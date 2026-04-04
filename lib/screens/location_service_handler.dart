// lib/screens/location_service_handler.dart
import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ✅ استخدام أنواع البيانات المتوافقة مع النظام الجديد
import 'package:google_maps_flutter/google_maps_flutter.dart';

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();

  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
  } catch (e) {
    debugPrint("Firebase Initialization Error: $e");
  }

  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((event) => service.setAsForegroundService());
    service.on('setAsBackground').listen((event) => service.setAsBackgroundService());
  }

  StreamSubscription<Position>? positionStream;
  StreamSubscription<DocumentSnapshot>? orderListener;

  Future<void> stopEverything() async {
    await positionStream?.cancel();
    await orderListener?.cancel();
    service.stopSelf();
  }

  service.on('stopService').listen((event) async => await stopEverything());

  final prefs = await SharedPreferences.getInstance();
  String? uid = prefs.getString('driver_uid');
  // ✅ التأكد من جلب رقم الطلب لمراقبته
  String? activeOrderId = prefs.getString('active_order_id');

  // --- مراقبة حالة الطلب لإغلاق الخدمة آلياً ---
  if (uid != null && activeOrderId != null) {
    orderListener = FirebaseFirestore.instance
        .collection('specialRequests')
        .doc(activeOrderId)
        .snapshots()
        .listen((snapshot) async {
      if (snapshot.exists) {
        String status = snapshot.data()?['status'] ?? '';
        
        // الحالات التي تستوجب إخلاء العهدة وإيقاف التتبع
        List<String> exitStatuses = [
          'delivered',
          'cancelled_by_user_after_accept',
          'driver_cancelled_reseeking',
          'returned_successfully'
        ];

        if (exitStatuses.contains(status)) {
          await FirebaseFirestore.instance.collection('freeDrivers').doc(uid).update({
            'currentStatus': 'online',
            'activeOrderId': "",
            'lastSeen': FieldValue.serverTimestamp(),
          });
          await stopEverything();
        }
      }
    });
  }

  // --- تتبع الموقع المتوافق مع جوجل مابس ---
  positionStream = Geolocator.getPositionStream(
    locationSettings: AndroidSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10,
      intervalDuration: const Duration(seconds: 10), // تحديث كل 10 ثواني في الخلفية كافٍ جداً
      foregroundNotificationConfig: const ForegroundNotificationConfig(
        notificationText: "جاري تحديث المسار لضمان استحقاق نقاط التأمين المحجوزة",
        notificationTitle: "رابية أحلى: نظام التأمين نشط 🛡️",
        enableWakeLock: true,
      ),
    ),
  ).listen((Position position) async {
    if (uid != null) {
      try {
        await FirebaseFirestore.instance.collection('freeDrivers').doc(uid).update({
          'location': GeoPoint(position.latitude, position.longitude),
          'lat': position.latitude,
          'lng': position.longitude,
          'heading': position.heading, // مهم جداً لدوران الماركر
          'speed': position.speed,
          'lastSeen': FieldValue.serverTimestamp(),
        });

        service.invoke('updateLocation', {
          "latitude": position.latitude,
          "longitude": position.longitude,
          "heading": position.heading,
        });
      } catch (e) {
        debugPrint("Background Update Error: $e");
      }
    }
  });
}


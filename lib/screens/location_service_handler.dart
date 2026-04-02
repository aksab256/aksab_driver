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

// ✅ إضافة مكتبة جوجل مابس لاستخدام أنواع البيانات المتوافقة مع النظام الجديد
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

  // مراجع للـ Streams عشان نقفلهم صح
  StreamSubscription<Position>? positionStream;
  StreamSubscription<DocumentSnapshot>? orderListener;

  // دالة الإغلاق النظيف للموارد
  Future<void> stopEverything() async {
    await positionStream?.cancel();
    await orderListener?.cancel();
    service.stopSelf();
  }

  service.on('stopService').listen((event) async => await stopEverything());

  final prefs = await SharedPreferences.getInstance();
  String? uid = prefs.getString('driver_uid');
  // بنجيب رقم الطلب الحالي من التخزين (لازم نكون حفظناه في الصفحة قبل تشغيل الخدمة)
  String? activeOrderId = prefs.getString('active_order_id');

  // --- الجزء الخاص بمراقبة حالة الطلب من الخلفية (بدون أي تغيير في المنطق) ---
  if (uid != null && activeOrderId != null) {
    orderListener = FirebaseFirestore.instance
        .collection('specialRequests')
        .doc(activeOrderId)
        .snapshots()
        .listen((snapshot) async {
      if (snapshot.exists) {
        String status = snapshot.data()?['status'] ?? '';

        // الحالات التي تستوجب إيقاف الخدمة فوراً من الخلفية
        List<String> exitStatuses = [
          'delivered',
          'cancelled_by_user_after_accept',
          'driver_cancelled_reseeking',
          'returned_successfully'
        ];

        if (exitStatuses.contains(status)) {
          // تحديث المندوب ليكون متاحاً مرة أخرى قبل قفل الخدمة
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

  // --- تتبع الموقع الحي المتوافق مع جوجل مابس ---
  positionStream = Geolocator.getPositionStream(
    locationSettings: const AndroidSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10,
      intervalDuration: Duration(seconds: 15),
    ),
  ).listen((Position position) async {
    if (service is AndroidServiceInstance) {
      // استخدام المصطلحات اللوجيستية المتفق عليها (نظام التأمين والعهدة)
      service.setForegroundNotificationInfo(
        title: "أكسب: نظام التأمين نشط 🛡️",
        content: "يتم تحديث المسار لضمان استحقاق النقاط المحجوزة",
      );
    }

    if (uid != null) {
      try {
        // ✅ تحديث البيانات في Firestore لتكون جاهزة للقراءة من أي تطبيق يستخدم جوجل مابس
        await FirebaseFirestore.instance.collection('freeDrivers').doc(uid).update({
          'location': GeoPoint(position.latitude, position.longitude),
          'lat': position.latitude,
          'lng': position.longitude,
          'lastSeen': FieldValue.serverTimestamp(),
          'speed': position.speed,
          'heading': position.heading,
        });

        // ✅ إرسال إشعار لحظي للتطبيق (في حال كان المندوب فاتح الشاشة) بنوع بيانات متوافق
        service.invoke('updateLocation', {
          "latitude": position.latitude,
          "longitude": position.longitude,
        });

      } catch (e) {
        debugPrint("Update Error: $e");
      }
    }
  });
}


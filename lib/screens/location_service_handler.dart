import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  // 1. تهيئة البيئة البرمجية الأساسية
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp();
  }

  // 2. إعداد واجهة الإشعارات للأندرويد
  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService();
    });

    service.on('setAsBackground').listen((event) {
      service.setAsBackgroundService();
    });
  }

  // 3. الاستماع لأمر الإيقاف وتصفية الموارد
  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  // 4. نظام التتبع الذكي (Stream) لتقليل استهلاك البطارية
  // بدلاً من التايمر، هنستخدم جيريوسنسور بيحس بالحركة
  const LocationSettings locationSettings = AndroidSettings(
    accuracy: LocationAccuracy.high,
    distanceFilter: 10, // لن يتم تحديث الموقع إلا إذا تحرك المندوب 10 أمتار على الأقل
    foregroundServiceBehavior: ForegroundServiceBehavior.continueService,
    intervalDuration: Duration(seconds: 15), // حد أدنى للوقت بين التحديثات
  );

  StreamSubscription<Position>? positionStream;

  positionStream = Geolocator.getPositionStream(locationSettings: locationSettings)
      .listen((Position position) async {
    
    if (service is AndroidServiceInstance) {
      if (await service.isForegroundService()) {
        // تحديث الإشعار لإظهار أن النظام يعمل بكفاءة
        service.setForegroundNotificationInfo(
          title: "أكسب: تأمين العهدة نشط 🛡️",
          content: "موقعك محدث: ${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)}",
        );
      }
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      String? uid = prefs.getString('driver_uid');

      if (uid != null) {
        // تحديث الفايربيز فقط عند حدوث حركة حقيقية
        await FirebaseFirestore.instance.collection('freeDrivers').doc(uid).update({
          'location': GeoPoint(position.latitude, position.longitude),
          'lastSeen': FieldValue.serverTimestamp(),
          'speed': position.speed, // ميزة إضافية لمعرفة سرعة المندوب
        });
      }
    } catch (e) {
      debugPrint("Firebase Background Update Error: $e");
    }
  });

  // في حالة إغلاق الخدمة، نوقف الـ Stream تماماً
  service.on('stopService').listen((event) {
    positionStream?.cancel();
    service.stopSelf();
  });
}

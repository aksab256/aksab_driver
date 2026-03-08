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
  // 1. تهيئة البيئة البرمجية الأساسية لضمان عمل المكونات في الخلفية
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
  } catch (e) {
    debugPrint("Firebase Initialization Error: $e");
  }

  // 2. إعدادات التحكم في خدمة الأندرويد
  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService();
    });

    service.on('setAsBackground').listen((event) {
      service.setAsBackgroundService();
    });
  }

  // 3. الاستماع لأمر الإيقاف
  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  // 4. إعدادات الموقع المتوافقة مع جميع نسخ geolocator (تجنباً لأخطاء الـ Build)
  // تم إزالة foregroundServiceBehavior لأنه يسبب تعارض في بعض النسخ
  // وتم استبداله بـ AppleSettings و AndroidSettings عامة
  final LocationSettings locationSettings = AndroidSettings(
    accuracy: LocationAccuracy.high,
    distanceFilter: 10, // تحديث كل 10 أمتار لتوفير البطارية والداتا
    intervalDuration: const Duration(seconds: 15),
  );

  StreamSubscription<Position>? positionStream;

  // 5. بدء تدفق البيانات (Stream)
  positionStream = Geolocator.getPositionStream(locationSettings: locationSettings)
      .listen((Position position) async {
    
    if (service is AndroidServiceInstance) {
      // تحديث الإشعار لضمان الشفافية مع المندوب ومع جوجل
      service.setForegroundNotificationInfo(
        title: "أكسب: تأمين العهدة نشط 🛡️",
        content: "يتم الآن تتبع مسار الرحلة لضمان مستحقاتك",
      );
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      String? uid = prefs.getString('driver_uid');

      if (uid != null && uid.isNotEmpty) {
        // تحديث الفايربيز بالحقول الموحدة
        await FirebaseFirestore.instance.collection('freeDrivers').doc(uid).update({
          'location': GeoPoint(position.latitude, position.longitude),
          'lat': position.latitude,
          'lng': position.longitude,
          'lastSeen': FieldValue.serverTimestamp(),
          'speed': position.speed, // مفيد جداً لحساب وقت الوصول المتوقع
          'heading': position.heading, // اتجاه حركة المندوب
        });
      }
    } catch (e) {
      debugPrint("Firebase Update Error: $e");
    }
  });

  // تنظيف الموارد عند إيقاف الخدمة
  service.on('stopService').listen((event) {
    positionStream?.cancel();
    service.stopSelf();
  });
}

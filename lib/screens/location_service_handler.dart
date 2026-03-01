import 'dart:async';
import 'dart:ui';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart'; // مهم جداً للأندرويد
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  // التأكد من تهيئة الإضافات والفايربيز داخل بيئة الخلفية (Background Isolate)
  DartPluginRegistrant.ensureInitialized();
  if (Firebase.apps.isEmpty) await Firebase.initializeApp();

  // الاستماع لأمر إيقاف الخدمة من التطبيق الرئيسي
  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  // دورة تحديث الموقع كل 10 ثوانٍ
  Timer.periodic(const Duration(seconds: 10), (timer) async {
    // التحقق إذا كانت الخدمة ما زالت تعمل قبل تنفيذ أي كود
    if (service is AndroidServiceInstance) {
      if (!(await service.isForegroundService())) {
        // إذا لم تعد الخدمة في الواجهة، لا داعي لتحديث الإشعار أو الموقع
        return;
      }

      // تحديث محتوى الإشعار الظاهر للمندوب لضمان الشفافية
      service.setForegroundNotificationInfo(
        title: "أكسب: تأمين العهدة نشط 🛡️",
        content: "جاري تتبع مسار الرحلة لضمان استرداد نقاط التأمين فور الوصول",
      );
    }

    try {
      // الحصول على الموقع الحالي بدقة عالية
      Position pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      
      // جلب معرف المندوب المخزن في SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      String? uid = prefs.getString('driver_uid');

      if (uid != null) {
        // تحديث مجموعة freeDrivers في فايربيز لتمكين التتبع الحي
        await FirebaseFirestore.instance.collection('freeDrivers').doc(uid).update({
          'location': GeoPoint(pos.latitude, pos.longitude),
          'lastSeen': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      // طباعة الخطأ في الـ Debug Console فقط للتطوير
      print("Background Service Error: $e");
    }
  });
}

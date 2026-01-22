import 'dart:async';
import 'dart:ui';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

Future<void> initializeService() async {
  final service = FlutterBackgroundService();

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart, // الدالة اللي هتشتغل في الخلفية
      autoStart: false,
      isForegroundMode: true,
      notificationChannelId: 'aksab_tracking_channel',
      initialNotificationTitle: 'أكسب: رحلة قيد التنفيذ',
      initialNotificationContent: 'جاري تحديث موقعك لضمان جودة التوصيل',
      foregroundServiceNotificationId: 888,
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: onStart,
    ),
  );
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  if (Firebase.apps.isEmpty) await Firebase.initializeApp();

  // جلب البيانات المخزنة محلياً (UID والـ OrderId)
  // ملحوظة: المكتبة دي بتستخدم نظام "Invoke" للتواصل
  
  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  // مؤقت لتحديث الموقع كل 10 ثواني
  Timer.periodic(const Duration(seconds: 10), (timer) async {
    if (service is AndroidServiceInstance) {
      if (!(await service.isForegroundService())) return;
    }

    Position pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
    
    // هنا بنحدث الفايربيس (محتاجين نمرر الـ UID للخدمة)
    // هنفترض إننا خزناه في SharedPreferences قبل ما نشغل الخدمة
    // أو نحدثه من خلال الـ Firestore مباشرة لو معانا الـ ID
    
    print("Background Location: ${pos.latitude}");
  });
}

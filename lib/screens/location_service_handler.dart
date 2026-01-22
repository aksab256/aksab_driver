import 'dart:async';
import 'dart:isolate';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(LocationTaskHandler());
}

class LocationTaskHandler extends TaskHandler {
  String? _orderId;
  String? _uid;
  double _lastLat = 0;
  double _lastLng = 0;

  @override
  Future<void> onStart(DateTime timestamp, SendPort? sendPort) async {
    // مهم جداً للأصدارات المستقرة: التأكد من تهيئة Firebase داخل الـ Isolate
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
    } catch (e) {
      print("Firebase Init Error in Background: $e");
    }

    _orderId = await FlutterForegroundTask.getData<String>(key: 'orderId');
    _uid = await FlutterForegroundTask.getData<String>(key: 'uid');
  }

  @override
  Future<void> onRepeatEvent(DateTime timestamp, SendPort? sendPort) async {
    // جلب الموقع
    Position pos = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high
    );

    double dist = Geolocator.distanceBetween(_lastLat, _lastLng, pos.latitude, pos.longitude);

    // لو المندوب تحرك أكتر من 10 متر أو دي أول نقطة
    if (dist > 10 || _lastLat == 0) {
      if (_uid != null) {
        await FirebaseFirestore.instance.collection('freeDrivers').doc(_uid).update({
          'location': GeoPoint(pos.latitude, pos.longitude),
          'lastSeen': FieldValue.serverTimestamp(),
        });
      }
      
      _lastLat = pos.latitude;
      _lastLng = pos.longitude;
      
      // إرسال الموقع للشاشة الرئيسية (لو التطبيق مفتوح)
      sendPort?.send(pos);
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp, SendPort? sendPort) async {
    // تنظيف الموارد لو لزم الأمر
  }

  // إضافة الدالة دي عشان نسخة 6.x.x ساعات بتطلبها في الـ Override
  @override
  void onButtonPressed(String id) {}
  
  @override
  void onNotificationPressed() {
    FlutterForegroundTask.launchApp();
  }
}

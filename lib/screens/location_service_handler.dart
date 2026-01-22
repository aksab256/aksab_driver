import 'dart:isolate';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

// الماكنة اللي بتشتغل في الخلفية (Isolate)
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
    // جلب البيانات المخزنة (رقم الطلب والـ UID)
    _orderId = await FlutterForegroundTask.getData<String>(key: 'orderId');
    _uid = await FlutterForegroundTask.getData<String>(key: 'uid');
  }

  @override
  Future<void> onRepeatEvent(DateTime timestamp, SendPort? sendPort) async {
    // جلب الموقع الحالي
    Position pos = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high
    );

    // حساب المسافة عن آخر نقطة اتبعتت
    double dist = Geolocator.distanceBetween(_lastLat, _lastLng, pos.latitude, pos.longitude);

    // المنطق الذكي: لو المندوب اتحرك أكتر من 10 متر (ممكن تخليها متغيرة)
    if (dist > 10) {
      // تحديث فايربيس مباشرة من الخلفية
      await FirebaseFirestore.instance.collection('freeDrivers').doc(_uid).update({
        'location': GeoPoint(pos.latitude, pos.longitude),
        'lastSeen': FieldValue.serverTimestamp(),
      });
      
      _lastLat = pos.latitude;
      _lastLng = pos.longitude;
      
      // إرسال الموقع للشاشة عشان الخريطة تتحرك لو التطبيق مفتوح
      sendPort?.send(pos);
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp, SendPort? sendPort) async {}
}

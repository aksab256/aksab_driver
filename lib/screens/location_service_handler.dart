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
  String? _uid;
  double _lastLat = 0;
  double _lastLng = 0;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    // تهيئة فايربيس
    if (Firebase.apps.isEmpty) await Firebase.initializeApp();
    
    // جلب الـ UID
    _uid = await FlutterForegroundTask.getData<String>(key: 'uid');
  }

  @override
  void onRepeatEvent(DateTime timestamp) async {
    // جلب الموقع
    Position pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);

    double dist = Geolocator.distanceBetween(_lastLat, _lastLng, pos.latitude, pos.longitude);

    if (dist > 10 || _lastLat == 0) {
      if (_uid != null) {
        await FirebaseFirestore.instance.collection('freeDrivers').doc(_uid).update({
          'location': GeoPoint(pos.latitude, pos.longitude),
          'lastSeen': FieldValue.serverTimestamp(),
        });
      }
      _lastLat = pos.latitude;
      _lastLng = pos.longitude;
      
      // إرسال البيانات للـ UI لو محتاج (اختياري في نسخة 9)
      FlutterForegroundTask.sendDataToMain(pos.toJson());
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}

import 'dart:async';
import 'dart:ui';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  if (Firebase.apps.isEmpty) await Firebase.initializeApp();

  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  Timer.periodic(const Duration(seconds: 10), (timer) async {
    try {
      Position pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      
      final prefs = await SharedPreferences.getInstance();
      String? uid = prefs.getString('driver_uid');

      if (uid != null) {
        // تحديث مجموعة freeDrivers كما هو في الكود الأصلي
        await FirebaseFirestore.instance.collection('freeDrivers').doc(uid).update({
          'location': GeoPoint(pos.latitude, pos.longitude),
          'lastSeen': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      print("Background Service Error: $e");
    }
  });
}

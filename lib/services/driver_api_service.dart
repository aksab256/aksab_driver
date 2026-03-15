import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DriverApiService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  // 1. الاستماع لحالة المندوب (محسّنة مع منع الارتداد)
  static void listenToStatus(String uid, Function(String) onStatusChange) {
    if (uid.isEmpty) return;
    _db.collection('freeDrivers').doc(uid).snapshots().listen((snap) {
      if (snap.exists && snap.data() != null) {
        String serverStatus = snap.data()?['currentStatus'] ?? 'offline';
        onStatusChange(serverStatus);
        // حفظ الحالة محلياً للمزامنة
        saveLocalStatus(serverStatus);
      }
    });
  }

  // 2. تحديث الحالة (محسّنة: تحديث سريع ثم جلب الموقع في الخلفية)
  static Future<void> updateStatus(String uid, String status) async {
    try {
      // تحديث محلي فوري لمنع تصفير الزرار
      await saveLocalStatus(status);

      Map<String, dynamic> updateData = {
        'currentStatus': status,
        'lastSeen': FieldValue.serverTimestamp(),
      };

      // تحديث الحالة فوراً في Firestore قبل البدء في جلب الموقع الثقيل
      await _db.collection('freeDrivers').doc(uid).update(updateData);

      if (status == 'online') {
        _syncFcmToken(uid);
        
        // جلب الموقع في الخلفية (Don't await it to prevent UI freeze)
        _updateLocationBackground(uid);
      }
    } catch (e) {
      debugPrint("Update Status API Error: $e");
    }
  }

  // دالة جانبية لتحديث الموقع دون تعطيل زر الأونلاين
  static Future<void> _updateLocationBackground(String uid) async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.always || permission == LocationPermission.whileInUse) {
        Position pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 5), // مهلة زمنية لعدم التعليق
        );
        
        await _db.collection('freeDrivers').doc(uid).update({
          'location': GeoPoint(pos.latitude, pos.longitude),
          'lat': pos.latitude,
          'lng': pos.longitude,
        });
      }
    } catch (e) {
      debugPrint("Background Location Update Error: $e");
    }
  }

  // دالة الحفظ المحلي (جعلتها public لاستخدامها في الهوم)
  static Future<void> saveLocalStatus(String status) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('driver_last_status', status);
  }

  // دالة جلب الحالة المحلية
  static Future<String> getLocalStatus() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('driver_last_status') ?? 'offline';
  }

  // 3. الاستماع للطلبات النشطة (العهدة)
  static void listenToActiveOrders(String uid, Function(String?, String?) onOrderChange) {
    if (uid.isEmpty) return;
    _db.collection('specialRequests')
        .where('driverId', isEqualTo: uid)
        .where('status', whereIn: ['accepted', 'picked_up', 'returning_to_seller', 'returning_to_merchant'])
        .snapshots()
        .listen((snap) {
      if (snap.docs.isEmpty) {
        onOrderChange(null, null);
      } else {
        var doc = snap.docs.first;
        onOrderChange(doc.id, doc.data()['status']);
      }
    });
  }

  // 4. مزامنة توكن الإشعارات
  static Future<void> _syncFcmToken(String uid) async {
    try {
      String? token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await http.post(
          Uri.parse("https://5uex7vzy64.execute-api.us-east-1.amazonaws.com/V2/new_nofiction"),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode({
            "userId": uid,
            "fcmToken": token,
            "role": "free_driver"
          }),
        ).timeout(const Duration(seconds: 10));
      }
    } catch (e) {
      debugPrint("AWS Sync Token Error: $e");
    }
  }
}


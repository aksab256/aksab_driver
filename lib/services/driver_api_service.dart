import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/foundation.dart';

class DriverApiService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  // 1. الاستماع لحالة المندوب الحالية
  static void listenToStatus(String uid, Function(String) onStatusChange) {
    if (uid.isEmpty) return;
    _db.collection('freeDrivers').doc(uid).snapshots().listen((snap) {
      if (snap.exists) {
        onStatusChange(snap.data()?['currentStatus'] ?? 'offline');
      }
    });
  }

  // 2. الاستماع للطلبات النشطة (العهدة)
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

  // 3. تحديث الحالة (Online / Offline) مع الموقع الجغرافي
  static Future<void> updateStatus(String uid, String status) async {
    try {
      Map<String, dynamic> updateData = {
        'currentStatus': status,
        'lastSeen': FieldValue.serverTimestamp(),
      };

      if (status == 'online') {
        Position pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
        updateData['location'] = GeoPoint(pos.latitude, pos.longitude);
        updateData['lat'] = pos.latitude;
        updateData['lng'] = pos.longitude;
        
        // مزامنة التوكن عند فتح الحالة
        _syncFcmToken(uid);
      }

      await _db.collection('freeDrivers').doc(uid).update(updateData);
    } catch (e) {
      debugPrint("Update Status API Error: $e");
      rethrow;
    }
  }

  // 4. مزامنة توكن الإشعارات مع AWS (خاص بـ V2)
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


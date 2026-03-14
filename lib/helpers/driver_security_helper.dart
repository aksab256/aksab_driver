import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../screens/freelance_terms_screen.dart';

class DriverSecurityHelper {
  
  // 1. فحص الشروط والأحكام عند تسجيل الدخول
  static Future<void> checkSecurityAndTerms(BuildContext context, String uid) async {
    if (uid.isEmpty) return;
    try {
      var userDoc = await FirebaseFirestore.instance.collection('freeDrivers').doc(uid).get();
      if (userDoc.exists && !(userDoc.data()?['hasAcceptedTerms'] ?? false)) {
        if (!context.mounted) return;
        
        final result = await showModalBottomSheet<bool>(
          context: context,
          isScrollControlled: true,
          isDismissible: false,
          builder: (context) => FreelanceTermsScreen(userId: uid),
        );
        
        if (result == true) {
          showErrorSnackBar(context, "تم حفظ موافقتك القانونية بنجاح ✅");
          requestNotificationPermission(context);
        }
      } else {
        requestNotificationPermission(context);
      }
    } catch (e) {
      debugPrint("Security Check Error: $e");
    }
  }

  // 2. رسالة إفصاح الموقع (هامة جداً لجوجل)
  static Future<bool> requestLocationPermission(BuildContext context) async {
    // عرض رسالة الإفصاح أولاً
    bool? proceed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("خدمات الموقع 📍", style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
        content: const Text(
          "تطبيق 'أكسب مندوب' يجمع بيانات الموقع لتمكين تتبع الطلبات وتحديد أقرب المهام إليك، حتى عند إغلاق التطبيق. هذا يضمن وصول الإشعارات الجغرافية الصحيحة لعهدتك."
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("لاحقاً")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange[900]),
            onPressed: () => Navigator.pop(context, true),
            child: const Text("موافق ومتابعة", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (proceed != true) return false;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return (permission == LocationPermission.always || permission == LocationPermission.whileInUse);
  }

  // 3. رسالة إفصاح الإشعارات
  static Future<void> requestNotificationPermission(BuildContext context) async {
    FirebaseMessaging messaging = FirebaseMessaging.instance;
    NotificationSettings current = await messaging.getNotificationSettings();

    if (current.authorizationStatus != AuthorizationStatus.authorized) {
      if (!context.mounted) return;
      
      bool? agree = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text("تنبيهات العهدة 🔔", style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
          content: const Text("يرجى تفعيل الإشعارات لتصلك تنبيهات المهام الجديدة وتحديثات حالة الأمانات لحظياً."),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange[900]),
              onPressed: () => Navigator.pop(context, true),
              child: const Text("تفعيل الآن", style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );

      if (agree == true) {
        await messaging.requestPermission(alert: true, badge: true, sound: true);
      }
    }
  }

  // 4. الحركة الشيك (SnackBar) عند التحول لـ Online
  static void showOnlineHint(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 4),
        backgroundColor: Colors.green[800],
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        content: const Row(
          children: [
            Icon(Icons.radar, color: Colors.white),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                "أنت الآن في الرادار! ستصلك إشعارات بالطلبات القريبة طول ما أنت 'متصل'. للراحة، حول حالتك لـ 'أوفلاين'.",
                style: TextStyle(fontFamily: 'Cairo', fontSize: 11),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 5. عرض رسائل الخطأ الموحدة
  static void showErrorSnackBar(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, textAlign: TextAlign.center, style: const TextStyle(fontFamily: 'Cairo')),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.redAccent,
      ),
    );
  }
}


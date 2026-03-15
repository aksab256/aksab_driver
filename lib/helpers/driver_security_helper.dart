import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../screens/freelance_terms_screen.dart';

class DriverSecurityHelper {

  // 1. فحص الشروط والأحكام - نسخة معدلة لمنع الهروب (Blocking Mode)
  static Future<void> checkSecurityAndTerms(BuildContext context, String uid) async {
    if (uid.isEmpty) return;
    try {
      var userDoc = await FirebaseFirestore.instance.collection('freeDrivers').doc(uid).get();
      
      // نتحقق من الحقل البرمجي الثابت hasAcceptedTerms
      if (userDoc.exists && !(userDoc.data()?['hasAcceptedTerms'] ?? false)) {
        if (!context.mounted) return;

        // استخدام showDialog بدلاً من BottomSheet لضمان السيطرة الكاملة
        final result = await showDialog<bool>(
          context: context,
          barrierDismissible: false, // يمنع الإغلاق بالضغط خارج الصندوق
          builder: (context) => PopScope(
            canPop: false, // يمنع زر الرجوع في الأندرويد
            child: Dialog.fullscreen( // عرض ملء الشاشة لعرض الشروط بوضوح
              child: FreelanceTermsScreen(userId: uid),
            ),
          ),
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

  // 2. رسالة إفصاح الموقع (إجبارية لمتجر جوجل)
  static Future<bool> requestLocationPermission(BuildContext context) async {
    bool? proceed = await showDialog<bool>(
      context: context,
      barrierDismissible: false, // يمنع المندوب من تجاهل الرسالة بالضغط حولها
      builder: (context) => PopScope(
        canPop: false,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text("خدمات الموقع 📍", 
            style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold), textAlign: TextAlign.right),
          content: const Text(
            "تطبيق 'أكسب مندوب' يجمع بيانات الموقع لتمكين تتبع الطلبات وتحديد أقرب المهام إليك، حتى عند إغلاق التطبيق أو عدم استخدامه. هذا يضمن وصول إشعارات العهدة والطلبات القريبة منك بدقة.",
            textAlign: TextAlign.right, style: TextStyle(fontFamily: 'Cairo')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false), 
              child: const Text("لاحقاً", style: TextStyle(fontFamily: 'Cairo'))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange[900]),
              onPressed: () => Navigator.pop(context, true),
              child: const Text("موافق ومتابعة", style: TextStyle(color: Colors.white, fontFamily: 'Cairo')),
            ),
          ],
        ),
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
        barrierDismissible: false,
        builder: (context) => PopScope(
          canPop: false,
          child: AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text("تنبيهات العهدة 🔔", 
              style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold), textAlign: TextAlign.right),
            content: const Text(
              "يرجى تفعيل الإشعارات لتصلك تنبيهات المهام الجديدة وتحديثات حالة الأمانات في عهدتك لحظياً.",
              textAlign: TextAlign.right, style: TextStyle(fontFamily: 'Cairo')),
            actions: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.orange[900]),
                onPressed: () => Navigator.pop(context, true),
                child: const Text("تفعيل الآن", style: TextStyle(color: Colors.white, fontFamily: 'Cairo')),
              ),
            ],
          ),
        ),
      );
      if (agree == true) {
        await messaging.requestPermission(alert: true, badge: true, sound: true);
      }
    }
  }

  // 4. السناك بار عند تفعيل الرادار
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
                "أنت الآن في الرادار! ستصلك إشعارات بالطلبات القريبة. للراحة، حول حالتك لـ 'أوفلاين' عند الانتهاء.",
                style: TextStyle(fontFamily: 'Cairo', fontSize: 11),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 5. رسائل الخطأ الموحدة
  static void showErrorSnackBar(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, textAlign: TextAlign.center, style: const TextStyle(fontFamily: 'Cairo')),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.redAccent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}


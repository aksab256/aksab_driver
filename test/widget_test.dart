import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// ⚠️ ملاحظة مهمة: الاسم الصحيح للحزمة (package name) لازم يطابق قيمة
// "name:" الموجودة في أول pubspec.yaml بتاعك. لو مختلف، غيّر السطر اللي تحت.
import 'package:aksab_driver/main.dart';

void main() {
  // ✅ إصلاح: الكلاس الأساسي اسمه AksabDriverApp مش MyApp
  // (MyApp كان اسم افتراضي من قالب Flutter الأصلي ومحصلش تحديث هنا)
  testWidgets('App builds without throwing', (WidgetTester tester) async {
    // ⚠️ تنبيه: التطبيق ده بيستخدم Firebase.initializeApp() و Firestore و
    // FirebaseAuth.authStateChanges() داخل AuthWrapper. لازم يكون عندك
    // firebase mocks متظبطة (زي حزمة firebase_auth_mocks أو fake_cloud_firestore)
    // وإلا الاختبار ده هيفشل فعليًا وقت التشغيل مش وقت الـ compile بس.
    // من غير Mocking، الأفضل إنك تحذف هذا التيست أو تستبدله بتيست Unit
    // على منطق منفصل عن Firebase.

    await tester.pumpWidget(const AksabDriverApp());

    // مجرد تأكيد إن الشجرة بنت بدون Exception أثناء أول فريم
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // ضرورية لإغلاق التطبيق برمجياً
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:sizer/sizer.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'dart:ui'; 

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'screens/login_screen.dart';
import 'screens/register_screen.dart';
import 'screens/free_driver_home_screen.dart';
import 'screens/CompanyRepHomeScreen.dart';
import 'screens/delivery_admin_dashboard.dart'; 

// متغير عالمي لتتبع توقيت ضغطة زر الرجوع
DateTime? _lastPressedAt;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  // ✅ 1. إعدادات Crashlytics
  FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
  PlatformDispatcher.instance.onError = (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true;
  };

  // ✅ 2. تعريف قناة الإشعارات
  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'aksab_tracking_channel', 
    'تتبع رحلات أكسب',
    description: 'تستخدم لتتبع موقع المندوب أثناء الرحلة لضمان جودة الخدمة',
    importance: Importance.high,
  );

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
  
  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  runApp(AksabDriverApp());
}

class AksabDriverApp extends StatelessWidget {
  // مفتاح عالمي للتحكم في التنقل (Navigator) ومنع الخروج
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return Sizer(
      builder: (context, orientation, deviceType) {
        return MaterialApp(
          navigatorKey: navigatorKey, // ربط المفتاح هنا ضروري جداً
          title: 'أكسب كابتن',
          debugShowCheckedModeBanner: false,
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('ar', 'EG')],
          locale: const Locale('ar', 'EG'),
          theme: ThemeData(
            primarySwatch: Colors.orange,
            fontFamily: 'Tajawal',
            scaffoldBackgroundColor: Colors.white,
          ),
          // ✅ تغليف الـ AuthWrapper بـ PopScope للتحكم في زر الرجوع
          home: PopScope(
            canPop: false, // نمنع الخروج التلقائي
            onPopInvokedWithResult: (didPop, result) async {
              if (didPop) return;

              final NavigatorState? navigator = navigatorKey.currentState;

              // أولاً: إذا كان هناك صفحات مفتوحة (مثل المحفظة أو التفاصيل)، ارجع للرئيسية
              if (navigator != null && navigator.canPop()) {
                navigator.pop();
                return;
              }

              // ثانياً: إذا كان المستخدم في الصفحة الرئيسية، نطلب منه الضغط مرتين للخروج
              final now = DateTime.now();
              const backButtonInterval = Duration(seconds: 2);

              if (_lastPressedAt == null || now.difference(_lastPressedAt!) > backButtonInterval) {
                _lastPressedAt = now;
                
                // إظهار رسالة تنبيه للمندوب
                ScaffoldMessenger.of(navigator!.context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'إضغط مرة أخرى للخروج من التطبيق',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontFamily: 'Tajawal'),
                    ),
                    backgroundColor: Colors.black87,
                    duration: Duration(seconds: 2),
                  ),
                );
                return;
              }

              // إذا ضغط المرة الثانية خلال ثانيتين، نغلق التطبيق فعلياً
              SystemNavigator.pop();
            },
            child: AuthWrapper(),
          ),
          routes: {
            '/login': (context) => LoginScreen(),
            '/register': (context) => RegisterScreen(),
            '/free_home': (context) => const FreeDriverHomeScreen(),
            '/company_home': (context) => const CompanyRepHomeScreen(),
            '/admin_dashboard': (context) => const DeliveryAdminDashboard(),
          },
        );
      },
    );
  }
}

class AuthWrapper extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        if (snapshot.hasData) {
          final uid = snapshot.data!.uid;

          return FutureBuilder<Map<String, dynamic>?>(
            future: _getUserRoleAndData(uid),
            builder: (context, roleSnapshot) {
              if (roleSnapshot.connectionState == ConnectionState.waiting) {
                return const Scaffold(body: Center(child: CircularProgressIndicator()));
              }

              final userData = roleSnapshot.data;
              if (userData != null) {
                final String type = userData['type'];
                final String status = userData['status'] ?? '';

                if (type == 'deliveryRep' && status == 'approved') {
                  return const CompanyRepHomeScreen();
                } 
                else if (type == 'freeDriver' && status == 'approved') {
                  return const FreeDriverHomeScreen();
                } 
                else if (type == 'manager') {
                  String role = userData['role'] ?? '';
                  if (role == 'delivery_manager' || role == 'delivery_supervisor') {
                    return const DeliveryAdminDashboard();
                  }
                }
              }
              return const LoginScreen();
            },
          );
        }
        return const LoginScreen();
      },
    );
  }

  Future<Map<String, dynamic>?> _getUserRoleAndData(String uid) async {
    var repDoc = await FirebaseFirestore.instance.collection('deliveryReps').doc(uid).get();
    if (repDoc.exists) return {...repDoc.data()!, 'type': 'deliveryRep'};

    var freeDoc = await FirebaseFirestore.instance.collection('freeDrivers').doc(uid).get();
    if (freeDoc.exists) return {...freeDoc.data()!, 'type': 'freeDriver'};

    var managerSnap = await FirebaseFirestore.instance
        .collection('managers')
        .where('uid', isEqualTo: uid)
        .get();
        
    if (managerSnap.docs.isNotEmpty) {
      return {...managerSnap.docs.first.data(), 'type': 'manager'};
    }
    return null;
  }
}

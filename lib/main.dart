import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:sizer/sizer.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// استيراد الشاشات (تأكد من أن المسارات صحيحة في مشروعك)
import 'screens/login_screen.dart';
import 'screens/register_screen.dart';
import 'screens/free_driver_home_screen.dart';
import 'screens/CompanyRepHomeScreen.dart';
import 'screens/delivery_admin_dashboard.dart'; 

void main() async {
  // ✅ ضروري جداً لضمان عمل الـ Binding قبل أي عملية Firebase أو Background
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(AksabDriverApp());
}

class AksabDriverApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Sizer(
      builder: (context, orientation, deviceType) {
        return MaterialApp(
          title: 'أكساب المندوب',
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
            fontFamily: 'Tajawal', // تأكد من إضافة الخط في الـ pubspec
            scaffoldBackgroundColor: Colors.white,
          ),
          home: AuthWrapper(),
          // ✅ الحفاظ على جميع المسارات الأصلية
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

                // 1. منطق مناديب الشركة
                if (type == 'deliveryRep' && status == 'approved') {
                  return const CompanyRepHomeScreen();
                } 
                // 2. منطق المناديب الأحرار
                else if (type == 'freeDriver' && status == 'approved') {
                  return const FreeDriverHomeScreen();
                } 
                // 3. منطق طاقم الإدارة
                else if (type == 'manager') {
                  String role = userData['role'] ?? '';
                  if (role == 'delivery_manager' || role == 'delivery_supervisor') {
                    return const DeliveryAdminDashboard();
                  }
                }
              }

              // إذا لم يتطابق أو الحساب معلق
              return const LoginScreen();
            },
          );
        }

        return const LoginScreen();
      },
    );
  }

  // ✅ الدالة الأصلية كما هي مع التأكد من الـ Collections الصحيحة
  Future<Map<String, dynamic>?> _getUserRoleAndData(String uid) async {
    // 1. فحص مناديب الشركة
    var repDoc = await FirebaseFirestore.instance.collection('deliveryReps').doc(uid).get();
    if (repDoc.exists) return {...repDoc.data()!, 'type': 'deliveryRep'};

    // 2. فحص المناديب الأحرار (المجموعة المستهدفة بالتتبع)
    var freeDoc = await FirebaseFirestore.instance.collection('freeDrivers').doc(uid).get();
    if (freeDoc.exists) return {...freeDoc.data()!, 'type': 'freeDriver'};

    // 3. فحص المديرين
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

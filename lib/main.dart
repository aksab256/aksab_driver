import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:sizer/sizer.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// استيراد الشاشات - أضفنا صفحة الشركة هنا
import 'screens/login_screen.dart';
import 'screens/register_screen.dart';
import 'screens/free_driver_home_screen.dart';
import 'screens/CompanyRepHomeScreen.dart'; 

void main() async {
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
          localizationsDelegates: [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: [Locale('ar', 'EG')],
          locale: Locale('ar', 'EG'),
          theme: ThemeData(
            primarySwatch: Colors.orange,
            fontFamily: 'Tajawal',
            scaffoldBackgroundColor: Colors.white,
          ),
          home: AuthWrapper(),
          routes: {
            '/login': (context) => LoginScreen(),
            '/register': (context) => RegisterScreen(),
            '/free_home': (context) => const FreeDriverHomeScreen(),
            '/company_home': (context) => const CompanyRepHomeScreen(), // تعريف المسار
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
        if (snapshot.hasData) {
          final uid = snapshot.data!.uid;

          return FutureBuilder<DocumentSnapshot>(
            // بنجرب نبحث في كولكشن الشركة الأول
            future: FirebaseFirestore.instance.collection('deliveryReps').doc(uid).get(),
            builder: (context, repSnap) {
              if (repSnap.connectionState == ConnectionState.waiting) {
                return const Scaffold(body: Center(child: CircularProgressIndicator()));
              }

              // 1. لو طلع مندوب شركة
              if (repSnap.hasData && repSnap.data!.exists) {
                var data = repSnap.data!.data() as Map<String, dynamic>;
                if (data['status'] == 'approved') {
                  return const CompanyRepHomeScreen();
                }
              }

              // 2. لو مش شركة، نبحث في الأحرار
              return FutureBuilder<DocumentSnapshot>(
                future: FirebaseFirestore.instance.collection('freeDrivers').doc(uid).get(),
                builder: (context, freeSnap) {
                  if (freeSnap.connectionState == ConnectionState.waiting) {
                    return const Scaffold(body: Center(child: CircularProgressIndicator()));
                  }

                  if (freeSnap.hasData && freeSnap.data!.exists) {
                    var data = freeSnap.data!.data() as Map<String, dynamic>;
                    if (data['status'] == 'approved') {
                      return const FreeDriverHomeScreen();
                    }
                  }

                  // لو مش موجود في الاتنين أو مش مقبول
                  FirebaseAuth.instance.signOut();
                  return LoginScreen();
                },
              );
            },
          );
        }
        return LoginScreen();
      },
    );
  }
}


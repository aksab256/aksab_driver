import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:sizer/sizer.dart';
import 'package:firebase_auth/firebase_auth.dart';

// استدعاء الشاشات - تأكد من مطابقة المسارات لمجلدات مشروعك
import 'screens/delivery_admin_dashboard.dart';
import 'screens/login_screen.dart';

// 1. معالج الإشعارات في الخلفية - يجب أن يكون خارج أي كلاس
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // تأكد من تهيئة Firebase داخل المعالج في الخلفية
  await Firebase.initializeApp();
  debugPrint("📩 إشعار في الخلفية: ${message.messageId}");
}

void main() async {
  // 2. تأكيد تهيئة الـ Widgets قبل أي شيء
  WidgetsFlutterBinding.ensureInitialized();
  
  // 3. تهيئة Firebase الأساسية
  await Firebase.initializeApp();

  // 4. إعداد معالج الخلفية
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // 5. إعدادات الإشعارات أثناء فتح التطبيق (Foreground)
  await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
    alert: true,
    badge: true,
    sound: true,
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // استخدم Sizer لضمان استجابة التصميم (Responsive) في كل الشاشات
    return Sizer(
      builder: (context, orientation, deviceType) {
        return MaterialApp(
          title: 'أكسب كابتن',
          debugShowCheckedModeBanner: false,
          
          // إعدادات السمات (Theme) والخطوط
          theme: ThemeData(
            primaryColor: const Color(0xFF2C3E50),
            colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2C3E50)),
            fontFamily: 'Cairo', // يجب أن يكون معرفاً في pubspec.yaml
            useMaterial3: true,
          ),

          // 6. فحص حالة التوجيه (تلقائياً)
          home: const AuthCheck(),

          // تعريف المسارات (Routes) للتنقل السهل
          routes: {
            '/login': (context) => const LoginScreen(),
            '/dashboard': (context) => const DeliveryAdminDashboard(),
          },
        );
      },
    );
  }
}

// كود فحص حالة تسجيل الدخول (الطبقة الواقية)
class AuthCheck extends StatefulWidget {
  const AuthCheck({super.key});

  @override
  State<AuthCheck> createState() => _AuthCheckState();
}

class _AuthCheckState extends State<AuthCheck> {
  @override
  void initState() {
    super.initState();
    _setupTokenLog();
  }

  // دالة اختيارية لمساعدتك في الحصول على الـ Token الخاص بالجهاز للتجربة
  void _setupTokenLog() async {
    try {
      String? token = await FirebaseMessaging.instance.getToken();
      debugPrint("🚀 FCM Token: $token"); 
      // هذا الـ Token هو الذي تستخدمه لإرسال إشعار تجريبي من Firebase Console
    } catch (e) {
      debugPrint("❌ Error fetching token: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // حالة التحميل
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator(color: Color(0xFF2C3E50))),
          );
        }
        
        // إذا كان المستخدم مسجل دخول
        if (snapshot.hasData && snapshot.data != null) {
          return const DeliveryAdminDashboard();
        }
        
        // إذا لم يكن مسجل دخول
        return const LoginScreen();
      },
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:sizer/sizer.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'dart:ui';
import 'dart:async'; 
import 'package:connectivity_plus/connectivity_plus.dart'; 

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

// ✅ استيراد ملف الخدمة الخاص بك للوصول لـ onStart
import 'location_service_handler.dart'; 

import 'screens/login_screen.dart';
import 'screens/register_screen.dart';
import 'screens/free_driver_home_screen.dart';
import 'screens/CompanyRepHomeScreen.dart';
import 'screens/delivery_admin_dashboard.dart';

DateTime? _lastPressedAt;

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

// ✅ دالة تهيئة الخدمة: تجهيز الإعدادات بدون تشغيل (autoStart: false)
Future<void> initializeService() async {
  final service = FlutterBackgroundService();

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart, // الدالة الموجودة في ملف location_service_handler.dart
      autoStart: false, // ⚠️ لن تعمل الخدمة إلا بطلب يدوي من صفحة الأوردر
      isForegroundMode: true,
      notificationChannelId: 'high_importance_channel',
      initialNotificationTitle: 'أكسب: تأمين العهدة نشط 🛡️',
      initialNotificationContent: 'جاري مراقبة المسار لضمان أمان الطلب...',
      foregroundServiceNotificationId: 888,
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: onStart,
      onBackground: onIosBackground,
    ),
  );
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  return true;
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  // ✅ تهيئة إعدادات الخدمة
  await initializeService();

  FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
  PlatformDispatcher.instance.onError = (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true;
  };

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
  const AndroidInitializationSettings initializationSettingsAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
  const InitializationSettings initializationSettings = InitializationSettings(android: initializationSettingsAndroid);
  await flutterLocalNotificationsPlugin.initialize(initializationSettings);

  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'high_importance_channel',
    'إشعارات هامة',
    description: 'هذه القناة مخصصة لإشعارات الطلبات والعهدة الهامة.',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
  );

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // ✅ التأكد من إغلاق أي خدمة قديمة كانت عالقة في الرامات
  try {
    FlutterBackgroundService().invoke("stopService");
  } catch (e) {}

  runApp(AksabDriverApp());
}

class AksabDriverApp extends StatelessWidget {
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  AksabDriverApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Sizer(
      builder: (context, orientation, deviceType) {
        return MaterialApp(
          navigatorKey: navigatorKey,
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
          builder: (context, child) {
            return ConnectivityWrapper(child: child!);
          },
          home: PopScope(
            canPop: false,
            onPopInvokedWithResult: (didPop, result) async {
              if (didPop) return;
              final NavigatorState? navigator = navigatorKey.currentState;
              if (navigator != null && navigator.canPop()) {
                navigator.pop();
                return;
              }
              final now = DateTime.now();
              if (_lastPressedAt == null || now.difference(_lastPressedAt!) > const Duration(seconds: 2)) {
                _lastPressedAt = now;
                ScaffoldMessenger.of(navigator!.context).showSnackBar(
                  const SnackBar(
                    content: Text('إضغط مرة أخرى للخروج', textAlign: TextAlign.center, style: TextStyle(fontFamily: 'Tajawal')), 
                    backgroundColor: Colors.black87
                  ),
                );
                return;
              }
              SystemNavigator.pop();
            },
            child: const AuthWrapper(),
          ),
          routes: {
            '/login': (context) => const LoginScreen(),
            '/register': (context) => const RegisterScreen(),
            '/free_home': (context) => const FreeDriverHomeScreen(),
            '/company_home': (context) => const CompanyRepHomeScreen(),
            '/admin_dashboard': (context) => const DeliveryAdminDashboard(),
          },
        );
      },
    );
  }
}

// --- ويدجت مراقبة الإنترنت (ConnectivityWrapper) ---
class ConnectivityWrapper extends StatefulWidget {
  final Widget child;
  const ConnectivityWrapper({super.key, required this.child});
  @override
  _ConnectivityWrapperState createState() => _ConnectivityWrapperState();
}

class _ConnectivityWrapperState extends State<ConnectivityWrapper> {
  late StreamSubscription<List<ConnectivityResult>> _subscription;
  bool _isConnected = true;
  Timer? _connectivityTimer;

  @override
  void initState() {
    super.initState();
    _checkInitialConnectivity();
    _subscription = Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> result) {
      _updateConnectionStatus(result);
    });
  }

  Future<void> _checkInitialConnectivity() async {
    List<ConnectivityResult> result = await Connectivity().checkConnectivity();
    _updateConnectionStatus(result);
  }

  void _updateConnectionStatus(List<ConnectivityResult> result) {
    bool hasConnection = result.isNotEmpty && !result.contains(ConnectivityResult.none);
    if (hasConnection) {
      _connectivityTimer?.cancel();
      if (mounted && !_isConnected) setState(() => _isConnected = true);
    } else {
      _connectivityTimer?.cancel();
      _connectivityTimer = Timer(const Duration(seconds: 3), () {
        if (mounted && _isConnected) setState(() => _isConnected = false);
      });
    }
  }

  @override
  void dispose() {
    _subscription.cancel();
    _connectivityTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (!_isConnected)
          Positioned.fill(
            child: Container(
              color: Colors.white,
              child: Scaffold(
                backgroundColor: Colors.white,
                body: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.wifi_off_rounded, size: 100, color: Colors.redAccent),
                        const SizedBox(height: 20),
                        const Text("عذراً، لا يوجد اتصال بالإنترنت", 
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, fontFamily: 'Tajawal')),
                        const SizedBox(height: 10),
                        const Text("تأكد من تفعيل الواي فاي أو بيانات الهاتف للمتابعة", 
                          textAlign: TextAlign.center, 
                          style: TextStyle(fontSize: 14, color: Colors.grey, fontFamily: 'Tajawal')),
                        const SizedBox(height: 40),
                        const CircularProgressIndicator(color: Colors.orange),
                        const SizedBox(height: 15),
                        const Text("جاري إعادة الاتصال تلقائياً...", 
                          style: TextStyle(fontSize: 12, fontFamily: 'Tajawal', color: Colors.orange)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// --- AuthWrapper ---
class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.hasData) {
          return FutureBuilder<Map<String, dynamic>?>(
            future: _getUserRoleAndData(snapshot.data!.uid),
            builder: (context, roleSnapshot) {
              if (roleSnapshot.connectionState == ConnectionState.waiting) {
                return const Scaffold(body: Center(child: CircularProgressIndicator()));
              }
              if (roleSnapshot.data != null) {
                final d = roleSnapshot.data!;
                if (d['type'] == 'deliveryRep' && d['status'] == 'approved') return const CompanyRepHomeScreen();
                if (d['type'] == 'freeDriver' && d['status'] == 'approved') return const FreeDriverHomeScreen();
                if (d['type'] == 'manager') return const DeliveryAdminDashboard();
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
    try {
      var repDoc = await FirebaseFirestore.instance.collection('deliveryReps').doc(uid).get();
      if (repDoc.exists) return {...repDoc.data()!, 'type': 'deliveryRep'};
      var freeDoc = await FirebaseFirestore.instance.collection('freeDrivers').doc(uid).get();
      if (freeDoc.exists) return {...freeDoc.data()!, 'type': 'freeDriver'};
      var managerSnap = await FirebaseFirestore.instance.collection('managers').where('uid', isEqualTo: uid).get();
      if (managerSnap.docs.isNotEmpty) return {...managerSnap.docs.first.data(), 'type': 'manager'};
    } catch (e) { return null; }
    return null;
  }
}

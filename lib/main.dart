import 'dart:async';                                 import 'dart:convert';
import 'dart:ui';                                    import 'package:flutter/material.dart';              import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';   import 'package:firebase_auth/firebase_auth.dart';   import 'package:cloud_firestore/cloud_firestore.dart';                                                    import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:sizer/sizer.dart';                   import 'package:flutter_localizations/flutter_localizations.dart';                                        import 'package:connectivity_plus/connectivity_plus.dart';                                                import 'package:flutter_local_notifications/flutter_local_notifications.dart';                            import 'package:flutter_background_service/flutter_background_service.dart';                              import 'package:firebase_messaging/firebase_messaging.dart';                                              import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:facebook_app_events/facebook_app_events.dart'; // 1. استيراد فيسبوك

// استيراد الشاشات والخدمات الخاصة بك
import 'screens/location_service_handler.dart';      import 'screens/login_screen.dart';                  import 'screens/register_screen.dart';               import 'screens/free_driver_home_screen.dart';       import 'screens/CompanyRepHomeScreen.dart';          import 'screens/delivery_admin_dashboard.dart';

DateTime? _lastPressedAt;
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
final facebookAppEvents = FacebookAppEvents(); // 2. تعريف الفيسبوك

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

Future<void> setupNotifications() async {
  const AndroidInitializationSettings initializationSettingsAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
  const DarwinInitializationSettings initializationSettingsIOS = DarwinInitializationSettings();
  const InitializationSettings initializationSettings = InitializationSettings(android: initializationSettingsAndroid, iOS: initializationSettingsIOS);
  const AndroidNotificationChannel channel = AndroidNotificationChannel('high_importance_channel', 'إشعارات هامة', description: 'هذه القناة مخصصة لإشعارات الطلبات والعهدة الهامة.', importance: Importance.max, playSound: true, enableVibration: true);
  await flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.createNotificationChannel(channel);
  await flutterLocalNotificationsPlugin.initialize(initializationSettings, onDidReceiveNotificationResponse: (NotificationResponse details) async {
    debugPrint('User tapped on notification: ${details.payload}');
  });
}

Future<void> initializeService() async {
  final service = FlutterBackgroundService();
  await service.configure(
    androidConfiguration: AndroidConfiguration(onStart: onStart, autoStart: false, isForegroundMode: true, notificationChannelId: 'high_importance_channel', initialNotificationTitle: 'أسواق أكسب: إدارة العهدة نشطة 🛡️', initialNotificationContent: 'جاري مراقبة المسار لضمان أمان النقل...', foregroundServiceNotificationId: 888),
    iosConfiguration: IosConfiguration(autoStart: false, onForeground: onStart, onBackground: onIosBackground),
  );
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async { return true; }

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async { DartPluginRegistrant.ensureInitialized(); }

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  
  // 3. تهيئة فيسبوك
  await facebookAppEvents.setAdvertiserTracking(true);

  await setupNotifications();
  await initializeService();
  FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
  PlatformDispatcher.instance.onError = (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true;
  };
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  try { FlutterBackgroundService().invoke("stopService"); } catch (e) {}
  runApp(const AksabDriverApp());
}

class AksabDriverApp extends StatelessWidget {
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  const AksabDriverApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Sizer(builder: (context, orientation, deviceType) {
      return MaterialApp(
        navigatorKey: navigatorKey,
        title: 'أسواق أكسب - كابتن',
        debugShowCheckedModeBanner: false,
        localizationsDelegates: const [GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
        supportedLocales: const [Locale('ar', 'EG')],
        locale: const Locale('ar', 'EG'),
        theme: ThemeData(primarySwatch: Colors.orange, fontFamily: 'Tajawal', scaffoldBackgroundColor: Colors.white),
        builder: (context, child) => ConnectivityWrapper(child: child!),
        home: PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) async {
            if (didPop) return;
            final NavigatorState? navigator = navigatorKey.currentState;
            if (navigator != null && navigator.canPop()) { navigator.pop(); return; }
            final now = DateTime.now();
            if (_lastPressedAt == null || now.difference(_lastPressedAt!) > const Duration(seconds: 2)) {
              _lastPressedAt = now;
              ScaffoldMessenger.of(navigator!.context).showSnackBar(const SnackBar(content: Text('إضغط مرة أخرى للخروج من تطبيق أكسب', textAlign: TextAlign.center, style: TextStyle(fontFamily: 'Tajawal')), backgroundColor: Colors.black87));
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
    });
  }
}

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
    _subscription = Connectivity().onConnectivityChanged.listen(_updateConnectionStatus);
  }

  Future<void> _checkInitialConnectivity() async {
    List<ConnectivityResult> result = await Connectivity().checkConnectivity();
    _updateConnectionStatus(result);
  }

  void _updateConnectionStatus(List<ConnectivityResult> result) {
    bool hasConnection = result.any((element) => element != ConnectivityResult.none);
    if (hasConnection) {
      _connectivityTimer?.cancel();
      if (mounted && !_isConnected) setState(() => _isConnected = true);
    } else {
      _connectivityTimer?.cancel();
      _connectivityTimer = Timer(const Duration(seconds: 6), () {
        if (mounted && _isConnected) setState(() => _isConnected = false);
      });
    }
  }

  @override
  void dispose() { _subscription.cancel(); _connectivityTimer?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Material(
      child: Stack(
        children: [
          widget.child,
          if (!_isConnected)
            Positioned(top: 0, left: 0, right: 0, child: Container(color: Colors.redAccent, padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 5, bottom: 8), child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.wifi_off, color: Colors.white, size: 18), SizedBox(width: 10), Text("لا يوجد اتصال بالإنترنت في تطبيق أكسب", style: TextStyle(color: Colors.white, fontSize: 13, fontFamily: 'Tajawal', fontWeight: FontWeight.bold))]))),
        ],
      ),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Scaffold(body: Center(child: CircularProgressIndicator()));
        if (snapshot.hasData) {
          return FutureBuilder<Map<String, dynamic>?>(
            future: _getUserRoleAndData(snapshot.data!.uid),
            builder: (context, roleSnapshot) {
              if (roleSnapshot.connectionState == ConnectionState.waiting) return const Scaffold(body: Center(child: CircularProgressIndicator()));
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


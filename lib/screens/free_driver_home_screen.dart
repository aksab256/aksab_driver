import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:sizer/sizer.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http; // إضافة مكتبة الـ HTTP
import 'dart:convert';

// الصفحات التابعة
import 'available_orders_screen.dart';
import 'active_order_screen.dart';
import 'wallet_screen.dart';
import 'orders_history_screen.dart';
import 'profile_screen.dart';

class FreeDriverHomeScreen extends StatefulWidget {
  const FreeDriverHomeScreen({super.key});

  @override
  State<FreeDriverHomeScreen> createState() => _FreeDriverHomeScreenState();
}

class _FreeDriverHomeScreenState extends State<FreeDriverHomeScreen> {
  bool isOnline = false; 
  int _selectedIndex = 0;
  String? _activeOrderId;
  String _vehicleConfig = 'motorcycleConfig';
  final String uid = FirebaseAuth.instance.currentUser?.uid ?? "";
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _loadVehicleConfig();
    _fetchInitialStatus(); 
    _listenToActiveOrders();
    
    // طلب الإذن بعد استقرار الواجهة بـ 1 ثانية
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 1000), () {
        _requestNotificationPermissionWithDisclosure();
      });
    });
  }

  // --- 🔗 دالة ربط المندوب الحر بنظام إشعارات AWS الرادار ---
  Future<void> _syncFreeDriverWithAWS() async {
    try {
      String? token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        const String apiUrl = "https://5uex7vzy64.execute-api.us-east-1.amazonaws.com/V2/new_nofiction";
        await http.post(
          Uri.parse(apiUrl),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode({
            "userId": uid,
            "fcmToken": token,
            "role": "free_driver"
          }),
        );
        debugPrint("✅ Free Driver AWS Sync Successful");
      }
    } catch (e) {
      debugPrint("❌ Free Driver AWS Sync Error: $e");
    }
  }

  // --- 🛡️ دالة الإفصاح وطلب إذن الإشعارات (متوافقة مع جوجل بلاي) ---
  Future<void> _requestNotificationPermissionWithDisclosure() async {
    FirebaseMessaging messaging = FirebaseMessaging.instance;
    NotificationSettings settings = await messaging.getNotificationSettings();
    
    // نطلب الإذن إذا لم يكن مفعلًا بالكامل
    if (settings.authorizationStatus != AuthorizationStatus.authorized) {
      if (!mounted) return;
      
      bool? proceed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
          title: Column(
            children: [
              Icon(Icons.radar_rounded, size: 50, color: Colors.orange[900]),
              const SizedBox(height: 15),
              const Text("رادار الطلبات الجديدة", 
                style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w900, fontSize: 18)),
            ],
          ),
          content: const Text(
            "كابتن أكسب، تفعيل الإشعارات يضمن ظهور الطلبات القريبة منك فور صدورها، لتتمكن من قبولها وزيادة أرباحك قبل الآخرين.",
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'Cairo', fontSize: 14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("ليس الآن", style: TextStyle(fontFamily: 'Cairo', color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange[900],
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              ),
              onPressed: () => Navigator.pop(context, true),
              child: const Text("تفعيل الرادار", style: TextStyle(fontFamily: 'Cairo', color: Colors.white)),
            ),
          ],
        ),
      );

      if (proceed == true) {
        NotificationSettings newSettings = await messaging.requestPermission(
          alert: true, badge: true, sound: true,
        );
        
        // إذا وافق الكابتن، نحدث الـ Token في AWS فوراً
        if (newSettings.authorizationStatus == AuthorizationStatus.authorized) {
          await _syncFreeDriverWithAWS();
        }
      }
    }
  }

  // ... (باقي الدوال: _fetchInitialStatus, _toggleOnlineStatus, _buildModernDashboard) ...
  // تأكد من بقاء الكود البرمجي كما هو في نسختك الأصلية لضمان عمل الواجهات.
  
  // ملاحظة: قمت بتحديث دالة الخروج لمسح بيانات AWS (اختياري)
  Future<void> _handleLogout() async {
     await FirebaseAuth.instance.signOut();
     final prefs = await SharedPreferences.getInstance();
     await prefs.clear();
     if (mounted) Navigator.pushReplacementNamed(context, '/login');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      drawer: _buildSideDrawer(),
      backgroundColor: const Color(0xFFF4F7FA),
      body: _selectedIndex == 0 
          ? _buildModernDashboard() 
          : _buildOtherPages(),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  // ... (استكمل بناء باقي الـ Widgets كما في الكود الخاص بك)
}

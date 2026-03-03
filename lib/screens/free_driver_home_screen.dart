// lib/screens/free_driver_home_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:sizer/sizer.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:permission_handler/permission_handler.dart'; 
import 'package:geolocator/geolocator.dart';

// الصفحات التابعة
import 'available_orders_screen.dart';
import 'active_order_screen.dart';
import 'wallet_screen.dart';
import 'orders_history_screen.dart';
import 'profile_screen.dart';
import 'support_screen.dart'; 
import 'freelance_terms_screen.dart'; 

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
  bool _hasNewOrders = false; 
  final String uid = FirebaseAuth.instance.currentUser?.uid ?? "";
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  DateTime? _lastBackPressTime;

  @override
  void initState() {
    super.initState();
    _loadVehicleConfig();
    _listenToDriverStatus(); // الاستماع للحالة بشكل حي (Online/Busy/Offline)
    _listenToActiveOrders();
    _listenToRadarNotifications();
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkSecurityAndTerms();
    });
  }

  // --- 📡 الاستماع لحالة المندوب من السيرفر ---
  // هذا يضمن أنه إذا انتهت الرحلة في ActiveOrderScreen، سيتحدث الزر هنا تلقائياً
  void _listenToDriverStatus() {
    FirebaseFirestore.instance.collection('freeDrivers').doc(uid).snapshots().listen((snap) {
      if (snap.exists && mounted) {
        String status = snap.data()?['currentStatus'] ?? 'offline';
        setState(() {
          // نعتبره "متصل" إذا كانت حالته online أو مشغول في رحلة busy
          isOnline = (status == 'online' || status == 'busy');
        });
      }
    });
  }

  void _listenToRadarNotifications() {
    FirebaseFirestore.instance
        .collection('notifications')
        .where('userId', isEqualTo: uid)
        .where('eventType', isEqualTo: 'radar_new_order')
        .where('isRead', isEqualTo: false)
        .snapshots()
        .listen((snap) {
      if (mounted) {
        setState(() => _hasNewOrders = snap.docs.isNotEmpty);
      }
    });
  }

  Future<bool> _handleWillPop() async {
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      Navigator.pop(context);
      return false;
    }
    if (_selectedIndex != 0) {
      setState(() => _selectedIndex = 0);
      return false;
    }
    DateTime now = DateTime.now();
    if (_lastBackPressTime == null || now.difference(_lastBackPressTime!) > const Duration(seconds: 2)) {
      _lastBackPressTime = now;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("إضغط مرة أخرى للخروج من التطبيق", style: TextStyle(fontFamily: 'Cairo')),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return false;
    }
    return true;
  }

  // --- 📍 منطق الأونلاين المطور ---
  void _toggleOnlineStatus(bool value) async {
    // إذا كان المندوب حالياً في رحلة (Busy)، لا نسمح له بالإغلاق حتى تنتهي الرحلة
    if (!value && _activeOrderId != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("لا يمكن التحول لوضع أوفلاين أثناء وجود رحلة نشطة", textAlign: TextAlign.center, style: TextStyle(fontFamily: 'Cairo')))
      );
      return;
    }

    if (value) {
      var status = await Permission.location.status;
      if (status.isGranted) {
        _updateOnlineInDB(true);
      } else {
        _showLocationDisclosure();
      }
    } else {
      _updateOnlineInDB(false);
    }
  }

  void _showLocationDisclosure() async {
    bool? proceed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
        title: Row(
          children: [
            Icon(Icons.location_on, color: Colors.orange[900]),
            const SizedBox(width: 10),
            const Text("تحسين الرادار", style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Text(
          "يقوم تطبيق 'أكسب كابتن' بجمع بيانات الموقع لتمكين 'رادار الطلبات' وتتبع الرحلات النشطة لضمان النقل الآمن للعهدة.\n\n"
          "سيتم استخدام الموقع لعرض الطلبات المتاحة في نطاقك وتحديث حالة العهدة.",
          textAlign: TextAlign.right,
          style: TextStyle(fontFamily: 'Cairo'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("ليس الآن")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange[900], shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
            onPressed: () => Navigator.pop(context, true),
            child: const Text("موافق ومتابعة", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (proceed == true) {
      if (await Permission.location.request().isGranted) {
        await Permission.locationAlways.request(); 
        _updateOnlineInDB(true);
      }
    }
  }

  void _updateOnlineInDB(bool value) async {
    Map<String, dynamic> updateData = {
      'isOnline': value,
      'currentStatus': value ? 'online' : 'offline', // التحديث الجوهري
      'lastSeen': FieldValue.serverTimestamp(),
    };

    if (value) {
      try {
        Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
        updateData['lat'] = position.latitude;
        updateData['lng'] = position.longitude;
      } catch (e) {
        debugPrint("⚠️ Location Error: $e");
      }
    }

    await FirebaseFirestore.instance.collection('freeDrivers').doc(uid).update(updateData);
  }

  // --- 🛡️ فحص الأمان وشروط الخدمة ---
  Future<void> _checkSecurityAndTerms() async {
    if (uid.isEmpty) return;
    await Future.delayed(const Duration(milliseconds: 1000));
    var userDoc = await FirebaseFirestore.instance.collection('freeDrivers').doc(uid).get();
    bool hasAccepted = userDoc.exists ? (userDoc.data()?['hasAcceptedTerms'] ?? false) : false;

    if (!hasAccepted && mounted) {
      final result = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        isDismissible: false,
        backgroundColor: Colors.transparent,
        builder: (context) => FreelanceTermsScreen(userId: uid),
      );
      if (result == true) _requestNotificationPermission();
    } else {
      _requestNotificationPermission();
    }
  }

  Future<void> _requestNotificationPermission() async {
    FirebaseMessaging messaging = FirebaseMessaging.instance;
    NotificationSettings settings = await messaging.requestPermission(alert: true, badge: true, sound: true);
    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      String? token = await messaging.getToken();
      if (token != null) {
        await http.post(
          Uri.parse("https://5uex7vzy64.execute-api.us-east-1.amazonaws.com/V2/new_nofiction"),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode({"userId": uid, "fcmToken": token, "role": "free_driver"}),
        );
      }
    }
  }

  void _loadVehicleConfig() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _vehicleConfig = prefs.getString('user_vehicle_config') ?? 'motorcycleConfig');
  }

  void _listenToActiveOrders() {
    FirebaseFirestore.instance
        .collection('specialRequests')
        .where('driverId', isEqualTo: uid)
        .where('status', whereIn: ['accepted', 'picked_up', 'returning_to_seller', 'returning_to_merchant'])
        .snapshots()
        .listen((snap) {
      if (mounted) setState(() => _activeOrderId = snap.docs.isNotEmpty ? snap.docs.first.id : null);
    });
  }

  void _onItemTapped(int index) {
    if (index == 1 && !isOnline) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("برجاء تفعيل وضع الاتصال لفتح الرادار", style: TextStyle(fontFamily: 'Cairo'))));
      return;
    }
    setState(() {
      _selectedIndex = index;
      if (index == 1) _hasNewOrders = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, 
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (await _handleWillPop() && mounted) SystemNavigator.pop();
      },
      child: Scaffold(
        key: _scaffoldKey,
        drawer: _buildSideDrawer(), 
        backgroundColor: const Color(0xFFF4F7FA),
        body: _selectedIndex == 0 ? _buildModernDashboard() : _buildOtherPages(),
        bottomNavigationBar: _buildBottomNav(),
      ),
    );
  }

  Widget _buildModernDashboard() {
    return SafeArea(
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 20, 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(children: [
                    IconButton(icon: const Icon(Icons.menu_rounded, size: 32), onPressed: () => _scaffoldKey.currentState?.openDrawer()),
                    const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text("أهلاً بك 👋", style: TextStyle(fontSize: 14, color: Colors.blueGrey, fontFamily: 'Cairo')),
                      Text("كابتن أكسب", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, fontFamily: 'Cairo'))
                    ])
                  ]),
                  _buildStatusToggle(),
                ],
              ),
            ),
          ),
          if (_activeOrderId != null) SliverToBoxAdapter(child: _buildActiveOrderBanner()),
          _buildLiveStatsGrid(),
        ],
      ),
    );
  }

  Widget _buildStatusToggle() {
    return GestureDetector(
      onTap: () => _toggleOnlineStatus(!isOnline),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300), 
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10), 
        decoration: BoxDecoration(color: isOnline ? Colors.green[600] : Colors.red[600], borderRadius: BorderRadius.circular(15)), 
        child: Row(children: [
          Icon(isOnline ? Icons.flash_on : Icons.flash_off, color: Colors.white, size: 18), 
          const SizedBox(width: 8), 
          Text(isOnline ? "متصل" : "أوفلاين", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontFamily: 'Cairo'))
        ])),
    );
  }

  // --- بقية الواجهات (Drawer, Stats, BottomNav) ---
  Widget _buildSideDrawer() { /* كود الدروير الخاص بك */ return Drawer(); }
  Widget _buildLiveStatsGrid() { /* كود إحصائيات الأرباح */ return SliverToBoxAdapter(); }
  Widget _buildActiveOrderBanner() { /* بانر الرحلة النشطة */ return Container(); }
  Widget _buildOtherPages() {
    return [
      const SizedBox(), 
      _activeOrderId != null 
          ? ActiveOrderScreen(orderId: _activeOrderId!) 
          : AvailableOrdersScreen(vehicleType: _vehicleConfig), 
      const OrdersHistoryScreen(), 
      const WalletScreen()
    ][_selectedIndex];
  }
  Widget _buildBottomNav() { /* الناف بار مع نقطة الرادار الحمراء */ return BottomNavigationBar(items: []); }
}

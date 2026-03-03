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
  String _currentStatus = 'offline'; 
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
    _listenToDriverStatus();
    _listenToActiveOrders();
    _listenToRadarNotifications();
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkSecurityAndTerms();
    });
  }

  // --- 📡 الاستماع للحالات (معدل لضمان إغلاق التتبع) ---
  void _listenToDriverStatus() {
    if (uid.isEmpty) return;
    FirebaseFirestore.instance.collection('freeDrivers').doc(uid).snapshots().listen((snap) {
      if (snap.exists && mounted) {
        setState(() {
          _currentStatus = snap.data()?['currentStatus'] ?? 'offline';
        });
      }
    });
  }

  void _listenToActiveOrders() {
    if (uid.isEmpty) return;
    // الاستماع للطلبات النشطة (المقبولة أو المستلمة فقط)
    FirebaseFirestore.instance
        .collection('specialRequests')
        .where('driverId', isEqualTo: uid)
        .where('status', whereIn: ['accepted', 'picked_up', 'returning_to_seller', 'returning_to_merchant'])
        .snapshots()
        .listen((snap) {
      if (mounted) {
        if (snap.docs.isEmpty) {
          // هامة جداً: لو مفيش طلبات نشطة والمندوب كان busy، رجعه online فوراً
          if (_currentStatus == 'busy') {
            _resetDriverToOnline();
          }
          setState(() => _activeOrderId = null);
        } else {
          setState(() => _activeOrderId = snap.docs.first.id);
        }
      }
    });
  }

  // دالة لإعادة المندوب للوضع الطبيعي وتصفير العهدة برمجياً
  void _resetDriverToOnline() async {
    await FirebaseFirestore.instance.collection('freeDrivers').doc(uid).update({
      'currentStatus': 'online',
      'insurance_points': 0, // تصفير نقاط التأمين عند انتهاء العهدة
    });
    debugPrint("✅ تم إنهاء العهدة وإعادة المندوب لوضع الاتصال");
  }

  // --- 📍 منطق التنقل والواجهة (كما هو متفق عليه) ---
  void _onItemTapped(int index) {
    if (index == 1) {
      if (_currentStatus == 'offline' && _activeOrderId == null) {
        _showErrorSnackBar("برجاء تفعيل وضع الاتصال لفتح الرادار");
        return;
      }
      _hasNewOrders = false;
    }
    setState(() => _selectedIndex = index);
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
        drawer: const ProfileScreen(), 
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
              padding: const EdgeInsets.all(20.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(children: [
                    IconButton(icon: const Icon(Icons.menu_rounded, size: 30), onPressed: () => _scaffoldKey.currentState?.openDrawer()),
                    const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text("أهلاً بك 👋", style: TextStyle(fontSize: 12, color: Colors.grey, fontFamily: 'Cairo')),
                      Text("كابتن أكسب", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, fontFamily: 'Cairo'))
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

  Widget _buildLiveStatsGrid() {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('freeDrivers').doc(uid).snapshots(),
      builder: (context, snapshot) {
        String insurancePoints = "0";
        String dailyCompleted = "0";
        String rating = "5.0";
        String walletBalance = "0.00";
        if (snapshot.hasData && snapshot.data!.exists) {
          var data = snapshot.data!.data() as Map<String, dynamic>;
          insurancePoints = (data['insurance_points'] ?? 0).toString();
          walletBalance = (data['wallet_balance'] ?? 0.0).toStringAsFixed(2);
          rating = (data['rating'] ?? 5.0).toStringAsFixed(1);
          dailyCompleted = (data['completed_today'] ?? 0).toString();
        }
        return SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2, crossAxisSpacing: 15, mainAxisSpacing: 15, childAspectRatio: 1.1,
            ),
            delegate: SliverChildListDelegate([
              _buildStatCard("نقاط التأمين", insurancePoints, Icons.security, Colors.blue),
              _buildStatCard("أمانات مُسلمة اليوم", dailyCompleted, Icons.task_alt, Colors.orange),
              _buildStatCard("التقييم المهني", rating, Icons.star_border_rounded, Colors.amber),
              _buildStatCard("المحفظة (ج.م)", walletBalance, Icons.account_balance_wallet_outlined, Colors.green),
            ]),
          ),
        );
      },
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(10)), child: Icon(icon, color: color, size: 24)),
        const Spacer(),
        Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        Text(title, style: const TextStyle(color: Colors.grey, fontFamily: 'Cairo', fontSize: 11)),
      ]),
    );
  }

  Widget _buildOtherPages() {
    switch (_selectedIndex) {
      case 1:
        if (_activeOrderId != null) return ActiveOrderScreen(orderId: _activeOrderId!);
        return AvailableOrdersScreen(vehicleType: _vehicleConfig);
      case 2: return const OrdersHistoryScreen();
      case 3: return const WalletScreen();
      default: return _buildModernDashboard();
    }
  }

  Widget _buildBottomNav() {
    return BottomNavigationBar(
      currentIndex: _selectedIndex,
      onTap: _onItemTapped,
      type: BottomNavigationBarType.fixed,
      selectedItemColor: Colors.orange[900],
      items: [
        const BottomNavigationBarItem(icon: Icon(Icons.home_filled), label: "الرئيسية"),
        BottomNavigationBarItem(
          icon: Icon(_activeOrderId != null ? Icons.location_searching : Icons.radar),
          label: _activeOrderId != null ? "التتبع" : "الرادار",
        ),
        const BottomNavigationBarItem(icon: Icon(Icons.history), label: "رحلاتي"),
        const BottomNavigationBarItem(icon: Icon(Icons.wallet), label: "المحفظة"),
      ],
    );
  }

  // --- 📍 منطق الأذونات (معدل للعمل مع دياالوج النظام) ---
  void _toggleOnlineStatus(bool shouldBeOnline) async {
    if (!shouldBeOnline && _currentStatus == 'busy') {
      _showErrorSnackBar("يجب إنهاء العهدة الحالية أولاً لتغيير الحالة");
      return;
    }
    if (shouldBeOnline) {
      PermissionStatus status = await Permission.location.status;
      if (status.isGranted) {
        _updateOnlineInDB(true);
      } else if (status.isPermanentlyDenied) {
        openAppSettings();
      } else {
        _showLocationDisclosure();
      }
    } else {
      _updateOnlineInDB(false);
    }
  }

  void _showLocationDisclosure() async {
    bool? proceed = await showDialog<bool>(
      context: context, barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("تأمين العهدة نشط 🛡️", style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
        content: const Text("يتطلب 'أكسب كابتن' الوصول الدائم للموقع لضمان استرداد نقاط التأمين وتتبع الرحلة بأمان."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("ليس الآن")),
          ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.orange[900]), onPressed: () => Navigator.pop(context, true), child: const Text("موافق", style: TextStyle(color: Colors.white))),
        ],
      ),
    );
    if (proceed == true) {
      if (await Permission.location.request().isGranted) {
        _updateOnlineInDB(true);
        await Permission.locationAlways.request();
      }
    }
  }

  void _updateOnlineInDB(bool value) async {
    Map<String, dynamic> updateData = {'currentStatus': value ? 'online' : 'offline', 'lastSeen': FieldValue.serverTimestamp()};
    if (value) {
      try {
        Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
        updateData['lat'] = position.latitude; updateData['lng'] = position.longitude;
      } catch (e) { debugPrint(e.toString()); }
    }
    await FirebaseFirestore.instance.collection('freeDrivers').doc(uid).update(updateData);
  }

  // --- دوال مساعدة ---
  void _showErrorSnackBar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg, textAlign: TextAlign.center, style: const TextStyle(fontFamily: 'Cairo')), behavior: SnackBarBehavior.floating, backgroundColor: Colors.redAccent));
  }

  void _listenToRadarNotifications() {
    FirebaseFirestore.instance.collection('notifications').where('userId', isEqualTo: uid).where('eventType', isEqualTo: 'radar_new_order').where('isRead', isEqualTo: false).snapshots().listen((snap) {
      if (mounted) setState(() => _hasNewOrders = snap.docs.isNotEmpty);
    });
  }

  void _loadVehicleConfig() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _vehicleConfig = prefs.getString('user_vehicle_config') ?? 'motorcycleConfig');
  }

  Future<void> _checkSecurityAndTerms() async {
    if (uid.isEmpty) return;
    var userDoc = await FirebaseFirestore.instance.collection('freeDrivers').doc(uid).get();
    if (userDoc.exists && !(userDoc.data()?['hasAcceptedTerms'] ?? false) && mounted) {
      final result = await showModalBottomSheet<bool>(context: context, isScrollControlled: true, isDismissible: false, backgroundColor: Colors.transparent, builder: (context) => FreelanceTermsScreen(userId: uid));
      if (result == true) _requestNotificationPermission();
    } else { _requestNotificationPermission(); }
  }

  Future<void> _requestNotificationPermission() async {
    FirebaseMessaging messaging = FirebaseMessaging.instance;
    NotificationSettings settings = await messaging.requestPermission(alert: true, badge: true, sound: true);
    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      String? token = await messaging.getToken();
      if (token != null) {
        await http.post(Uri.parse("https://5uex7vzy64.execute-api.us-east-1.amazonaws.com/V2/new_nofiction"), headers: {"Content-Type": "application/json"}, body: jsonEncode({"userId": uid, "fcmToken": token, "role": "free_driver"}));
      }
    }
  }

  Future<bool> _handleWillPop() async {
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) { Navigator.pop(context); return false; }
    if (_selectedIndex != 0) { setState(() => _selectedIndex = 0); return false; }
    DateTime now = DateTime.now();
    if (_lastBackPressTime == null || now.difference(_lastBackPressTime!) > const Duration(seconds: 2)) {
      _lastBackPressTime = now;
      _showErrorSnackBar("إضغط مرة أخرى للخروج");
      return false;
    }
    return true;
  }

  Widget _buildActiveOrderBanner() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(color: Colors.orange[50], borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.orange.shade200)),
      child: Row(children: [
        const Icon(Icons.delivery_dining, color: Colors.orange),
        const SizedBox(width: 10),
        const Expanded(child: Text("لديك عهدة نشطة، اضغط لإدارة الرحلة", style: TextStyle(fontFamily: 'Cairo', fontSize: 13, fontWeight: FontWeight.bold))),
        ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.orange[900]), onPressed: () => setState(() => _selectedIndex = 1), child: const Text("متابعة", style: TextStyle(color: Colors.white, fontSize: 12)))
      ]),
    );
  }
}

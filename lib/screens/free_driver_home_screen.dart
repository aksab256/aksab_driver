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
import 'dart:io'; 
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
  bool _showOnlinePrompt = false; // لمطالبة المندوب بتفعيل الوضع أونلاين
  final String uid = FirebaseAuth.instance.currentUser?.uid ?? "";
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  DateTime? _lastBackPressTime;

  @override
  void initState() {
    super.initState();
    _loadVehicleConfig();
    _listenToDriverStatus();
    _listenToActiveOrders();
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkSecurityAndTerms();
    });
  }

  // --- 🔄 الاستماع لحالة المندوب والطلبات ---
  void _listenToDriverStatus() {
    if (uid.isEmpty) return;
    FirebaseFirestore.instance.collection('freeDrivers').doc(uid).snapshots().listen((snap) {
      if (snap.exists && mounted) {
        setState(() => _currentStatus = snap.data()?['currentStatus'] ?? 'offline');
      }
    });
  }

  void _listenToActiveOrders() {
    if (uid.isEmpty) return;
    FirebaseFirestore.instance
        .collection('specialRequests')
        .where('driverId', isEqualTo: uid)
        .where('status', whereIn: ['accepted', 'picked_up', 'returning_to_seller', 'returning_to_merchant'])
        .snapshots()
        .listen((snap) {
      if (mounted) {
        if (snap.docs.isEmpty) {
          if (_currentStatus == 'busy') _resetDriverToOnline();
          setState(() => _activeOrderId = null);
        } else {
          setState(() => _activeOrderId = snap.docs.first.id);
        }
      }
    });
  }

  void _resetDriverToOnline() async {
    try {
      await FirebaseFirestore.instance.collection('freeDrivers').doc(uid).update({
        'currentStatus': 'online',
        'insurance_points': 0,
      });
    } catch (e) {
      debugPrint("Reset Status Error: $e");
    }
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

  // --- 📋 بناء الشريط الجانبي ---
  Widget _buildSideDrawer() {
    return Drawer(
      width: 75.w,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.only(topLeft: Radius.circular(35), bottomLeft: Radius.circular(35))),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [Colors.orange[900]!, Colors.orange[700]!]),
              borderRadius: const BorderRadius.only(bottomRight: Radius.circular(30)),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const CircleAvatar(radius: 35, backgroundColor: Colors.white, child: Icon(Icons.person, size: 45, color: Colors.orange)),
                    const SizedBox(height: 15),
                    const Text("كابتن أكسب", style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w900, fontSize: 18, color: Colors.white)),
                    Text(FirebaseAuth.instance.currentUser?.email ?? "driver@aksab.shop", 
                      style: const TextStyle(fontFamily: 'Cairo', color: Colors.white70, fontSize: 12)),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
              children: [
                _buildDrawerItem(Icons.account_circle_outlined, "حسابي الشخصي", 
                  () => Navigator.push(context, MaterialPageRoute(builder: (context) => const ProfileScreen()))),
                _buildDrawerItem(Icons.privacy_tip_outlined, "سياسة الخصوصية", _launchPrivacyPolicy),
                _buildDrawerItem(Icons.help_outline_rounded, "الدعم الفني", 
                  () => Navigator.push(context, MaterialPageRoute(builder: (context) => const SupportScreen()))),
              ],
            ),
          ),
          const Divider(indent: 20, endIndent: 20),
          ListTile(
            leading: const Icon(Icons.logout_rounded, color: Colors.redAccent),
            title: const Text("تسجيل الخروج", style: TextStyle(fontFamily: 'Cairo', color: Colors.redAccent, fontWeight: FontWeight.bold)),
            onTap: () async {
              if (_currentStatus == 'busy') {
                _showErrorSnackBar("لا يمكن تسجيل الخروج أثناء وجود عهدة نشطة");
                return;
              }
              await FirebaseAuth.instance.signOut();
              if (mounted) Navigator.pushReplacementNamed(context, '/login');
            },
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildDrawerItem(IconData icon, String title, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: Colors.blueGrey[700]),
      title: Text(title, style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w600, fontSize: 14)),
      trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
      onTap: onTap,
    );
  }

  // --- 🏠 لوحة التحكم ---
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
                    IconButton(icon: const Icon(Icons.menu_rounded, size: 32), onPressed: () => _scaffoldKey.currentState?.openDrawer()),
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
          
          // --- 📢 أنيميشن التوجيه للوضع أونلاين ---
          if (_showOnlinePrompt && _currentStatus == 'offline')
            SliverToBoxAdapter(
              child: TweenAnimationBuilder(
                duration: const Duration(milliseconds: 1000),
                tween: Tween<double>(begin: 0, end: 1),
                builder: (context, double value, child) {
                  return Opacity(
                    opacity: value,
                    child: Transform.translate(offset: Offset(0, (1 - value) * 15), child: child),
                  );
                },
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.orange[50], borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.orange[200]!)),
                  child: Row(children: [
                    const Icon(Icons.lightbulb_outline, color: Colors.orange),
                    const SizedBox(width: 10),
                    const Expanded(child: Text("فعل وضع 'متصل' الآن لتظهر في الرادار وتصلك الطلبات القريبة!", style: TextStyle(fontFamily: 'Cairo', fontSize: 12, color: Colors.orange[900]))),
                    IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => setState(() => _showOnlinePrompt = false)),
                  ]),
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
    bool isActive = (_currentStatus == 'online' || _currentStatus == 'busy');
    return GestureDetector(
      onTap: () => _toggleOnlineStatus(!isActive),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? Colors.green[600] : Colors.red[600],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(children: [
          Icon(isActive ? Icons.flash_on : Icons.flash_off, color: Colors.white, size: 16),
          const SizedBox(width: 6),
          Text(isActive ? "متصل" : "أوفلاين",
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
          )
        ]),
      ),
    );
  }

  Widget _buildLiveStatsGrid() {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('freeDrivers').doc(uid).snapshots(),
      builder: (context, snapshot) {
        var data = snapshot.hasData && snapshot.data!.exists ? snapshot.data!.data() as Map<String, dynamic> : {};
        return SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 15, mainAxisSpacing: 15, childAspectRatio: 1.1),
            delegate: SliverChildListDelegate([
              _buildStatCard("نقاط التأمين", "${data['insurance_points'] ?? 0}", Icons.security, Colors.blue),
              _buildStatCard("أمانات مُسلمة اليوم", "${data['completed_today'] ?? 0}", Icons.task_alt, Colors.orange),
              _buildStatCard("التقييم المهني", "${data['rating'] ?? 5.0}", Icons.star_border_rounded, Colors.amber),
              _buildStatCard("المحفظة (ج.م)", "${(data['wallet_balance'] ?? 0.0).toStringAsFixed(2)}", Icons.account_balance_wallet_outlined, Colors.green),
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
        Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        Text(title, style: const TextStyle(color: Colors.grey, fontFamily: 'Cairo', fontSize: 10)),
      ]),
    );
  }

  // --- 🛡️ التحكم في الحالة والأمان ---
  void _toggleOnlineStatus(bool shouldBeOnline) async {
    if (!shouldBeOnline && _currentStatus == 'busy') {
      _showErrorSnackBar("يجب إنهاء العهدة الحالية أولاً");
      return;
    }
    if (shouldBeOnline) {
      PermissionStatus status = await Permission.location.status;
      if (status.isGranted) {
        _updateOnlineInDB(true);
        setState(() => _showOnlinePrompt = false);
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
        title: const Text("تتبع العهدة واللوجيستيات 🛡️", style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
        content: const Text(
            "يتطلب 'أكسب كابتن' الوصول للموقع في الخلفية لضمان استرداد نقاط التأمين وتحديث حالة الطلب للعملاء فور وجود 'طلب نشط' فقط.\n\n"
            "• يتم التوقف عن إرسال الموقع فور الانتقال لوضع 'أوفلاين'."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("ليس الآن")),
          ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.orange[900]), onPressed: () => Navigator.pop(context, true), child: const Text("موافق", style: TextStyle(color: Colors.white))),
        ],
      ),
    );
    if (proceed == true) {
      if (await Permission.location.request().isGranted) {
        _updateOnlineInDB(true);
        setState(() => _showOnlinePrompt = false);
        await Permission.locationAlways.request();
      }
    }
  }

  void _updateOnlineInDB(bool value) async {
    try {
      Map<String, dynamic> updateData = {'currentStatus': value ? 'online' : 'offline', 'lastSeen': FieldValue.serverTimestamp()};
      if (value) {
        Position pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
        updateData['lat'] = pos.latitude; updateData['lng'] = pos.longitude;
      }
      await FirebaseFirestore.instance.collection('freeDrivers').doc(uid).update(updateData);
    } catch (e) { debugPrint("DB Update Error: $e"); }
  }

  Future<void> _launchPrivacyPolicy() async {
    final Uri url = Uri.parse('https://aksab.shop/');
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) _showErrorSnackBar("تعذر فتح الرابط");
  }

  void _showErrorSnackBar(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg, textAlign: TextAlign.center, style: const TextStyle(fontFamily: 'Cairo')), behavior: SnackBarBehavior.floating));
  }

  Widget _buildActiveOrderBanner() {
    return GestureDetector(
      onTap: () => setState(() => _selectedIndex = 1),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(color: Colors.orange[900], borderRadius: BorderRadius.circular(15)),
        child: const Row(children: [
          Icon(Icons.delivery_dining, color: Colors.white),
          SizedBox(width: 10),
          Expanded(child: Text("لديك عهدة نشطة، اضغط للمتابعة", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontFamily: 'Cairo'))),
          Icon(Icons.arrow_forward_ios, color: Colors.white, size: 14)
        ]),
      ),
    );
  }

  Widget _buildBottomNav() {
    return BottomNavigationBar(
      currentIndex: _selectedIndex,
      onTap: (i) => setState(() => _selectedIndex = i),
      type: BottomNavigationBarType.fixed,
      selectedItemColor: Colors.orange[900],
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.home_filled), label: "الرئيسية"),
        BottomNavigationBarItem(icon: Icon(Icons.radar), label: "الرادار"),
        BottomNavigationBarItem(icon: Icon(Icons.history), label: "رحلاتي"),
        BottomNavigationBarItem(icon: Icon(Icons.wallet), label: "المحفظة"),
      ],
    );
  }

  Widget _buildOtherPages() {
    switch (_selectedIndex) {
      case 1: return _activeOrderId != null ? ActiveOrderScreen(orderId: _activeOrderId!) : AvailableOrdersScreen(vehicleType: _vehicleConfig);
      case 2: return const OrdersHistoryScreen();
      case 3: return const WalletScreen();
      default: return _buildModernDashboard();
    }
  }

  void _loadVehicleConfig() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _vehicleConfig = prefs.getString('user_vehicle_config') ?? 'motorcycleConfig');
  }

  Future<void> _checkSecurityAndTerms() async {
    if (uid.isEmpty) return;
    try {
      var userDoc = await FirebaseFirestore.instance.collection('freeDrivers').doc(uid).get();
      if (userDoc.exists && !(userDoc.data()?['hasAcceptedTerms'] ?? false) && mounted) {
        final result = await showModalBottomSheet<bool>(context: context, isScrollControlled: true, isDismissible: false, builder: (context) => FreelanceTermsScreen(userId: uid));
        if (result == true) {
          _showErrorSnackBar("تم حفظ موافقتك القانونية بنجاح ✅");
          _requestNotificationWithDisclosure();
        }
      } else { 
        _requestNotificationWithDisclosure(); 
      }
    } catch (e) { debugPrint("Security Check Error: $e"); }
  }

  // --- 🔔 طلب الإشعارات مع رسالة إفصاح مسبقة ---
  Future<void> _requestNotificationWithDisclosure() async {
    // إظهار تنبيه يوضح فائدة الإشعارات (متطلب لجوجل في بعض الحالات)
    bool? proceed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("تنبيهات الطلبات 🔔", style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
        content: const Text("يرجى تفعيل الإشعارات لتصلك تنبيهات الطلبات الجديدة وتحديثات العهدة لحظياً."),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange[900]),
            onPressed: () => Navigator.pop(context, true),
            child: const Text("موافق", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (proceed == true) {
      try {
        FirebaseMessaging messaging = FirebaseMessaging.instance;
        NotificationSettings settings = await messaging.requestPermission(alert: true, badge: true, sound: true);
        if (settings.authorizationStatus == AuthorizationStatus.authorized) {
          String? token = await messaging.getToken();
          if (token != null) {
            await http.post(
              Uri.parse("https://5uex7vzy64.execute-api.us-east-1.amazonaws.com/V2/new_nofiction"),
              headers: {"Content-Type": "application/json"},
              body: jsonEncode({"userId": uid, "fcmToken": token, "role": "free_driver"}),
            ).timeout(const Duration(seconds: 10));
          }
        }
        // بعد الانتهاء من الإشعارات، فعل أنيميشن التوجيه
        if (_currentStatus == 'offline') setState(() => _showOnlinePrompt = true);
      } catch (e) { debugPrint("Notification error: $e"); }
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
}

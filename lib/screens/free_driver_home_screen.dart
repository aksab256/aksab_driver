import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:sizer/sizer.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

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
  final String uid = FirebaseAuth.instance.currentUser?.uid ?? "";
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  
  // متغير لتسجيل وقت آخر ضغطة لزر الرجوع (لمنع الخروج المفاجئ)
  DateTime? _lastBackPressTime;

  @override
  void initState() {
    super.initState();
    _loadVehicleConfig();
    _fetchInitialStatus(); 
    _listenToActiveOrders();
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkSecurityAndTerms();
    });
  }

  // --- 🛡️ منطق التعامل مع زر الرجوع الذكي ---
  Future<bool> _handleWillPop() async {
    // 1. لو الـ Drawer مفتوح، اقفله الأول
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      Navigator.pop(context);
      return false;
    }

    // 2. لو المستخدم في أي صفحة غير "الرئيسية" (Tabs 1, 2, 3)
    if (_selectedIndex != 0) {
      setState(() => _selectedIndex = 0); // رجعه للتبويب الأول
      return false; // لا تخرج من التطبيق
    }

    // 3. لو هو في الصفحة الرئيسية (تبويب 0)
    DateTime now = DateTime.now();
    if (_lastBackPressTime == null || now.difference(_lastBackPressTime!) > const Duration(seconds: 2)) {
      _lastBackPressTime = now;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("إضغط مرة أخرى للخروج من التطبيق", 
            style: TextStyle(fontFamily: 'Cairo'), textAlign: TextAlign.center),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return false; // لا تخرج بعد
    }
    return true; // اخرج في الضغطة الثانية
  }

  // --- 🛡️ بوابة الأمان وفحص الشروط ---
  Future<void> _checkSecurityAndTerms() async {
    if (uid.isEmpty) return;
    await Future.delayed(const Duration(milliseconds: 1000));
    try {
      var userDoc = await FirebaseFirestore.instance.collection('freeDrivers').doc(uid).get();
      bool hasAccepted = userDoc.exists ? (userDoc.data()?['hasAcceptedTerms'] ?? false) : false;

      if (!hasAccepted && mounted) {
        final result = await showModalBottomSheet<bool>(
          context: context,
          isScrollControlled: true,
          isDismissible: false,
          enableDrag: false,
          backgroundColor: Colors.transparent,
          builder: (context) => FreelanceTermsScreen(userId: uid),
        );
        if (result == true) _requestNotificationPermissionWithDisclosure();
      } else {
        _requestNotificationPermissionWithDisclosure();
      }
    } catch (e) { debugPrint("⚠️ Security Check Error: $e"); }
  }

  // --- 🔗 الربط مع AWS ---
  Future<void> _syncFreeDriverWithAWS() async {
    try {
      String? token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        const String apiUrl = "https://5uex7vzy64.execute-api.us-east-1.amazonaws.com/V2/new_nofiction";
        await http.post(Uri.parse(apiUrl), headers: {"Content-Type": "application/json"},
          body: jsonEncode({"userId": uid, "fcmToken": token, "role": "free_driver"}),
        );
      }
    } catch (e) { debugPrint("❌ AWS Sync Error: $e"); }
  }

  // --- 🔔 الإشعارات ---
  Future<void> _requestNotificationPermissionWithDisclosure() async {
    FirebaseMessaging messaging = FirebaseMessaging.instance;
    NotificationSettings settings = await messaging.getNotificationSettings();
    if (settings.authorizationStatus != AuthorizationStatus.authorized && mounted) {
      bool? proceed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
          title: const Text("رادار الطلبات الجديدة", textAlign: TextAlign.center, style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
          content: const Text("تفعيل الإشعارات يضمن ظهور الطلبات القريبة منك فور صدورها.", textAlign: TextAlign.center, style: TextStyle(fontFamily: 'Cairo')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("ليس الآن")),
            ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text("تفعيل")),
          ],
        ),
      );
      if (proceed == true) {
        NotificationSettings newSettings = await messaging.requestPermission(alert: true, badge: true, sound: true);
        if (newSettings.authorizationStatus == AuthorizationStatus.authorized) await _syncFreeDriverWithAWS();
      }
    }
  }

  // --- ⚙️ الإعدادات والحالة ---
  void _loadVehicleConfig() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _vehicleConfig = prefs.getString('user_vehicle_config') ?? 'motorcycleConfig');
  }

  void _fetchInitialStatus() async {
    var doc = await FirebaseFirestore.instance.collection('freeDrivers').doc(uid).get();
    if (doc.exists && mounted) setState(() => isOnline = doc.data()?['isOnline'] ?? false);
  }

  void _listenToActiveOrders() {
    FirebaseFirestore.instance.collection('specialRequests').where('driverId', isEqualTo: uid).where('status', whereIn: ['accepted', 'picked_up']).snapshots().listen((snap) {
      if (mounted) setState(() => _activeOrderId = snap.docs.isNotEmpty ? snap.docs.first.id : null);
    });
  }

  void _toggleOnlineStatus(bool value) async {
    setState(() => isOnline = value);
    await FirebaseFirestore.instance.collection('freeDrivers').doc(uid).update({'isOnline': value, 'lastSeen': FieldValue.serverTimestamp()});
  }

  // --- 🏗️ بناء الواجهة ---
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // التحكم اليدوي لمنع الخروج أو العودة للرئيسية
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldExit = await _handleWillPop();
        if (shouldExit && mounted) Navigator.of(context).pop();
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
              padding: const EdgeInsets.all(15),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(children: [
                    IconButton(icon: const Icon(Icons.menu_rounded, size: 32), onPressed: () => _scaffoldKey.currentState?.openDrawer()),
                    const SizedBox(width: 5),
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

  Widget _buildLiveStatsGrid() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('specialRequests').where('driverId', isEqualTo: uid).where('status', isEqualTo: 'delivered').snapshots(),
      builder: (context, snapshot) {
        double todayEarnings = 0.0;
        int completedCount = 0;
        if (snapshot.hasData) {
          final startOfToday = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
          for (var doc in snapshot.data!.docs) {
            var d = doc.data() as Map<String, dynamic>;
            Timestamp? time = d['completedAt'] as Timestamp?;
            if (time != null && time.toDate().isAfter(startOfToday)) {
              completedCount++;
              todayEarnings += double.tryParse(d['driverNet']?.toString() ?? '0') ?? 0.0;
            }
          }
        }
        return SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 15, crossAxisSpacing: 15, childAspectRatio: 1.2),
            delegate: SliverChildListDelegate([
              _modernStatCard("أرباح اليوم", "${todayEarnings.toStringAsFixed(0)} ج.م", Icons.payments_rounded, Colors.green),
              _modernStatCard("طلباتك", "$completedCount", Icons.local_shipping_rounded, Colors.blue),
              _modernStatCard("المركبة", _vehicleConfig == 'motorcycleConfig' ? "موتوسيكل" : "سيارة", Icons.moped_rounded, Colors.orange),
              _modernStatCard("التقييم", "4.8", Icons.stars_rounded, Colors.amber),
            ]),
          ),
        );
      },
    );
  }

  Widget _modernStatCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(25), boxShadow: [BoxShadow(color: color.withOpacity(0.08), blurRadius: 15)]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(icon, color: color), const Spacer(), Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, fontFamily: 'Cairo')), Text(title, style: const TextStyle(fontSize: 12, color: Colors.grey, fontFamily: 'Cairo'))]),
    );
  }

  Widget _buildStatusToggle() {
    return GestureDetector(
      onTap: () => _toggleOnlineStatus(!isOnline),
      child: AnimatedContainer(duration: const Duration(milliseconds: 300), padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10), decoration: BoxDecoration(color: isOnline ? Colors.green[600] : Colors.red[600], borderRadius: BorderRadius.circular(15)), child: Row(children: [Icon(isOnline ? Icons.flash_on : Icons.flash_off, color: Colors.white, size: 18), const SizedBox(width: 8), Text(isOnline ? "متصل" : "أوفلاين", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontFamily: 'Cairo'))])),
    );
  }

  Widget _buildActiveOrderBanner() {
    return GestureDetector(
      onTap: () => setState(() => _selectedIndex = 1), // التوجه للرادار الذي سيحوله للطلب النشط
      child: Container(margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10), padding: const EdgeInsets.all(18), decoration: BoxDecoration(gradient: LinearGradient(colors: [Colors.orange[800]!, Colors.orange[600]!]), borderRadius: BorderRadius.circular(25)), child: const Row(children: [Icon(Icons.directions_run_rounded, color: Colors.white), SizedBox(width: 15), Expanded(child: Text("لديك رحلة نشطة الآن..", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontFamily: 'Cairo'))), Icon(Icons.arrow_forward_ios, color: Colors.white, size: 18)])),
    );
  }

  Widget _buildOtherPages() {
    // الترتيب حسب الـ BottomNav
    return [
      const SizedBox(), // تابة 0 (الرئيسية بتبني نفسها فوق)
      _activeOrderId != null ? ActiveOrderScreen(orderId: _activeOrderId!) : AvailableOrdersScreen(vehicleType: _vehicleConfig), // تابة 1 (الرادار)
      const OrdersHistoryScreen(), // تابة 2 (طلباتي)
      const WalletScreen() // تابة 3 (المحفظة)
    ][_selectedIndex];
  }

  Widget _buildBottomNav() {
    return BottomNavigationBar(
      currentIndex: _selectedIndex,
      onTap: _onItemTapped,
      selectedItemColor: Colors.orange[900],
      type: BottomNavigationBarType.fixed,
      selectedLabelStyle: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w900),
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.home_filled), label: "الرئيسية"),
        BottomNavigationBarItem(icon: Icon(Icons.radar), label: "الرادار"),
        BottomNavigationBarItem(icon: Icon(Icons.assignment_rounded), label: "طلباتي"),
        BottomNavigationBarItem(icon: Icon(Icons.account_balance_wallet_rounded), label: "المحفظة"),
      ],
    );
  }

  void _onItemTapped(int index) async {
    if (index == 1) {
       var doc = await FirebaseFirestore.instance.collection('freeDrivers').doc(uid).get();
       if (!(doc.data()?['hasAcceptedTerms'] ?? false)) { _checkSecurityAndTerms(); return; }
       if (!isOnline) { _showOnlineSnackBar(); return; }
    }
    setState(() => _selectedIndex = index);
  }

  void _showOnlineSnackBar() {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: const Text("⚠️ برجاء تفعيل وضع الاتصال لفتح الرادار", textAlign: TextAlign.center, style: TextStyle(fontFamily: 'Cairo')), backgroundColor: Colors.orange[900], behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))));
  }

  Widget _buildSideDrawer() {
    return Drawer(
      width: 75.w,
      child: Column(children: [
        Container(width: double.infinity, decoration: BoxDecoration(gradient: LinearGradient(colors: [Colors.orange[900]!, Colors.orange[700]!])), child: SafeArea(child: Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const CircleAvatar(radius: 30, backgroundColor: Colors.white, child: Icon(Icons.person, color: Colors.orange)), const SizedBox(height: 10), const Text("كابتن أكسب", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontFamily: 'Cairo')), Text(FirebaseAuth.instance.currentUser?.email ?? "", style: const TextStyle(color: Colors.white70, fontSize: 10))])))),
        _buildDrawerItem(Icons.account_circle_outlined, "حسابي", () => Navigator.push(context, MaterialPageRoute(builder: (context) => const ProfileScreen()))),
        _buildDrawerItem(Icons.help_outline, "الدعم", () => Navigator.push(context, MaterialPageRoute(builder: (context) => const SupportScreen()))),
        const Spacer(),
        ListTile(leading: const Icon(Icons.logout, color: Colors.red), title: const Text("خروج", style: TextStyle(color: Colors.red, fontFamily: 'Cairo')), onTap: () => FirebaseAuth.instance.signOut().then((_) => Navigator.pushReplacementNamed(context, '/login'))),
      ]),
    );
  }

  Widget _buildDrawerItem(IconData icon, String title, VoidCallback onTap) {
    return ListTile(leading: Icon(icon), title: Text(title, style: const TextStyle(fontFamily: 'Cairo')), onTap: onTap);
  }
}

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:sizer/sizer.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

// الصفحات التابعة - تأكد أن هذه الملفات موجودة في مشروعك بنفس الأسماء
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

  @override
  void initState() {
    super.initState();
    _loadVehicleConfig();
    _fetchInitialStatus(); 
    _listenToActiveOrders();
    
    // فحص الشروط والأذونات بعد رسم الواجهة مباشرة
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkTermsAndPermissions();
    });
  }

  // --- 🛡️ منطق فحص الشروط من مجموعة freeDrivers ---
  Future<void> _checkTermsAndPermissions() async {
    if (uid.isEmpty) return;
    try {
      // الفحص في المجموعة الصحيحة حسب صورة قاعدة البيانات
      var userDoc = await FirebaseFirestore.instance.collection('freeDrivers').doc(uid).get();
      
      bool hasAccepted = false;
      if(userDoc.exists){
        hasAccepted = userDoc.data()?['hasAcceptedTerms'] ?? false;
      }

      if (!hasAccepted) {
        if (!mounted) return;
        
        // فتح صفحة الشروط (إجبارية)
        final result = await showModalBottomSheet<bool>(
          context: context,
          isScrollControlled: true,
          isDismissible: false,
          enableDrag: false,
          backgroundColor: Colors.transparent,
          builder: (context) => FreelanceTermsScreen(userId: uid),
        );
        
        if (result == true) {
           _requestNotificationPermissionWithDisclosure();
        }
      } else {
        // إذا وافق سابقاً، نطلب إذن الإشعارات لو لم يكن مفعلاً
        _requestNotificationPermissionWithDisclosure();
      }
    } catch (e) {
      debugPrint("Error checking terms: $e");
    }
  }

  // --- 🔗 ربط المندوب بنظام AWS ---
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
      }
    } catch (e) {
      debugPrint("❌ AWS Sync Error: $e");
    }
  }

  // --- 🔔 طلب إذن الإشعارات ---
  Future<void> _requestNotificationPermissionWithDisclosure() async {
    FirebaseMessaging messaging = FirebaseMessaging.instance;
    NotificationSettings settings = await messaging.getNotificationSettings();
    
    if (settings.authorizationStatus != AuthorizationStatus.authorized) {
      if (!mounted) return;
      await Future.delayed(const Duration(milliseconds: 800));

      if (!mounted) return;
      bool? proceed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
          title: const Text("تفعيل التنبيهات", style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
          content: const Text("كابتن أكسب، نحتاج لتفعيل الإشعارات لإرسال طلبات الرادار إليك فوراً.", 
            textAlign: TextAlign.center, style: TextStyle(fontFamily: 'Cairo')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("لاحقاً")),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange[900], shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              onPressed: () => Navigator.pop(context, true),
              child: const Text("تفعيل", style: TextStyle(color: Colors.white, fontFamily: 'Cairo')),
            ),
          ],
        ),
      );

      if (proceed == true) {
        NotificationSettings newSettings = await messaging.requestPermission(alert: true, badge: true, sound: true);
        if (newSettings.authorizationStatus == AuthorizationStatus.authorized) {
          await _syncFreeDriverWithAWS();
        }
      }
    }
  }

  // --- ⚙️ دوال البيانات ---
  void _loadVehicleConfig() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _vehicleConfig = prefs.getString('user_vehicle_config') ?? 'motorcycleConfig');
  }

  void _fetchInitialStatus() async {
    var doc = await FirebaseFirestore.instance.collection('freeDrivers').doc(uid).get();
    if (doc.exists && mounted) {
      setState(() => isOnline = doc.data()?['isOnline'] ?? false);
    }
  }

  void _listenToActiveOrders() {
    FirebaseFirestore.instance
        .collection('specialRequests')
        .where('driverId', isEqualTo: uid)
        .where('status', whereIn: ['accepted', 'picked_up'])
        .snapshots()
        .listen((snap) {
      if (mounted) setState(() => _activeOrderId = snap.docs.isNotEmpty ? snap.docs.first.id : null);
    });
  }

  void _toggleOnlineStatus(bool value) async {
    setState(() => isOnline = value);
    await FirebaseFirestore.instance.collection('freeDrivers').doc(uid).update({
      'isOnline': value,
      'lastSeen': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _launchPrivacyPolicy() async {
    final Uri url = Uri.parse('https://aksab.shop/');
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) return;
  }

  void _onItemTapped(int index) {
    if (index == 1 && !isOnline) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("برجاء تفعيل وضع الاتصال أولاً")));
      return; 
    }
    setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      drawer: _buildSideDrawer(),
      backgroundColor: const Color(0xFFF4F7FA),
      body: _selectedIndex == 0 ? _buildModernDashboard() : _buildOtherPages(),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  // --- 🧱 واجهات العرض الكاملة ---

  Widget _buildSideDrawer() {
    return Drawer(
      width: 75.w,
      child: Column(
        children: [
          UserAccountsDrawerHeader(
            decoration: BoxDecoration(color: Colors.orange[900]),
            accountName: const Text("كابتن أكسب", style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
            accountEmail: Text(FirebaseAuth.instance.currentUser?.email ?? ""),
            currentAccountPicture: const CircleAvatar(backgroundColor: Colors.white, child: Icon(Icons.person, color: Colors.orange)),
          ),
          ListTile(leading: const Icon(Icons.person), title: const Text("الملف الشخصي"), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const ProfileScreen()))),
          ListTile(leading: const Icon(Icons.privacy_tip), title: const Text("سياسة الخصوصية"), onTap: _launchPrivacyPolicy),
          ListTile(leading: const Icon(Icons.support_agent), title: const Text("الدعم الفني"), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const SupportScreen()))),
          const Spacer(),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text("تسجيل الخروج", style: TextStyle(color: Colors.red)),
            onTap: () async {
              await FirebaseAuth.instance.signOut();
              if (mounted) Navigator.pushReplacementNamed(context, '/login');
            },
          ),
          SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildModernDashboard() {
    return SafeArea(
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(icon: const Icon(Icons.menu_open, size: 30), onPressed: () => _scaffoldKey.currentState?.openDrawer()),
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
        double earnings = 0;
        int count = 0;
        if (snapshot.hasData) {
          count = snapshot.data!.docs.length;
          for (var d in snapshot.data!.docs) {
             earnings += double.tryParse((d.data() as Map)['driverNet']?.toString() ?? '0') ?? 0;
          }
        }
        return SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 15, crossAxisSpacing: 15, childAspectRatio: 1.3),
            delegate: SliverChildListDelegate([
              _statCard("الأرباح", "${earnings.toStringAsFixed(1)}", Icons.monetization_on, Colors.green),
              _statCard("الطلبات", "$count", Icons.shopping_bag, Colors.blue),
              _statCard("المركبة", _vehicleConfig == 'motorcycleConfig' ? "موتوسيكل" : "سيارة", Icons.vape_free, Colors.orange),
              _statCard("التقييم", "4.9", Icons.star, Colors.amber),
            ]),
          ),
        );
      },
    );
  }

  Widget _statCard(String label, String val, IconData icon, Color col) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 5)]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: col, size: 20),
          const Spacer(),
          Text(val, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12, fontFamily: 'Cairo')),
        ],
      ),
    );
  }

  Widget _buildStatusToggle() {
    return SwitchListTile(
      value: isOnline,
      onChanged: _toggleOnlineStatus,
      title: Text(isOnline ? "متصل" : "أوفلاين", style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, color: isOnline ? Colors.green : Colors.red)),
    );
  }

  Widget _buildActiveOrderBanner() {
    return Container(
      margin: const EdgeInsets.all(20),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(color: Colors.orange, borderRadius: BorderRadius.circular(15)),
      child: const Row(children: [Icon(Icons.delivery_dining, color: Colors.white), SizedBox(width: 10), Text("لديك رحلة جارية الآن", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontFamily: 'Cairo'))]),
    );
  }

  Widget _buildOtherPages() {
    return [
      const SizedBox(),
      _activeOrderId != null ? ActiveOrderScreen(orderId: _activeOrderId!) : AvailableOrdersScreen(vehicleType: _vehicleConfig),
      const OrdersHistoryScreen(),
      const WalletScreen(),
    ][_selectedIndex];
  }

  Widget _buildBottomNav() {
    return BottomNavigationBar(
      currentIndex: _selectedIndex,
      onTap: _onItemTapped,
      type: BottomNavigationBarType.fixed,
      selectedItemColor: Colors.orange[900],
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.dashboard), label: "الرئيسية"),
        BottomNavigationBarItem(icon: Icon(Icons.radar), label: "الرادار"),
        BottomNavigationBarItem(icon: Icon(Icons.history), label: "طلباتي"),
        BottomNavigationBarItem(icon: Icon(Icons.account_balance_wallet), label: "المحفظة"),
      ],
    );
  }
}

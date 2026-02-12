// lib/screens/free_driver_home_screen.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'available_orders_screen.dart';
import 'active_order_screen.dart';
import 'wallet_screen.dart';

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
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestNotificationPermissionOnce();
    });
  }

  Future<void> _requestNotificationPermissionOnce() async {
    FirebaseMessaging messaging = FirebaseMessaging.instance;
    await messaging.requestPermission(alert: true, badge: true, sound: true);
  }

  void _onItemTapped(int index) {
    if (index == 1 && !isOnline) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            "⚠️ برجاء تفعيل وضع الاتصال (أونلاين) لفتح الرادار",
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
          ),
          backgroundColor: Colors.orange[900],
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          margin: const EdgeInsets.all(20),
        ),
      );
      return; 
    }
    setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      drawer: _buildSideDrawer(), // الشريط الجانبي الجديد
      backgroundColor: const Color(0xFFF4F7FA),
      body: SafeArea(
        child: _selectedIndex == 0 ? _buildModernDashboard() : _buildOtherPages(),
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  // --- الشريط الجانبي (Drawer) ---
  Widget _buildSideDrawer() {
    return Drawer(
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(topLeft: Radius.circular(30), bottomLeft: Radius.circular(30)),
      ),
      child: Column(
        children: [
          UserAccountsDrawerHeader(
            decoration: BoxDecoration(
              color: Colors.orange[900],
              image: DecorationImage(
                image: const AssetImage('assets/images/drawer_bg.png'), // اختياري لو عندك خلفية
                fit: BoxFit.cover,
                colorFilter: ColorFilter.mode(Colors.black.withOpacity(0.1), BlendMode.dstATop),
              ),
            ),
            accountName: const Text("كابتن أكسب", style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 18)),
            accountEmail: Text(FirebaseAuth.instance.currentUser?.email ?? "لا يوجد بريد", style: const TextStyle(fontFamily: 'Cairo')),
            currentAccountPicture: const CircleAvatar(
              backgroundColor: Colors.white,
              child: Icon(Icons.person, size: 45, color: Colors.orange),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.account_circle_outlined, color: Colors.blueGrey),
            title: const Text("حسابي", style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w600)),
            onTap: () {
              Navigator.pop(context);
              // أضف كود الانتقال لصفحة البروفايل هنا
            },
          ),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined, color: Colors.blueGrey),
            title: const Text("سياسة الخصوصية", style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w600)),
            onTap: () {
              Navigator.pop(context);
              // أضف كود عرض سياسة الخصوصية هنا
            },
          ),
          ListTile(
            leading: const Icon(Icons.help_outline_rounded, color: Colors.blueGrey),
            title: const Text("الدعم الفني", style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w600)),
            onTap: () => Navigator.pop(context),
          ),
          const Spacer(),
          const Divider(indent: 20, endIndent: 20),
          ListTile(
            leading: const Icon(Icons.logout_rounded, color: Colors.redAccent),
            title: const Text("تسجيل الخروج", style: TextStyle(fontFamily: 'Cairo', color: Colors.redAccent, fontWeight: FontWeight.bold)),
            onTap: () async {
              await FirebaseAuth.instance.signOut();
              if (mounted) Navigator.pushReplacementNamed(context, '/login');
            },
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  // --- واجهة لوحة التحكم ---
  Widget _buildModernDashboard() {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 30, 20, 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.menu_rounded, size: 32, color: Colors.black),
                      onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                    ),
                    const SizedBox(width: 5),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("أهلاً بك 👋", style: TextStyle(fontSize: 16, color: Colors.blueGrey, fontFamily: 'Cairo')),
                        const Text("كابتن أكسب", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black, fontFamily: 'Cairo')),
                      ],
                    ),
                  ],
                ),
                _buildStatusToggle(),
              ],
            ),
          ),
        ),
        if (_activeOrderId != null)
          SliverToBoxAdapter(child: _buildActiveOrderBanner()),
        _buildLiveStatsGrid(),
      ],
    );
  }

  Widget _buildLiveStatsGrid() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('specialRequests')
          .where('driverId', isEqualTo: uid)
          .where('status', isEqualTo: 'delivered')
          .snapshots(),
      builder: (context, ordersSnapshot) {
        double todayEarnings = 0.0;
        int completedCount = 0;

        if (ordersSnapshot.hasData) {
          final today = DateTime.now();
          final startOfToday = DateTime(today.year, today.month, today.day);
          for (var doc in ordersSnapshot.data!.docs) {
            var d = doc.data() as Map<String, dynamic>;
            Timestamp? time = d['completedAt'] as Timestamp?;
            if (time != null && time.toDate().isAfter(startOfToday)) {
              completedCount++;
              todayEarnings += double.tryParse(d['price']?.toString() ?? '0') ?? 0.0;
            }
          }
        }

        return SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 20,
              crossAxisSpacing: 20,
              childAspectRatio: 0.95,
            ),
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
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(color: color.withOpacity(0.1), blurRadius: 20, offset: const Offset(0, 10)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(15)),
            child: Icon(icon, color: color, size: 28),
          ),
          const Spacer(),
          Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
          Text(title, style: const TextStyle(fontSize: 14, color: Colors.grey, fontFamily: 'Cairo')),
        ],
      ),
    );
  }

  Widget _buildStatusToggle() {
    return GestureDetector(
      onTap: () => _toggleOnlineStatus(!isOnline),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
        decoration: BoxDecoration(
          color: isOnline ? Colors.green[600] : Colors.red[600],
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(color: (isOnline ? Colors.green : Colors.red).withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 5)),
          ],
        ),
        child: Row(
          children: [
            Icon(isOnline ? Icons.flash_on : Icons.flash_off, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text(isOnline ? "متصل" : "أوفلاين", 
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16, fontFamily: 'Cairo')),
          ],
        ),
      ),
    );
  }

  void _toggleOnlineStatus(bool value) async {
    setState(() => isOnline = value);
    await FirebaseFirestore.instance.collection('freeDrivers').doc(uid).update({
      'isOnline': value,
      'lastSeen': FieldValue.serverTimestamp(),
    });
  }

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

  Widget _buildActiveOrderBanner() {
    return GestureDetector(
      onTap: () => setState(() => _selectedIndex = 1),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [Colors.orange[800]!, Colors.orange[600]!]),
          borderRadius: BorderRadius.circular(25),
          boxShadow: [BoxShadow(color: Colors.orange.withOpacity(0.3), blurRadius: 15, offset: const Offset(0, 8))],
        ),
        child: Row(
          children: [
            const CircleAvatar(backgroundColor: Colors.white24, child: Icon(Icons.directions_run, color: Colors.white)),
            const SizedBox(width: 15),
            const Expanded(
              child: Text("لديك طلب جاري تنفيذه حالياً", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18, fontFamily: 'Cairo')),
            ),
            const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildOtherPages() {
    final List<Widget> pages = [
      const SizedBox(),
      _activeOrderId != null 
          ? ActiveOrderScreen(orderId: _activeOrderId!) 
          : AvailableOrdersScreen(vehicleType: _vehicleConfig),
      const Center(child: Text("سجل الطلبات قريباً", style: TextStyle(fontFamily: 'Cairo', fontSize: 20))),
      const WalletScreen(),
    ];
    return pages[_selectedIndex];
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: BoxDecoration(
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20)],
      ),
      child: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        selectedItemColor: Colors.orange[900],
        unselectedItemColor: Colors.grey[400],
        showUnselectedLabels: true,
        iconSize: 28,
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 14),
        unselectedLabelStyle: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_filled), label: "الرئيسية"),
          BottomNavigationBarItem(icon: Icon(Icons.radar), label: "الرادار"),
          BottomNavigationBarItem(icon: Icon(Icons.assignment_rounded), label: "طلباتي"),
          BottomNavigationBarItem(icon: Icon(Icons.account_balance_wallet_rounded), label: "المحفظة"),
        ],
      ),
    );
  }
}

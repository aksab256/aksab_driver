// lib/screens/free_driver_home_screen.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:sizer/sizer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:app_settings/app_settings.dart';
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

  @override
  void initState() {
    super.initState();
    _loadVehicleConfig();
    _fetchInitialStatus();
    _listenToActiveOrders();
    
    // ✅ فحص الإشعارات المتوافق مع سياسات جوجل
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkNotificationPermission();
    });
  }

  // 🛡️ منطق الإشعارات الاحترافي
  Future<void> _checkNotificationPermission() async {
    FirebaseMessaging messaging = FirebaseMessaging.instance;
    NotificationSettings settings = await messaging.getNotificationSettings();

    if (settings.authorizationStatus == AuthorizationStatus.notDetermined) {
      await messaging.requestPermission(alert: true, badge: true, sound: true);
    } else if (settings.authorizationStatus == AuthorizationStatus.denied) {
      _showSettingsRedirectDialog();
    }
  }

  void _showSettingsRedirectDialog() {
    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text("تفعيل الإشعارات", style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
          content: const Text("استقبال الطلبات يتطلب تفعيل الإشعارات. يرجى تفعيلها من إعدادات الهاتف لضمان وصول التنبيهات إليك.", style: TextStyle(fontFamily: 'Cairo')),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                AppSettings.openAppSettings(type: AppSettingsType.notification);
              },
              child: const Text("الذهاب للإعدادات", style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: SafeArea(
        child: _selectedIndex == 0 ? _buildModernDashboard() : _buildOtherPages(),
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  // 🏗️ واجهة لوحة التحكم العصرية
  Widget _buildModernDashboard() {
    return CustomScrollView(
      slivers: [
        // الهيدر (الترحيب وحالة الاتصال)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 25, 20, 15),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("أهلاً بك، مندوبنا 👋", style: TextStyle(fontSize: 11.sp, color: Colors.grey[600], fontFamily: 'Cairo')),
                    Text("أكسب مناديب", style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold, color: Colors.black, fontFamily: 'Cairo')),
                  ],
                ),
                _buildStatusToggle(),
              ],
            ),
          ),
        ),

        // تنبيه الطلب النشط
        if (_activeOrderId != null)
          SliverToBoxAdapter(child: _buildActiveOrderBanner()),

        // الإحصائيات الحية
        _buildLiveStatsGrid(),
      ],
    );
  }

  // 📊 ربط البيانات بالفايربيز (أرباح، طلبات، تقييم)
  Widget _buildLiveStatsGrid() {
    return StreamBuilder<QuerySnapshot>(
      // مراقبة طلبات اليوم المسلمة
      stream: FirebaseFirestore.instance
          .collection('specialRequests')
          .where('driverId', isEqualTo: uid)
          .where('status', isEqualTo: 'delivered')
          .snapshots(),
      builder: (context, ordersSnapshot) {
        
        return StreamBuilder<DocumentSnapshot>(
          // مراقبة بيانات المندوب (التقييم)
          stream: FirebaseFirestore.instance.collection('freeDrivers').doc(uid).snapshots(),
          builder: (context, driverSnapshot) {
            
            double todayEarnings = 0.0;
            int completedCount = 0;
            double rating = 4.0; // البداية بـ 4 نجوم

            // حساب أرباح اليوم
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

            // حساب التقييم الاحترافي
            if (driverSnapshot.hasData && driverSnapshot.data!.exists) {
              var dData = driverSnapshot.data!.data() as Map<String, dynamic>;
              double totalStars = double.tryParse(dData['totalStars']?.toString() ?? '0') ?? 0.0;
              int reviews = int.tryParse(dData['reviewsCount']?.toString() ?? '0') ?? 0;
              rating = (4.0 + totalStars) / (1 + reviews);
            }

            return SliverPadding(
              padding: const EdgeInsets.all(20),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 15,
                  crossAxisSpacing: 15,
                  childAspectRatio: 1.1,
                ),
                delegate: SliverChildListDelegate([
                  _modernStatCard("أرباح اليوم", "${todayEarnings.toStringAsFixed(2)} ج.م", Icons.account_balance_wallet_rounded, Colors.blue),
                  _modernStatCard("طلبات منفذة", "$completedCount", Icons.shopping_bag_rounded, Colors.orange),
                  _modernStatCard("نوع المركبة", _vehicleConfig == 'motorcycleConfig' ? "موتوسيكل" : "سيارة", Icons.moped_rounded, Colors.purple),
                  _modernStatCard("تقييمك", rating.toStringAsFixed(1), Icons.star_rounded, Colors.amber),
                ]),
              ),
            );
          },
        );
      },
    );
  }

  Widget _modernStatCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: color.withOpacity(0.08), blurRadius: 15, offset: const Offset(0, 8)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 22.sp),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value, style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
              Text(title, style: TextStyle(fontSize: 9.sp, color: Colors.grey, fontFamily: 'Cairo')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusToggle() {
    return GestureDetector(
      onTap: () => _toggleOnlineStatus(!isOnline),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isOnline ? Colors.green[50] : Colors.red[50],
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: isOnline ? Colors.green : Colors.red, width: 1.5),
        ),
        child: Row(
          children: [
            Container(
              width: 8, height: 8,
              decoration: BoxDecoration(color: isOnline ? Colors.green : Colors.red, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Text(isOnline ? "متصل" : "غير متصل", 
              style: TextStyle(color: isOnline ? Colors.green[800] : Colors.red[800], fontWeight: FontWeight.bold, fontSize: 10.sp, fontFamily: 'Cairo')),
          ],
        ),
      ),
    );
  }

  // --- المنطق (Logic) ---

  void _toggleOnlineStatus(bool value) async {
    NotificationSettings settings = await FirebaseMessaging.instance.getNotificationSettings();
    if (value && settings.authorizationStatus != AuthorizationStatus.authorized) {
      _showSettingsRedirectDialog();
      return;
    }

    await FirebaseFirestore.instance.collection('freeDrivers').doc(uid).update({
      'isOnline': value,
      'lastSeen': FieldValue.serverTimestamp(),
    });
    setState(() => isOnline = value);
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
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [Colors.orange[800]!, Colors.orange[900]!]),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            const Icon(Icons.delivery_dining, color: Colors.white, size: 30),
            const SizedBox(width: 15),
            const Expanded(
              child: Text("لديك طلب نشط جاري تنفيذه", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
            ),
            const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 15),
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
      const Center(child: Text("سجل الطلبات قريباً")),
      const WalletScreen(),
    ];
    return pages[_selectedIndex];
  }

  Widget _buildBottomNav() {
    return BottomNavigationBar(
      currentIndex: _selectedIndex,
      onTap: (i) => setState(() => _selectedIndex = i),
      selectedItemColor: Colors.orange[900],
      unselectedItemColor: Colors.grey[400],
      showUnselectedLabels: true,
      type: BottomNavigationBarType.fixed,
      selectedLabelStyle: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
      unselectedLabelStyle: const TextStyle(fontFamily: 'Cairo'),
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.grid_view_rounded), label: "الرئيسية"),
        BottomNavigationBarItem(icon: Icon(Icons.explore_rounded), label: "الرادار"),
        BottomNavigationBarItem(icon: Icon(Icons.history_rounded), label: "طلباتي"),
        BottomNavigationBarItem(icon: Icon(Icons.wallet_rounded), label: "المحفظة"),
      ],
    );
  }
}

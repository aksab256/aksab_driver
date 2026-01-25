// lib/screens/free_driver_home_screen.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:sizer/sizer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_messaging/firebase_messaging.dart'; // مكتبة الإشعارات
import 'package:app_settings/app_settings.dart'; // مكتبة لفتح الإعدادات (تحتاج لإضافتها في pubspec.yaml)
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

  @override
  void initState() {
    super.initState();
    _loadVehicleConfig();
    _fetchInitialStatus();
    _listenToActiveOrders();
    
    // فحص أذونات الإشعارات فور الدخول
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAndRequestNotificationPermission();
    });
  }

  // 🛡️ دالة الفحص الذكي للإشعارات
  Future<void> _checkAndRequestNotificationPermission() async {
    FirebaseMessaging messaging = FirebaseMessaging.instance;
    NotificationSettings settings = await messaging.getNotificationSettings();

    // الحالة 1: لم يتم طلب الإذن من قبل (أول مرة)
    if (settings.authorizationStatus == AuthorizationStatus.notDetermined) {
      _showRationaleDialog();
    } 
    // الحالة 2: المندوب رفض الإشعارات نهائياً من إعدادات النظام
    else if (settings.authorizationStatus == AuthorizationStatus.denied) {
      _showSettingsRedirectDialog();
    }
  }

  // ديالوج الشرح (الرسالة التمهيدية)
  void _showRationaleDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _buildCustomDialog(
        title: "تفعيل التنبيهات",
        content: "من فضلك، فعل الإشعارات لتتمكن من استقبال طلبات التوصيل الجديدة فور صدورها. بدون هذا الإذن، لن تصلك تنبيهات العمل.",
        buttonText: "موافق، تفعيل الآن",
        onPressed: () async {
          Navigator.pop(context);
          await FirebaseMessaging.instance.requestPermission(alert: true, badge: true, sound: true);
        },
      ),
    );
  }

  // ديالوج التوجيه للإعدادات (لو هو قافلها من الموبايل نفسه)
  void _showSettingsRedirectDialog() {
    showDialog(
      context: context,
      builder: (context) => _buildCustomDialog(
        title: "الإشعارات معطلة",
        content: "لقد قمت بتعطيل إشعارات التطبيق من إعدادات هاتفك. يرجى تفعيلها لتتمكن من استلام الطلبات.",
        buttonText: "الذهاب للإعدادات",
        onPressed: () {
          Navigator.pop(context);
          AppSettings.openAppSettings(type: AppSettingsType.notification); // تفتح إعدادات إشعارات التطبيق
        },
      ),
    );
  }

  Widget _buildCustomDialog({required String title, required String content, required String buttonText, required VoidCallback onPressed}) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(title, style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
        content: Text(content, style: const TextStyle(fontFamily: 'Cairo')),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange[900]),
            onPressed: onPressed,
            child: Text(buttonText, style: const TextStyle(color: Colors.white, fontFamily: 'Cairo')),
          ),
        ],
      ),
    );
  }

  void _loadVehicleConfig() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _vehicleConfig = prefs.getString('user_vehicle_config') ?? 'motorcycleConfig';
    });
  }

  void _listenToActiveOrders() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    FirebaseFirestore.instance
        .collection('specialRequests')
        .where('driverId', isEqualTo: uid)
        .where('status', whereIn: ['accepted', 'picked_up'])
        .snapshots()
        .listen((snapshot) {
      if (mounted) {
        setState(() {
          _activeOrderId = snapshot.docs.isNotEmpty ? snapshot.docs.first.id : null;
        });
      }
    });
  }

  void _fetchInitialStatus() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      var doc = await FirebaseFirestore.instance.collection('freeDrivers').doc(uid).get();
      if (doc.exists && mounted) {
        setState(() => isOnline = doc.data()?['isOnline'] ?? false);
      }
    }
  }

  void _toggleOnlineStatus(bool value) async {
    // فحص إضافي: لا تسمح له بالتحول لـ Online إلا لو الإشعارات مفعلة
    NotificationSettings settings = await FirebaseMessaging.instance.getNotificationSettings();
    if (value && settings.authorizationStatus != AuthorizationStatus.authorized) {
      _showSettingsRedirectDialog();
      return;
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      await FirebaseFirestore.instance.collection('freeDrivers').doc(uid).update({
        'isOnline': value,
        'lastSeen': FieldValue.serverTimestamp(),
      });
      setState(() => isOnline = value);
    }
  }

  void _logout() async {
    await FirebaseAuth.instance.signOut();
    Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
  }

  void _softDeleteAccount() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    bool confirm = await _showConfirmDialog();
    if (confirm && uid != null) {
      await FirebaseFirestore.instance.collection('freeDrivers').doc(uid).update({'status': 'deleted'});
      _logout();
    }
  }

  Future<bool> _showConfirmDialog() async {
    return await showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text("حذف الحساب", textAlign: TextAlign.right),
        content: const Text("هل أنت متأكد من رغبتك في إغلاق الحساب؟ سيتم مراجعة طلبك من الإدارة.", textAlign: TextAlign.right),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text("إلغاء")),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text("تأكيد الحذف", style: TextStyle(color: Colors.red))),
        ],
      ),
    ) ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> _pages = [
      _buildDashboardContent(),
      _activeOrderId != null 
          ? ActiveOrderScreen(orderId: _activeOrderId!) 
          : AvailableOrdersScreen(vehicleType: _vehicleConfig),
      const Center(child: Text("سجل الطلبات قريباً")),
      const WalletScreen(),
    ];

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        iconTheme: const IconThemeData(color: Colors.black),
        title: Text(_activeOrderId != null ? "طلب نشط" : "أكسب مناديب", 
          style: TextStyle(color: Colors.black, fontSize: 16.sp, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.only(left: 10),
            child: Switch(value: isOnline, activeColor: Colors.orange[900], onChanged: _toggleOnlineStatus),
          ),
        ],
      ),
      drawer: _buildSideDrawer(),
      body: _pages[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) {
          if (index == 1 && !isOnline && _activeOrderId == null) {
             _showStatusAlert();
             return;
          }
          setState(() => _selectedIndex = index);
        },
        selectedItemColor: Colors.orange[900],
        unselectedItemColor: Colors.grey[600],
        type: BottomNavigationBarType.fixed,
        items: [
          const BottomNavigationBarItem(icon: Icon(Icons.dashboard), label: "الرئيسية"),
          BottomNavigationBarItem(
            icon: _activeOrderId != null 
                ? const Icon(Icons.directions_run, color: Colors.green) 
                : (isOnline ? _buildPulseIcon() : const Icon(Icons.radar)), 
            label: "الرادار"
          ),
          const BottomNavigationBarItem(icon: Icon(Icons.history), label: "طلباتي"),
          const BottomNavigationBarItem(icon: Icon(Icons.account_balance_wallet), label: "المحفظة"),
        ],
      ),
    );
  }

  // ... (باقي دوال الـ UI مثل _buildSideDrawer و _buildDashboardContent تظل كما هي)
  Widget _buildSideDrawer() {
    return Drawer(
      child: Column(
        children: [
          UserAccountsDrawerHeader(
            decoration: BoxDecoration(color: Colors.orange[900]),
            accountName: const Text("مندوب أكسب", style: TextStyle(fontFamily: 'Cairo')),
            accountEmail: Text(FirebaseAuth.instance.currentUser?.email ?? ""),
            currentAccountPicture: const CircleAvatar(backgroundColor: Colors.white, child: Icon(Icons.person, size: 40, color: Colors.black)),
          ),
          ListTile(
            leading: const Icon(Icons.person_outline, color: Colors.blue),
            title: const Text("حسابي (إغلاق الحساب)", style: TextStyle(fontFamily: 'Cairo')),
            onTap: _softDeleteAccount,
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text("تسجيل الخروج", style: TextStyle(fontFamily: 'Cairo')),
            onTap: _logout,
          ),
        ],
      ),
    );
  }

  Widget _buildDashboardContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          if (_activeOrderId != null) _activeOrderBanner(),
          _buildLiveStatsGrid(),
        ],
      ),
    );
  }

  Widget _buildLiveStatsGrid() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('specialRequests').where('driverId', isEqualTo: uid).where('status', isEqualTo: 'delivered').snapshots(),
      builder: (context, snapshot) {
        double todayTotalEarnings = 0.0;
        int completedCount = 0;

        if (snapshot.hasData) {
          final todayStart = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
          for (var doc in snapshot.data!.docs) {
            final data = doc.data() as Map<String, dynamic>;
            Timestamp? completedAt = data['completedAt'] as Timestamp?;
            if (completedAt != null && completedAt.toDate().isAfter(todayStart)) {
              completedCount++;
              todayTotalEarnings += double.tryParse(data['price'].toString()) ?? 0.0;
            }
          }
        }

        return GridView.count(
          shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2, crossAxisSpacing: 15, mainAxisSpacing: 15,
          children: [
            _statCard("أرباح اليوم", "${todayTotalEarnings.toStringAsFixed(2)} ج.م", Icons.monetization_on, Colors.blue),
            _statCard("طلبات منفذة", "$completedCount", Icons.shopping_basket, Colors.orange),
            _statCard("نوع المركبة", _vehicleConfig == 'motorcycleConfig' ? "موتوسيكل" : "سيارة", Icons.vape_free, Colors.purple),
            _statCard("تقييمك", "5.0", Icons.star, Colors.amber),
          ],
        );
      },
    );
  }

  Widget _statCard(String title, String value, IconData icon, Color color) {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [const BoxShadow(color: Colors.black12, blurRadius: 10)]),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, color: color, size: 25.sp),
        const SizedBox(height: 10),
        Text(title, style: TextStyle(color: Colors.grey, fontSize: 10.sp, fontFamily: 'Cairo')),
        Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.sp)),
      ]),
    );
  }

  Widget _buildPulseIcon() {
    return TweenAnimationBuilder(
      tween: Tween<double>(begin: 1.0, end: 1.2),
      duration: const Duration(milliseconds: 800),
      builder: (context, double scale, child) => Transform.scale(
        scale: scale,
        child: Icon(Icons.radar, color: Colors.orange[900]),
      ),
      onEnd: () => setState(() {}),
    );
  }

  void _showStatusAlert() {
     showDialog(
       context: context,
       builder: (c) => AlertDialog(
         title: const Text("تنبيه", textAlign: TextAlign.right, style: TextStyle(fontFamily: 'Cairo')),
         content: const Text("يجب تفعيل وضع الاتصال (Online) أولاً لاستلام الطلبات.", textAlign: TextAlign.right, style: TextStyle(fontFamily: 'Cairo')),
         actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text("حسناً"))],
       ),
     );
  }

  Widget _activeOrderBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(color: Colors.orange[900], borderRadius: BorderRadius.circular(20)),
      child: Row(children: [
        const Icon(Icons.delivery_dining, color: Colors.white),
        const SizedBox(width: 10),
        const Expanded(child: Text("لديك طلب نشط", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontFamily: 'Cairo'))),
        TextButton(onPressed: () => setState(() => _selectedIndex = 1), child: const Text("تابعه", style: TextStyle(color: Colors.yellow, fontFamily: 'Cairo')))
      ]),
    );
  }
}

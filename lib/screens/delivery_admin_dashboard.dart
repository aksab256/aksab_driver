import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:sizer/sizer.dart';
import 'package:firebase_messaging/firebase_messaging.dart'; // إضافة المكتبة

// استدعاء الصفحات التابعة
import 'delivery_management_screen.dart'; 
import 'delivery_fleet_screen.dart';      
import 'manager_geo_dist_screen.dart';    
import 'ProfileScreen.dart'; 

class DeliveryAdminDashboard extends StatefulWidget {
  const DeliveryAdminDashboard({super.key});

  @override
  State<DeliveryAdminDashboard> createState() => _DeliveryAdminDashboardState();
}

class _DeliveryAdminDashboardState extends State<DeliveryAdminDashboard> {
  final String? _uid = FirebaseAuth.instance.currentUser?.uid;
  Map<String, dynamic>? _userData;
  bool _isLoading = true;

  int _totalOrders = 0;
  double _totalSales = 0;
  int _totalReps = 0;

  @override
  void initState() {
    super.initState();
    _checkAuthAndLoadData();
    
    // طلب الإذن للإدارة فور الدخول مع الإفصاح
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestNotificationPermissionWithDisclosure();
    });
  }

  // --- 🔔 دالة الإفصاح وطلب إذن الإشعارات للإدارة ---
  Future<void> _requestNotificationPermissionWithDisclosure() async {
    FirebaseMessaging messaging = FirebaseMessaging.instance;
    NotificationSettings settings = await messaging.getNotificationSettings();
    
    if (settings.authorizationStatus == AuthorizationStatus.notDetermined) {
      if (!mounted) return;
      
      bool? proceed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
          title: Column(
            children: [
              Icon(Icons.admin_panel_settings_rounded, size: 45, color: const Color(0xFF2C3E50)),
              const SizedBox(height: 15),
              const Text("تفعيل إشعارات النظام", 
                style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w900, fontSize: 16)),
            ],
          ),
          content: const Text(
            "بصفتك مسؤولاً في النظام، ننصح بتفعيل الإشعارات لتصلك تنبيهات العمليات الحرجة، تقارير الأداء، وأي تحديثات فورية تخص طاقم المناديب.",
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'Cairo', fontSize: 13),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("تجاهل", style: TextStyle(fontFamily: 'Cairo', color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2C3E50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              ),
              onPressed: () => Navigator.pop(context, true),
              child: const Text("تفعيل الآن", style: TextStyle(fontFamily: 'Cairo', color: Colors.white)),
            ),
          ],
        ),
      );

      if (proceed == true) {
        await messaging.requestPermission(alert: true, badge: true, sound: true);
      }
    }
  }

  Future<void> _checkAuthAndLoadData() async {
    try {
      var managerSnap = await FirebaseFirestore.instance
          .collection('managers')
          .where('uid', isEqualTo: _uid)
          .get();

      if (managerSnap.docs.isNotEmpty) {
        var doc = managerSnap.docs.first;
        _userData = doc.data();
        String role = _userData!['role'] ?? 'delivery_supervisor';
        String managerDocId = doc.id;

        await _loadStats(role, managerDocId);
      }
      if (mounted) setState(() => _isLoading = false);
    } catch (e) {
      debugPrint("Dashboard Error: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadStats(String role, String managerDocId) async {
    Query ordersQuery = FirebaseFirestore.instance.collection('orders');
    Query repsQuery = FirebaseFirestore.instance.collection('deliveryReps');

    if (role == 'delivery_supervisor') {
      var myReps = await repsQuery.where('supervisorId', isEqualTo: managerDocId).get();
      _totalReps = myReps.size;

      if (myReps.docs.isNotEmpty) {
        List<String> repCodes = myReps.docs.map((d) => d['repCode'] as String).toList();
        ordersQuery = ordersQuery.where('buyer.repCode', whereIn: repCodes);
      } else { return; }
    } else {
      var allReps = await repsQuery.get();
      _totalReps = allReps.size;
    }

    var ordersSnap = await ordersQuery.get();
    _totalOrders = ordersSnap.size;

    double salesSum = 0;
    for (var doc in ordersSnap.docs) {
      var data = doc.data() as Map<String, dynamic>;
      salesSum += (data['total'] ?? 0).toDouble();
    }
    _totalSales = salesSum;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator(color: Colors.blue)));

    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: AppBar(
        title: Text(
          _userData?['role'] == 'delivery_manager' ? "لوحة مدير التوصيل" : "لوحة مشرف التوصيل",
          style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, color: Colors.white, fontSize: 16.sp),
        ),
        backgroundColor: const Color(0xFF2C3E50),
        centerTitle: true,
        elevation: 5,
        iconTheme: IconThemeData(color: Colors.white, size: 22.sp), 
      ),
      drawer: _buildDrawer(),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(18.sp),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("أهلاً بك، ${_userData?['fullname'] ?? ''}",
                  style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold, fontFamily: 'Cairo', color: Color(0xFF2C3E50))),
              SizedBox(height: 3.h),
              Expanded(
                child: GridView.count(
                  crossAxisCount: 1, 
                  childAspectRatio: 2.2,
                  mainAxisSpacing: 20,
                  children: [
                    _buildStatCard("إجمالي الطلبات المستلمة", "$_totalOrders", Icons.inventory_2, Colors.blue),
                    _buildStatCard("إجمالي مبالغ التحصيل", "${_totalSales.toStringAsFixed(0)} ج.م", Icons.payments, Colors.green),
                    _buildStatCard("طاقم المناديب المسجل", "$_totalReps", Icons.groups, Colors.orange),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 20.sp),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: color.withOpacity(0.1), blurRadius: 15, offset: const Offset(0, 6))
        ],
        border: Border(right: BorderSide(color: color, width: 8)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 35.sp),
          SizedBox(width: 15.sp),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(fontSize: 13.sp, color: Colors.grey[700], fontFamily: 'Cairo', fontWeight: FontWeight.w600)),
              Text(value, style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold, color: Colors.black87, fontFamily: 'Cairo')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      width: 75.w,
      child: Column(
        children: [
          UserAccountsDrawerHeader(
            decoration: const BoxDecoration(color: Color(0xFF2C3E50)),
            accountName: Text(_userData?['fullname'] ?? "المدير", 
              style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 14.sp)),
            accountEmail: Text(_userData?['role'] == 'delivery_manager' ? "مدير نظام" : "مشرف ميداني", 
              style: const TextStyle(fontFamily: 'Cairo')),
            currentAccountPicture: CircleAvatar(
              backgroundColor: Colors.white,
              child: Icon(Icons.admin_panel_settings, size: 35.sp, color: const Color(0xFF2C3E50)),
            ),
          ),
          
          _drawerItem(Icons.account_circle, "حسابي الشخصي", Colors.blue, () {
            Navigator.pop(context);
            Navigator.push(context, MaterialPageRoute(builder: (context) => ProfileScreen(repData: _userData)));
          }),

          _drawerItem(Icons.analytics_rounded, "تقارير العمليات", Colors.teal, () {
            Navigator.pop(context);
            Navigator.push(context, MaterialPageRoute(builder: (context) => const DeliveryManagementScreen()));
          }),

          _drawerItem(Icons.delivery_dining, "إدارة المناديب", Colors.orange, () {
            Navigator.pop(context);
            Navigator.push(context, MaterialPageRoute(builder: (context) => const DeliveryFleetScreen()));
          }),

          if (_userData?['role'] == 'delivery_manager')
            _drawerItem(Icons.map_rounded, "نطاقات التوزيع", Colors.purple, () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (context) => const ManagerGeoDistScreen()));
            }),

          const Spacer(),
          const Divider(),
          
          _drawerItem(Icons.logout_rounded, "تسجيل الخروج", Colors.redAccent, () {
            _showLogoutDialog();
          }),
          SizedBox(height: 3.h),
        ],
      ),
    );
  }

  Widget _drawerItem(IconData icon, String title, Color color, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: color, size: 22.sp),
      title: Text(title, style: TextStyle(fontSize: 14.sp, fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
      onTap: onTap,
    );
  }

  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("تأكيد الخروج", textAlign: TextAlign.right, style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
        content: const Text("هل تريد إغلاق لوحة التحكم؟", textAlign: TextAlign.right, style: TextStyle(fontFamily: 'Cairo')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("إلغاء", style: TextStyle(fontFamily: 'Cairo'))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              if (mounted) Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
            },
            child: const Text("خروج", style: TextStyle(color: Colors.white, fontFamily: 'Cairo')),
          ),
        ],
      ),
    );
  }
}

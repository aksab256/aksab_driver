import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:sizer/sizer.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart'; // تأكد من إضافة هذا المكتبة في pubspec.yaml

// استدعاء الصفحات التابعة
import 'delivery_management_screen.dart';
import 'delivery_fleet_screen.dart';
import 'manager_geo_dist_screen.dart';
import 'ProfileScreen.dart';
import 'field_monitor_screen.dart';

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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 800), () {
        _requestNotificationPermissionWithDisclosure();
      });
    });
  }

  // --- الدوال التقنية (AWS & Permissions) ---

  Future<void> _syncNotificationWithAWS(String role) async {
    try {
      String? token = await FirebaseMessaging.instance.getToken();
      if (token != null && _uid != null) {
        const String apiUrl = "https://5uex7vzy64.execute-api.us-east-1.amazonaws.com/V2/new_nofiction";
        await http.post(
          Uri.parse(apiUrl),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode({
            "userId": _uid,
            "fcmToken": token,
            "role": role
          }),
        );
      }
    } catch (e) {
      debugPrint("❌ AWS Sync Error: $e");
    }
  }

  Future<void> _requestNotificationPermissionWithDisclosure() async {
    FirebaseMessaging messaging = FirebaseMessaging.instance;
    NotificationSettings settings = await messaging.getNotificationSettings();

    if (settings.authorizationStatus != AuthorizationStatus.authorized) {
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
            "بصفتك مسؤولاً في النظام، يحتاج التطبيق لتفعيل الإشعارات لتزويدك بتنبيهات فورية عن العمليات الحرجة، تقارير الأداء، وتحديثات طاقم المناديب لضمان سير العمل بدقة.",
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
        NotificationSettings newSettings = await messaging.requestPermission(
          alert: true, badge: true, sound: true,
        );
        if (newSettings.authorizationStatus == AuthorizationStatus.authorized) {
          String role = _userData?['role'] ?? 'delivery_manager';
          await _syncNotificationWithAWS(role);
        }
      }
    }
  }

  // --- جلب البيانات ---

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
      } else {
        return;
      }
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

  // --- الواجهة الرسومية الرئيسية ---

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator(color: Colors.blue)));

    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: AppBar(
        title: Text(_userData?['role'] == 'delivery_manager' ? "لوحة مدير التوصيل" : "لوحة مشرف التوصيل",
            style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, color: Colors.white, fontSize: 16.sp)),
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
                  style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold, fontFamily: 'Cairo', color: const Color(0xFF2C3E50))),
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
        boxShadow: [BoxShadow(color: color.withOpacity(0.1), blurRadius: 15, offset: const Offset(0, 6))],
        border: Border(right: BorderSide(color: color, width: 8)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 35.sp),
          SizedBox(width: 15.sp),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontSize: 13.sp, color: Colors.grey[700], fontFamily: 'Cairo', fontWeight: FontWeight.w600)),
                Text(value, style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold, color: Colors.black87, fontFamily: 'Cairo')),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- الـ Drawer مع التعديلات المطلوبة (نسخة طبق الأصل) ---

  Widget _buildDrawer() {
    return Drawer(
      width: 75.w,
      child: SafeArea( // ✅ حماية الشريط الجانبي من الحواف العلوية والسفلية (Safe Area)
        child: Column(
          children: [
            UserAccountsDrawerHeader(
              decoration: const BoxDecoration(color: Color(0xFF2C3E50)),
              margin: EdgeInsets.zero, // لضمان التصاق الهيدر بالأعلى داخل الـ SafeArea
              accountName: Text(_userData?['fullname'] ?? "المدير", style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 14.sp)),
              accountEmail: Text(_userData?['role'] == 'delivery_manager' ? "مدير نظام" : "مشرف ميداني", style: const TextStyle(fontFamily: 'Cairo')),
              currentAccountPicture: CircleAvatar(backgroundColor: Colors.white, child: Icon(Icons.admin_panel_settings, size: 35.sp, color: const Color(0xFF2C3E50))),
            ),
            
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  _drawerItem(Icons.account_circle, "حسابي الشخصي", Colors.blue, () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(builder: (context) => ProfileScreen(repData: _userData)));
                  }),

                  StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('specialRequests')
                        .where('status', isEqualTo: 'returning_to_seller')
                        .snapshots(),
                    builder: (context, snapshot) {
                      int returnCount = snapshot.hasData ? snapshot.data!.docs.length : 0;
                      return _drawerItem(
                        Icons.radar_rounded, 
                        "تتبع التوصيل الحر", 
                        Colors.redAccent, 
                        () {
                          Navigator.pop(context);
                          Navigator.push(context, MaterialPageRoute(builder: (context) => const FieldMonitorScreen()));
                        },
                        trailing: returnCount > 0 
                          ? Container(
                              padding: const EdgeInsets.all(6),
                              decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                              child: Text("$returnCount", style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                            )
                          : null,
                      );
                    }
                  ),

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

                  // ✅ إضافة أيقونة شروط الاستخدام والخصوصية
                  _drawerItem(Icons.policy_rounded, "شروط الاستخدام والخصوصية", Colors.blueGrey, () async {
                    final Uri url = Uri.parse('https://aksab.shop');
                    if (await canLaunchUrl(url)) {
                      await launchUrl(url, mode: LaunchMode.externalApplication);
                    }
                  }),
                ],
              ),
            ),
            
            const Divider(),
            
            // ✅ إضافة زر تسجيل الخروج في أسفل الشريط (مساحة آمنة)
            _drawerItem(
              Icons.logout_rounded, 
              "تسجيل الخروج", 
              Colors.redAccent, 
              () => _showLogoutDialog()
            ),
            SizedBox(height: 2.h), // مسافة بسيطة لضمان عدم ملامسة الحافة السفلية تماماً
          ],
        ),
      ),
    );
  }

  Widget _drawerItem(IconData icon, String title, Color color, VoidCallback onTap, {Widget? trailing}) {
    return ListTile(
      leading: Icon(icon, color: color, size: 22.sp),
      title: Text(title, style: TextStyle(fontSize: 14.sp, fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
      trailing: trailing,
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

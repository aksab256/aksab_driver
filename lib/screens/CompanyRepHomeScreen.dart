import 'package:flutter/material.dart';
import 'package:sizer/sizer.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_messaging/firebase_messaging.dart'; 
import 'package:http/http.dart' as http; // إضافة http للربط مع AWS
import 'dart:convert';

// استيراد الصفحات التابعة
import 'TodayTasksScreen.dart';
import 'RepReportsScreen.dart'; 
import 'ProfileScreen.dart'; 

class CompanyRepHomeScreen extends StatefulWidget {
  const CompanyRepHomeScreen({super.key});

  @override
  State<CompanyRepHomeScreen> createState() => _CompanyRepHomeScreenState();
}

class _CompanyRepHomeScreenState extends State<CompanyRepHomeScreen> {
  final String? _uid = FirebaseAuth.instance.currentUser?.uid;
  Map<String, dynamic>? _repData;
  bool _isLoading = true;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _fetchRepData();
    
    // طلب الإذن بعد استقرار الواجهة لضمان ظهور الـ Dialog بسلاسة
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 1000), () {
        _requestNotificationPermissionWithDisclosure();
      });
    });
  }

  // --- 🔗 دالة مزامنة التوكن مع AWS لضمان استلام المهام ---
  Future<void> _syncNotificationWithAWS() async {
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
            "role": "delivery_rep"
          }),
        );
        debugPrint("✅ Rep AWS Sync Successful");
      }
    } catch (e) {
      debugPrint("❌ Rep AWS Sync Error: $e");
    }
  }

  // --- 🔔 دالة الإفصاح وطلب إذن الإشعارات للمندوب ---
  Future<void> _requestNotificationPermissionWithDisclosure() async {
    FirebaseMessaging messaging = FirebaseMessaging.instance;
    NotificationSettings settings = await messaging.getNotificationSettings();
    
    // يظهر الحوار إذا لم يتم التفعيل مسبقاً
    if (settings.authorizationStatus != AuthorizationStatus.authorized) {
      if (!mounted) return;
      
      bool? proceed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
          title: Column(
            children: [
              Icon(Icons.notifications_active_rounded, size: 45, color: const Color(0xFF2C3E50)),
              const SizedBox(height: 15),
              const Text("تنبيهات المهام اليومية", 
                style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w900, fontSize: 18)),
            ],
          ),
          content: const Text(
            "بصفتك مندوباً في شركة أكسب، يحتاج التطبيق لتفعيل الإشعارات لإرسال تكليفات المهام اليومية، تحديثات عناوين العملاء، والرسائل الإدارية العاجلة لضمان سرعة التوصيل.",
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'Cairo', fontSize: 14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("ليس الآن", style: TextStyle(fontFamily: 'Cairo', color: Colors.grey)),
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
        
        // إذا وافق المندوب، نربط التوكن فوراً بـ AWS
        if (newSettings.authorizationStatus == AuthorizationStatus.authorized) {
          await _syncNotificationWithAWS();
        }
      }
    }
  }

  Future<void> _fetchRepData() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('deliveryReps')
          .doc(_uid)
          .get();

      if (snapshot.exists) {
        final data = snapshot.data()!;
        if (mounted) {
          setState(() {
            _repData = data;
            _isLoading = false;
          });
        }
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('userData', jsonEncode(data));
        await prefs.setString('userRole', 'delivery_rep');
      }
    } catch (e) {
      debugPrint("Error fetching rep data: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleLogout() async {
    // يفضل مسح التوكن من AWS عند الخروج (اختياري ولكن أفضل للأمان)
    await FirebaseAuth.instance.signOut();
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (mounted) Navigator.pushReplacementNamed(context, '/login');
  }

  Future<void> _launchPrivacyPolicy() async {
    final Uri url = Uri.parse('https://aksab.shop/'); 
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      debugPrint("Could not launch $url");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFFF0F2F5),
      drawer: _buildSideDrawer(),
      appBar: AppBar(
        title: Text("لوحة التحكم",
            style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold, color: Colors.white, fontFamily: 'Cairo')),
        centerTitle: true,
        backgroundColor: const Color(0xFF2C3E50),
        elevation: 4,
        leading: IconButton(
          icon: Icon(Icons.menu_open_rounded, size: 26.sp, color: Colors.white),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: Colors.blue))
            : SingleChildScrollView(
                padding: EdgeInsets.symmetric(horizontal: 5.w, vertical: 2.h),
                child: Column(
                  children: [
                    _buildUserInfoCard(),
                    SizedBox(height: 2.5.h),
                    _buildStatsSection(),
                    SizedBox(height: 4.h),
                    _buildQuickActions(),
                    SizedBox(height: MediaQuery.of(context).padding.bottom + 5.h),
                  ],
                ),
              ),
      ),
    );
  }

  // ... (باقي الـ Widgets: _buildSideDrawer, _buildUserInfoCard, إلخ كما هي في كودك) ...
  // تأكد من بقاء باقي الـ Widgets التي لم نعدل عليها ليعمل الكود بالكامل
  
  Widget _buildSideDrawer() {
    return Drawer(
      width: 80.w,
      child: SafeArea( 
        top: false, 
        child: Column(
          children: [
            UserAccountsDrawerHeader(
              decoration: const BoxDecoration(color: Color(0xFF2C3E50)),
              accountName: Text(_repData?['fullname'] ?? "المندوب", 
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16.sp, fontFamily: 'Cairo')),
              accountEmail: Text(_repData?['repCode'] ?? "REP-XXXX", 
                style: TextStyle(fontSize: 12.sp, color: Colors.white70, fontFamily: 'Cairo')),
              currentAccountPicture: CircleAvatar(
                backgroundColor: Colors.white,
                child: Icon(Icons.person, size: 38.sp, color: const Color(0xFF2C3E50)),
              ),
            ),
            ListTile(
              leading: Icon(Icons.account_circle, color: Colors.blue, size: 22.sp),
              title: Text("حسابي الشخصي", style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600, fontFamily: 'Cairo')),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (context) => ProfileScreen(repData: _repData)));
              },
            ),
            ListTile(
              leading: Icon(Icons.security, color: Colors.green, size: 22.sp),
              title: Text("سياسة الخصوصية", style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600, fontFamily: 'Cairo')),
              onTap: () {
                Navigator.pop(context);
                _launchPrivacyPolicy();
              },
            ),
            const Spacer(),
            const Divider(),
            ListTile(
              leading: Icon(Icons.logout_rounded, color: Colors.red, size: 22.sp),
              title: Text("تسجيل الخروج", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 14.sp, fontFamily: 'Cairo')),
              onTap: _handleLogout,
            ),
            SizedBox(height: 2.h),
          ],
        ),
      ),
    );
  }

  Widget _buildUserInfoCard() {
    return Container(
      padding: EdgeInsets.all(16.sp),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: const Border(right: BorderSide(color: Color(0xFF3498DB), width: 8)),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 4))],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28.sp,
            backgroundColor: const Color(0xFF3498DB).withOpacity(0.1),
            child: Icon(Icons.delivery_dining_rounded, size: 30.sp, color: const Color(0xFF2C3E50)),
          ),
          SizedBox(width: 14.sp),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("${_repData?['fullname'] ?? 'المندوب'}",
                    style: TextStyle(fontSize: 17.sp, fontWeight: FontWeight.bold, color: const Color(0xFF2C3E50), fontFamily: 'Cairo')),
                Text("كود الموظف: ${_repData?['repCode'] ?? 'REP-XXXX'}",
                    style: TextStyle(fontSize: 12.sp, color: Colors.blueGrey, fontWeight: FontWeight.w600, fontFamily: 'Cairo')),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsSection() {
    return Container(
      width: 100.w,
      padding: EdgeInsets.all(18.sp),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 15)],
      ),
      child: Column(
        children: [
          Text("ملخص الإنتاجية",
              style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold, color: Colors.blue[900], fontFamily: 'Cairo')),
          const Divider(height: 30, thickness: 1),
          _buildDetailRow(Icons.phone_android, "الهاتف:", _repData?['phone'] ?? "-"),
          SizedBox(height: 1.h),
          _buildDetailRow(Icons.verified, "الطلبات المسلمة:", "${_repData?['successfulDeliveries'] ?? 0}"),
        ],
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4.sp),
      child: Row(
        children: [
          Icon(icon, size: 16.sp, color: const Color(0xFF3498DB)),
          SizedBox(width: 12.sp),
          Text(label, style: TextStyle(fontSize: 13.5.sp, color: Colors.grey[700], fontFamily: 'Cairo')),
          const Spacer(),
          Text(value, style: TextStyle(fontSize: 13.5.sp, fontWeight: FontWeight.bold, color: Colors.black87, fontFamily: 'Cairo')),
        ],
      ),
    );
  }

  Widget _buildQuickActions() {
    return Column(
      children: [
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF27AE60),
            minimumSize: Size(100.w, 8.5.h),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            elevation: 6,
          ),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => TodayTasksScreen(repCode: _repData?['repCode'] ?? '')),
            );
          },
          icon: Icon(Icons.list_alt_rounded, color: Colors.white, size: 24.sp),
          label: Text("مـهام الـيوم",
              style: TextStyle(fontSize: 16.sp, color: Colors.white, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
        ),
        SizedBox(height: 2.5.h),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            minimumSize: Size(100.w, 8.h),
            side: const BorderSide(color: Color(0xFF2C3E50), width: 2.5),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          ),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => RepReportsScreen(repCode: _repData?['repCode'] ?? '')),
            );
          },
          icon: Icon(Icons.insights_rounded, size: 22.sp, color: const Color(0xFF2C3E50)),
          label: Text("التقارير والتحصيل",
              style: TextStyle(fontSize: 15.sp, color: const Color(0xFF2C3E50), fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
        ),
      ],
    );
  }
}

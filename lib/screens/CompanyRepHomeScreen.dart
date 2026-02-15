import 'package:flutter/material.dart';
import 'package:sizer/sizer.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
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
    await FirebaseAuth.instance.signOut();
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (mounted) Navigator.pushReplacementNamed(context, '/login');
  }

  Future<void> _launchPrivacyPolicy() async {
    final Uri url = Uri.parse('https://aksab-app.com/privacy-policy'); 
    if (!await launchUrl(url)) {
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
            style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold, color: Colors.white)),
        centerTitle: true,
        backgroundColor: const Color(0xFF2C3E50),
        elevation: 4,
        leading: IconButton(
          icon: Icon(Icons.menu_open_rounded, size: 26.sp, color: Colors.white),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
      ),
      // استخدام SafeArea هنا لحماية المحتوى بالكامل من التداخل مع الحواف
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
                    // إضافة مساحة أمان سفلية إضافية بعد آخر زرار
                    SizedBox(height: MediaQuery.of(context).padding.bottom + 5.h),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildSideDrawer() {
    return Drawer(
      width: 80.w,
      child: SafeArea( // حماية محتوى Drawer أيضاً
        top: false, // نترك الـ Header يأخذ المساحة العلوية بلونه
        child: Column(
          children: [
            UserAccountsDrawerHeader(
              decoration: const BoxDecoration(color: Color(0xFF2C3E50)),
              accountName: Text(_repData?['fullname'] ?? "المندوب", 
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16.sp)),
              accountEmail: Text(_repData?['repCode'] ?? "REP-XXXX", 
                style: TextStyle(fontSize: 12.sp, color: Colors.white70)),
              currentAccountPicture: CircleAvatar(
                backgroundColor: Colors.white,
                child: Icon(Icons.person, size: 38.sp, color: const Color(0xFF2C3E50)),
              ),
            ),
            ListTile(
              leading: Icon(Icons.account_circle, color: Colors.blue, size: 22.sp),
              title: Text("حسابي الشخصي", style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600)),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (context) => ProfileScreen(repData: _repData)));
              },
            ),
            ListTile(
              leading: Icon(Icons.security, color: Colors.green, size: 22.sp),
              title: Text("سياسة الخصوصية", style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600)),
              onTap: () {
                Navigator.pop(context);
                _launchPrivacyPolicy();
              },
            ),
            const Spacer(),
            const Divider(),
            ListTile(
              leading: Icon(Icons.logout_rounded, color: Colors.red, size: 22.sp),
              title: Text("تسجيل الخروج", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 14.sp)),
              onTap: _handleLogout,
            ),
            // مسافة أمان سفلية داخل الـ Drawer
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
                    style: TextStyle(fontSize: 17.sp, fontWeight: FontWeight.bold, color: const Color(0xFF2C3E50))),
                Text("كود الموظف: ${_repData?['repCode'] ?? 'REP-XXXX'}",
                    style: TextStyle(fontSize: 12.sp, color: Colors.blueGrey, fontWeight: FontWeight.w600)),
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
              style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold, color: Colors.blue[900])),
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
          Text(label, style: TextStyle(fontSize: 13.5.sp, color: Colors.grey[700])),
          const Spacer(),
          Text(value, style: TextStyle(fontSize: 13.5.sp, fontWeight: FontWeight.bold, color: Colors.black87)),
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
              style: TextStyle(fontSize: 16.sp, color: Colors.white, fontWeight: FontWeight.bold)),
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
              style: TextStyle(fontSize: 15.sp, color: const Color(0xFF2C3E50), fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}

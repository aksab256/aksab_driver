import 'package:flutter/material.dart';
import 'package:sizer/sizer.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart'; // ستحتاجها لفتح رابط الخصوصية
import 'dart:convert';

// استيراد الصفحات التابعة
import 'TodayTasksScreen.dart';
import 'RepReportsScreen.dart'; // تأكد من تسمية الملف بهذا الاسم

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

  // دالة لفتح رابط الخصوصية
  Future<void> _launchPrivacyPolicy() async {
    final Uri url = Uri.parse('https://aksab-app.com/privacy-policy'); 
    if (!await launchUrl(url)) {
      debugPrint("Could not launch $url");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey, // مفتاح التحكم في الـ Drawer
      backgroundColor: const Color(0xFFF0F2F5),
      drawer: _buildSideDrawer(), // استدعاء الشريط الجانبي
      appBar: AppBar(
        title: Text("لوحة التحكم",
            style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold, color: Colors.white)),
        centerTitle: true,
        backgroundColor: const Color(0xFF2C3E50),
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.menu_rounded, size: 22.sp, color: Colors.white),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.blue))
          : SafeArea(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(horizontal: 5.w, vertical: 2.h),
                child: Column(
                  children: [
                    _buildUserInfoCard(),
                    SizedBox(height: 3.h),
                    _buildStatsSection(),
                    SizedBox(height: 4.h),
                    _buildQuickActions(),
                  ],
                ),
              ),
            ),
    );
  }

  // --- 🛠️ بناء الشريط الجانبي (Drawer) ---
  Widget _buildSideDrawer() {
    return Drawer(
      width: 80.w,
      child: Column(
        children: [
          UserAccountsDrawerHeader(
            decoration: const BoxDecoration(color: Color(0xFF2C3E50)),
            accountName: Text(_repData?['fullname'] ?? "المندوب", 
              style: const TextStyle(fontWeight: FontWeight.bold)),
            accountEmail: Text(_repData?['repCode'] ?? "REP-XXXX"),
            currentAccountPicture: CircleAvatar(
              backgroundColor: Colors.white,
              child: Icon(Icons.person, size: 35.sp, color: const Color(0xFF2C3E50)),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.account_circle_outlined, color: Colors.blue),
            title: const Text("حسابي الشخصي"),
            subtitle: const Text("تعديل البيانات أو حذف الحساب"),
            onTap: () {
              Navigator.pop(context);
              // سنربط هنا صفحة الملف الشخصي لاحقاً
            },
          ),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined, color: Colors.green),
            title: const Text("سياسة الخصوصية"),
            onTap: () {
              Navigator.pop(context);
              _launchPrivacyPolicy();
            },
          ),
          const Spacer(), // لدفع زر الخروج للأسفل
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout_rounded, color: Colors.red),
            title: const Text("تسجيل الخروج", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
            onTap: _handleLogout,
          ),
          SizedBox(height: 2.h),
        ],
      ),
    );
  }

  Widget _buildUserInfoCard() {
    return Container(
      padding: EdgeInsets.all(18.sp),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: const Border(right: BorderSide(color: Color(0xFF3498DB), width: 6)),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10)],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 25.sp,
            backgroundColor: const Color(0xFF3498DB).withOpacity(0.1),
            child: Icon(Icons.delivery_dining, size: 25.sp, color: const Color(0xFF2C3E50)),
          ),
          SizedBox(width: 12.sp),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("${_repData?['fullname'] ?? 'المندوب'}",
                    style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.bold, color: const Color(0xFF2C3E50))),
                Text("كود الموظف: ${_repData?['repCode'] ?? 'REP-XXXX'}",
                    style: TextStyle(fontSize: 11.sp, color: Colors.grey[600])),
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
        borderRadius: BorderRadius.circular(15),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 15)],
      ),
      child: Column(
        children: [
          Text("ملخص الأداء",
              style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.bold, color: Colors.blue[900])),
          const Divider(height: 25),
          _buildDetailRow(Icons.phone_android, "الهاتف:", _repData?['phone'] ?? "-"),
          _buildDetailRow(Icons.task_alt, "إجمالي التسليمات:", "${_repData?['successfulDeliveries'] ?? 0}"),
        ],
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 6.sp),
      child: Row(
        children: [
          Icon(icon, size: 14.sp, color: const Color(0xFF3498DB)),
          SizedBox(width: 10.sp),
          Text(label, style: TextStyle(fontSize: 12.sp, color: Colors.grey[700])),
          const Spacer(),
          Text(value, style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.bold, color: Colors.black87)),
        ],
      ),
    );
  }

  Widget _buildQuickActions() {
    return Column(
      children: [
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF4CAF50),
            minimumSize: Size(100.w, 8.h),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            elevation: 4,
          ),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => TodayTasksScreen(
                  repCode: _repData?['repCode'] ?? '',
                ),
              ),
            );
          },
          icon: Icon(Icons.playlist_add_check_circle_rounded, color: Colors.white, size: 20.sp),
          label: Text("مهام اليوم",
              style: TextStyle(fontSize: 14.sp, color: Colors.white, fontWeight: FontWeight.bold)),
        ),
        SizedBox(height: 2.h),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            minimumSize: Size(100.w, 7.h),
            side: const BorderSide(color: Color(0xFF2C3E50), width: 1.5),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          ),
          onPressed: () {
            // تفعيل ربط صفحة التقارير المصممة
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => RepReportsScreen(
                  repCode: _repData?['repCode'] ?? '',
                ),
              ),
            );
          },
          icon: Icon(Icons.analytics_outlined, size: 18.sp, color: const Color(0xFF2C3E50)),
          label: Text("عرض التقارير والتحصيل",
              style: TextStyle(fontSize: 13.sp, color: const Color(0xFF2C3E50), fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}

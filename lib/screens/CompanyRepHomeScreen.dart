import 'package:flutter/material.dart';
import 'package:sizer/sizer.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert'; // ضروري لتحويل البيانات لـ JSON
import 'TodayTasksScreen.dart'; // استيراد صفحة المهام

class CompanyRepHomeScreen extends StatefulWidget {
  const CompanyRepHomeScreen({super.key});

  @override
  State<CompanyRepHomeScreen> createState() => _CompanyRepHomeScreenState();
}

class _CompanyRepHomeScreenState extends State<CompanyRepHomeScreen> {
  final String? _uid = FirebaseAuth.instance.currentUser?.uid;
  Map<String, dynamic>? _repData;
  bool _isLoading = true;

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
        setState(() {
          _repData = data;
          _isLoading = false;
        });

        // حفظ البيانات كـ JSON String لمحاكاة localStorage
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('userData', jsonEncode(data));
        await prefs.setString('userRole', 'delivery_rep');
      }
    } catch (e) {
      debugPrint("Error fetching rep data: $e");
      setState(() => _isLoading = false);
    }
  }

  Future<void> _handleLogout() async {
    await FirebaseAuth.instance.signOut();
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (mounted) Navigator.pushReplacementNamed(context, '/login');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: AppBar(
        title: Text("لوحة التحكم", 
          style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold, color: Colors.white)),
        centerTitle: true,
        backgroundColor: const Color(0xFF2C3E50),
        elevation: 10,
        actions: [
          IconButton(
            icon: Icon(Icons.logout, size: 20.sp, color: Colors.white),
            onPressed: _handleLogout,
          )
        ],
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
            radius: 28.sp,
            backgroundColor: const Color(0xFF3498DB).withOpacity(0.1),
            child: Icon(Icons.person, size: 32.sp, color: const Color(0xFF2C3E50)),
          ),
          SizedBox(width: 12.sp),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("${_repData?['fullname'] ?? 'المندوب'}",
                    style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold, color: const Color(0xFF2C3E50))),
                Text("كود: ${_repData?['repCode'] ?? 'REP-XXXX'}",
                    style: TextStyle(fontSize: 13.sp, color: Colors.grey[600], fontWeight: FontWeight.w600)),
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
          Text("ملخص الحساب", 
            style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.bold, color: Colors.blue[900])),
          const Divider(height: 25),
          _buildDetailRow(Icons.email, "البريد:", _repData?['email'] ?? "-"),
          _buildDetailRow(Icons.phone, "الهاتف:", _repData?['phone'] ?? "-"),
          _buildDetailRow(Icons.check_circle, "الطلبات الناجحة:", "${_repData?['successfulDeliveries'] ?? 0}"),
        ],
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 7.sp),
      child: Row(
        children: [
          Icon(icon, size: 15.sp, color: const Color(0xFF3498DB)),
          SizedBox(width: 10.sp),
          Text(label, style: TextStyle(fontSize: 13.sp, color: Colors.grey[700])),
          const Spacer(),
          Text(value, style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.bold, color: Colors.black87)),
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
            elevation: 5,
          ),
          onPressed: () {
            // التنقل لصفحة المهام
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const TodayTasksScreen()),
            );
          },
          icon: Icon(Icons.assignment, color: Colors.white, size: 20.sp),
          label: Text("مهام اليوم", 
            style: TextStyle(fontSize: 15.sp, color: Colors.white, fontWeight: FontWeight.bold)),
        ),
        SizedBox(height: 2.h),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            minimumSize: Size(100.w, 7.h),
            side: const BorderSide(color: Color(0xFF2C3E50), width: 2),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          ),
          onPressed: () {
            // سيتم ربط التقارير لاحقاً
          },
          icon: Icon(Icons.bar_chart, size: 18.sp, color: const Color(0xFF2C3E50)),
          label: Text("عرض التقارير", 
            style: TextStyle(fontSize: 14.sp, color: const Color(0xFF2C3E50), fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}


import 'package:flutter/material.dart';
import 'package:sizer/sizer.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart'; // مكتبة فتح الروابط
import 'dart:convert';

import 'free_driver_home_screen.dart';
import 'CompanyRepHomeScreen.dart';
import 'delivery_admin_dashboard.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;

  // دالة فتح رابط سياسة الخصوصية
  Future<void> _launchPrivacyPolicy() async {
    final Uri url = Uri.parse('https://aksab.shop/');
    try {
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        _showError("تعذر فتح الرابط حالياً");
      }
    } catch (e) {
      debugPrint("Privacy Policy Error: $e");
    }
  }

  Future<void> _sendNotificationDataToAWS(String role) async {
    try {
      String? token = await FirebaseMessaging.instance.getToken();
      String? uid = FirebaseAuth.instance.currentUser?.uid;
      
      if (token != null && uid != null) {
        const String apiUrl = "https://5uex7vzy64.execute-api.us-east-1.amazonaws.com/V2/new_nofiction";
        await http.post(
          Uri.parse(apiUrl),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode({
            "userId": uid, 
            "fcmToken": token, 
            "role": role 
          }),
        );
      }
    } catch (e) {
      debugPrint("❌ AWS Notification Error: $e");
    }
  }

  Future<void> _saveVehicleInfo(String config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_vehicle_config', config);
  }

  Future<void> _handleLogin() async {
    if (_phoneController.text.isEmpty || _passwordController.text.isEmpty) {
      _showError("من فضلك أدخل رقم الهاتف وكلمة المرور");
      return;
    }

    setState(() => _isLoading = true);

    try {
      String smartEmail = "${_phoneController.text.trim()}@aksab.com";
      UserCredential userCredential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: smartEmail,
        password: _passwordController.text,
      );

      String uid = userCredential.user!.uid;

      // 1. فحص مندوب شركة
      var repSnap = await FirebaseFirestore.instance.collection('deliveryReps').doc(uid).get();
      if (repSnap.exists) {
        var userData = repSnap.data()!;
        if (userData['status'] == 'approved') {
          _sendNotificationDataToAWS('delivery_rep');
          if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const CompanyRepHomeScreen()));
          return;
        } else {
          await FirebaseAuth.instance.signOut();
          _showError("❌ حساب المندوب غير مفعل. راجع الإدارة.");
          return;
        }
      }

      // 2. فحص مندوب حر
      var freeSnap = await FirebaseFirestore.instance.collection('freeDrivers').doc(uid).get();
      if (freeSnap.exists) {
        var userData = freeSnap.data()!;
        if (userData['status'] == 'approved') {
          String config = userData['vehicleConfig'] ?? 'motorcycleConfig';
          await _saveVehicleInfo(config);
          _sendNotificationDataToAWS('free_driver');
          if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const FreeDriverHomeScreen()));
          return;
        } else {
          await FirebaseAuth.instance.signOut();
          _showError("❌ حسابك قيد المراجعة أو غير مفعل.");
          return;
        }
      }

      // 3. فحص طاقم الإدارة
      var managerSnap = await FirebaseFirestore.instance.collection('managers').doc(uid).get();
      if (managerSnap.exists) {
        var managerData = managerSnap.data()!;
        String role = managerData['role'] ?? '';
        if (role == 'delivery_manager' || role == 'delivery_supervisor') {
          _sendNotificationDataToAWS(role);
          if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const DeliveryAdminDashboard()));
          return;
        }
      }

      _showError("لم يتم العثور على صلاحيات لهذا الحساب");
      await FirebaseAuth.instance.signOut();

    } on FirebaseAuthException catch (e) {
      _showError("فشل الدخول: تأكد من رقم الهاتف وكلمة المرور");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, textAlign: TextAlign.right, style: TextStyle(fontSize: 14.sp, fontFamily: 'Cairo')),
      backgroundColor: Colors.redAccent,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.orange))
          : SafeArea(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 2.h),
                child: Column(
                  children: [
                    SizedBox(height: 3.h),
                    Container(
                      padding: const EdgeInsets.all(15),
                      decoration: BoxDecoration(
                        color: Colors.orange[50],
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.moped_rounded, size: 50.sp, color: Colors.orange[900]),
                    ),
                    SizedBox(height: 2.h),
                    Text("أكسب مناديب",
                        style: TextStyle(fontSize: 22.sp, fontWeight: FontWeight.w900, color: Colors.black87, fontFamily: 'Cairo')),
                    Text("سجل دخولك لبدء العمل",
                        style: TextStyle(fontSize: 14.sp, color: Colors.grey[600], fontFamily: 'Cairo')),
                    SizedBox(height: 4.h),
                    _buildInput(_phoneController, "رقم الهاتف", Icons.phone, type: TextInputType.phone),
                    _buildInput(_passwordController, "كلمة المرور", Icons.lock, isPass: true),
                    SizedBox(height: 1.h),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black87,
                        minimumSize: Size(100.w, 7.5.h),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                        elevation: 5,
                      ),
                      onPressed: _handleLogin,
                      child: Text("دخول للنظام",
                          style: TextStyle(color: Colors.white, fontSize: 16.sp, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
                    ),
                    SizedBox(height: 2.h),
                    TextButton(
                      onPressed: () => Navigator.pushNamed(context, '/register'),
                      child: Text("ليس لديك حساب؟ سجل الآن",
                          style: TextStyle(color: Colors.orange[900], fontSize: 14.sp, fontWeight: FontWeight.w600, fontFamily: 'Cairo')),
                    ),
                    SizedBox(height: 3.h),
                    // --- رابط سياسة الخصوصية ---
                    GestureDetector(
                      onTap: _launchPrivacyPolicy,
                      child: Text(
                        "سياسة الخصوصية والاستخدام",
                        style: TextStyle(
                          color: Colors.blueGrey,
                          fontSize: 11.sp,
                          decoration: TextDecoration.underline,
                          fontFamily: 'Cairo'
                        ),
                      ),
                    ),
                    SizedBox(height: 2.h),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildInput(TextEditingController controller, String label, IconData icon,
      {bool isPass = false, TextInputType type = TextInputType.text}) {
    return Padding(
      padding: EdgeInsets.only(bottom: 2.5.h),
      child: TextField(
        controller: controller,
        obscureText: isPass ? _obscurePassword : false,
        keyboardType: type,
        textAlign: TextAlign.right,
        style: TextStyle(fontSize: 15.sp),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(fontSize: 14.sp, fontFamily: 'Cairo'),
          contentPadding: EdgeInsets.symmetric(vertical: 2.h, horizontal: 5.w),
          prefixIcon: Icon(icon, color: Colors.orange[800], size: 22.sp),
          suffixIcon: isPass
              ? IconButton(
                  icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility, size: 20.sp),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                )
              : null,
          filled: true,
          fillColor: Colors.grey[100],
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: BorderSide(color: Colors.orange[800]!, width: 2),
          ),
        ),
      ),
    );
  }
}

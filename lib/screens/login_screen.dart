import 'package:flutter/material.dart';
import 'package:sizer/sizer.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
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
  String? _verificationId;

  Future<void> _launchPrivacyPolicy() async {
    final Uri url = Uri.parse('https://aksab.shop/');
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      _showError("تعذر فتح الرابط حالياً");
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
          body: jsonEncode({"userId": uid, "fcmToken": token, "role": role}),
        ).timeout(const Duration(seconds: 8));
      }
    } catch (e) {
      debugPrint("❌ AWS Notification Error: $e");
    }
  }

  Future<void> _saveVehicleInfo(String config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_vehicle_config', config);
  }

  // دالة الدخول الجديدة عبر الـ OTP
  Future<void> _handlePhoneLogin() async {
    if (_phoneController.text.isEmpty) {
      _showError("من فضلك أدخل رقم الهاتف أولاً");
      return;
    }

    setState(() => _isLoading = true);

    try {
      // تنظيف رقم الهاتف وإضافة كود الدولة
      String phone = _phoneController.text.trim();
      if (!phone.startsWith('+')) {
        phone = "+2$phone"; 
      }

      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: phone,
        verificationCompleted: (PhoneAuthCredential credential) async {
          await FirebaseAuth.instance.signInWithCredential(credential);
          _checkUserAccess();
        },
        verificationFailed: (FirebaseAuthException e) {
          setState(() => _isLoading = false);
          _showError("فشل إرسال الكود: ${e.message}");
        },
        codeSent: (String verificationId, int? resendToken) {
          setState(() {
            _isLoading = false;
            _verificationId = verificationId;
          });
          _showOTPDialog();
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          _verificationId = verificationId;
        },
      );
    } catch (e) {
      setState(() => _isLoading = false);
      _showError("حدث خطأ غير متوقع");
    }
  }

  // نافذة إدخال كود التحقق
  void _showOTPDialog() {
    final otpController = TextEditingController();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text("تأكيد الهوية", textAlign: TextAlign.center, style: TextStyle(fontFamily: 'Cairo', fontSize: 16.sp)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("أدخل الكود المرسل لرقمك", textAlign: TextAlign.center, style: TextStyle(fontFamily: 'Cairo', fontSize: 12.sp)),
            SizedBox(height: 2.h),
            TextField(
              controller: otpController,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style: TextStyle(letterSpacing: 5, fontSize: 18.sp, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                hintText: "------",
                filled: true,
                fillColor: Colors.grey[100],
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("إلغاء", style: TextStyle(fontFamily: 'Cairo', color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF5722)),
            onPressed: () async {
              if (otpController.text.length < 6) return;
              try {
                PhoneAuthCredential credential = PhoneAuthProvider.credential(
                  verificationId: _verificationId!,
                  smsCode: otpController.text.trim(),
                );
                await FirebaseAuth.instance.signInWithCredential(credential);
                Navigator.pop(context);
                _checkUserAccess();
              } catch (e) {
                _showError("كود التحقق غير صحيح");
              }
            },
            child: Text("تأكيد", style: TextStyle(fontFamily: 'Cairo', color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // فحص صلاحيات المستخدم (اللوجيك الأصلي بتاعك)
  Future<void> _checkUserAccess() async {
    setState(() => _isLoading = true);
    try {
      String uid = FirebaseAuth.instance.currentUser!.uid;

      // 1. التحقق من مناديب الشركات
      var repSnap = await FirebaseFirestore.instance.collection('deliveryReps').doc(uid).get();
      if (repSnap.exists) {
        var userData = repSnap.data()!;
        if (userData['status'] == 'approved') {
          _sendNotificationDataToAWS('delivery_rep');
          if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const CompanyRepHomeScreen()));
          return;
        } else {
          await FirebaseAuth.instance.signOut();
          _showError("❌ حساب المندوب غير مفعل حالياً.");
          return;
        }
      }

      // 2. التحقق من المناديب الأحرار
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

      // 3. التحقق من المدراء والمشرفين
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

      _showError("عذراً، هذا الحساب لا يملك صلاحيات دخول");
      await FirebaseAuth.instance.signOut();

    } catch (e) {
      _showError("خطأ في جلب بيانات الحساب");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, textAlign: TextAlign.right, style: TextStyle(fontSize: 13.sp, fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFFF5722)))
          : SingleChildScrollView(
              child: SafeArea(
                top: false,
                child: Column(
                  children: [
                    Stack(
                      children: [
                        Container(
                          height: 42.h,
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Color(0xFF1A1A1A), Color(0xFF333333)],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ),
                            borderRadius: BorderRadius.only(bottomLeft: Radius.circular(60), bottomRight: Radius.circular(60)),
                          ),
                        ),
                        Positioned(
                          top: 10.h,
                          left: 0,
                          right: 0,
                          child: Column(
                            children: [
                              _buildHeroLogo(),
                              SizedBox(height: 2.h),
                              Text("أسواق اكسب - كابتن", style: TextStyle(fontSize: 26.sp, fontWeight: FontWeight.bold, color: Colors.white, fontFamily: 'Cairo')),
                              Text("منصة إدارة العهدة واللوجستيات", style: TextStyle(fontSize: 12.sp, color: Colors.white70, fontFamily: 'Cairo')),
                            ],
                          ),
                        ),
                      ],
                    ),
                    Transform.translate(
                      offset: Offset(0, -6.h),
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 6.w),
                        child: Container(
                          padding: EdgeInsets.symmetric(horizontal: 7.w, vertical: 5.h),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(35),
                            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 40, offset: const Offset(0, 15))],
                          ),
                          child: Column(
                            children: [
                              _buildCustomField(_phoneController, "رقم الهاتف", Icons.phone_iphone, type: TextInputType.phone),
                              SizedBox(height: 3.h),
                              _buildCustomField(_passwordController, "كلمة المرور (اختياري)", Icons.lock_open_rounded, isPass: true),
                              SizedBox(height: 5.h),
                              _buildLoginButton(),
                            ],
                          ),
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pushNamed(context, '/register'),
                      child: RichText(
                        text: TextSpan(
                          style: TextStyle(fontFamily: 'Cairo', fontSize: 13.sp, color: Colors.black87),
                          children: [
                            const TextSpan(text: "ليس لديك حساب؟ "),
                            TextSpan(text: "قدم طلب انضمام الآن", style: TextStyle(color: const Color(0xFFFF5722), fontWeight: FontWeight.bold, decoration: TextDecoration.underline)),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(height: 3.h),
                    _buildPrivacyButton(),
                    SizedBox(height: 2.h),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildHeroLogo() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.orange.withOpacity(0.4), blurRadius: 25, spreadRadius: 8)]),
      child: Icon(Icons.delivery_dining_rounded, size: 55.sp, color: const Color(0xFFFF5722)),
    );
  }

  Widget _buildCustomField(TextEditingController controller, String label, IconData icon, {bool isPass = false, TextInputType type = TextInputType.text}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(label, style: TextStyle(fontFamily: 'Cairo', fontSize: 12.sp, color: Colors.grey[800], fontWeight: FontWeight.bold)),
        SizedBox(height: 1.5.h),
        TextField(
          controller: controller,
          obscureText: isPass ? _obscurePassword : false,
          keyboardType: type,
          textAlign: TextAlign.right,
          style: TextStyle(fontSize: 14.sp, fontFamily: 'Cairo', fontWeight: FontWeight.bold),
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.grey[50],
            prefixIcon: Icon(icon, color: const Color(0xFFFF5722), size: 22.sp),
            suffixIcon: isPass
                ? IconButton(icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility, color: Colors.grey, size: 20.sp), onPressed: () => setState(() => _obscurePassword = !_obscurePassword))
                : null,
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: Colors.grey[200]!)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: const BorderSide(color: Color(0xFFFF5722), width: 2)),
          ),
        ),
      ],
    );
  }

  Widget _buildLoginButton() {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF1A1A1A),
        foregroundColor: Colors.white,
        minimumSize: Size(100.w, 8.5.h),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        elevation: 10,
      ),
      onPressed: _handlePhoneLogin, // تم تغيير الوظيفة لتعمل بالـ OTP
      child: Text("دخول للنظام", style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
    );
  }

  Widget _buildPrivacyButton() {
    return InkWell(
      onTap: _launchPrivacyPolicy,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.shield_outlined, size: 14.sp, color: Colors.grey),
          SizedBox(width: 2.w),
          Text("سياسة الخصوصية وشروط الاستخدام", style: TextStyle(color: Colors.grey[600], fontSize: 11.sp, fontFamily: 'Cairo', fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}


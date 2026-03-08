import 'package:flutter/material.dart';
import 'package:sizer/sizer.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart'; 
import 'dart:convert';

// تأكد من صحة مسارات الملفات لديك
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

  Future<void> _launchPrivacyPolicy() async {
    final Uri url = Uri.parse('https://aksab.shop/');
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      _showError("تعذر فتح الرابط حالياً");
    }
  }

  // --- الربط مع AWS للإشعارات ---
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

  Future<void> _handleLogin() async {
    if (_phoneController.text.isEmpty || _passwordController.text.isEmpty) {
      _showError("من فضلك أدخل رقم الهاتف وكلمة المرور");
      return;
    }

    setState(() => _isLoading = true);

    try {
      // الامتداد الجديد لضمان الفصل التام عن تطبيق العملاء
      String smartEmail = "${_phoneController.text.trim()}@aksabship.com";
      
      UserCredential userCredential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: smartEmail,
        password: _passwordController.text,
      );

      String uid = userCredential.user!.uid;

      // 1. فحص مناديب الشركات
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

      // 2. فحص المناديب الأحرار
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

      // 3. فحص المديرين والمشرفين
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

    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found') {
        _showError("رقم الهاتف غير مسجل في نظام المناديب");
      } else if (e.code == 'wrong-password') {
        _showError("كلمة المرور غير صحيحة");
      } else {
        _showError("فشل الدخول: تأكد من بياناتك");
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, textAlign: TextAlign.right, style: TextStyle(fontSize: 13.sp, fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
      backgroundColor: Colors.redAccent,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.orange))
          : Stack(
              children: [
                // خلفية علوية بتدرج لوني
                Container(
                  height: 35.h,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.orange[900]!, Colors.orange[700]!],
                      begin: Alignment.topRight,
                      end: Alignment.bottomLeft,
                    ),
                    borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(100)),
                  ),
                ),
                SafeArea(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.symmetric(horizontal: 8.w),
                    child: Column(
                      children: [
                        SizedBox(height: 6.h),
                        // شعار التطبيق فلاتي
                        _buildHeroIcon(),
                        SizedBox(height: 3.h),
                        Text("أكسب مناديب",
                            style: TextStyle(fontSize: 24.sp, fontWeight: FontWeight.w900, color: Colors.white, fontFamily: 'Cairo')),
                        Text("مرحباً بك مجدداً في فريقنا",
                            style: TextStyle(fontSize: 12.sp, color: Colors.white70, fontFamily: 'Cairo')),
                        SizedBox(height: 5.h),
                        
                        // كارت تسجيل الدخول
                        _buildLoginCard(),
                        
                        SizedBox(height: 2.h),
                        TextButton(
                          onPressed: () => Navigator.pushNamed(context, '/register'),
                          child: RichText(
                            text: TextSpan(
                              style: TextStyle(fontFamily: 'Cairo', fontSize: 13.sp, color: Colors.grey[800]),
                              children: [
                                const TextSpan(text: "ليس لديك حساب؟ "),
                                TextSpan(text: "سجل الآن", style: TextStyle(color: Colors.orange[900], fontWeight: FontWeight.bold)),
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
              ],
            ),
    );
  }

  Widget _buildHeroIcon() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 20)],
      ),
      child: Icon(Icons.delivery_dining_rounded, size: 55.sp, color: Colors.orange[900]),
    );
  }

  Widget _buildLoginCard() {
    return Container(
      padding: EdgeInsets.all(6.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 15, offset: const Offset(0, 5))],
      ),
      child: Column(
        children: [
          _buildInputField(_phoneController, "رقم الهاتف", Icons.phone_android, type: TextInputType.phone),
          SizedBox(height: 1.h),
          _buildInputField(_passwordController, "كلمة المرور", Icons.lock_outline, isPass: true),
          SizedBox(height: 3.h),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.black87,
              minimumSize: Size(100.w, 7.5.h),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              elevation: 5,
            ),
            onPressed: _handleLogin,
            child: Text("دخول للنظام",
                style: TextStyle(color: Colors.white, fontSize: 15.sp, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
          ),
        ],
      ),
    );
  }

  Widget _buildInputField(TextEditingController controller, String label, IconData icon,
      {bool isPass = false, TextInputType type = TextInputType.text}) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 1.2.h),
      child: TextField(
        controller: controller,
        obscureText: isPass ? _obscurePassword : false,
        keyboardType: type,
        textAlign: TextAlign.right,
        style: TextStyle(fontSize: 14.sp, fontFamily: 'Cairo', fontWeight: FontWeight.w500),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(fontSize: 12.sp, fontFamily: 'Cairo', color: Colors.grey[600]),
          prefixIcon: Icon(icon, color: Colors.orange[900], size: 20.sp),
          suffixIcon: isPass
              ? IconButton(
                  icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility, size: 18.sp, color: Colors.grey),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                )
              : null,
          filled: true,
          fillColor: Colors.grey[50],
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: Colors.grey[200]!)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: Colors.orange[800]!, width: 1.5)),
        ),
      ),
    );
  }

  Widget _buildPrivacyButton() {
    return GestureDetector(
      onTap: _launchPrivacyPolicy,
      child: Text(
        "سياسة الخصوصية والاستخدام",
        style: TextStyle(
          color: Colors.blueGrey[400],
          fontSize: 11.sp,
          decoration: TextDecoration.underline,
          fontFamily: 'Cairo',
        ),
      ),
    );
  }
}

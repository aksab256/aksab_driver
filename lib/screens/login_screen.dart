import 'package:flutter/material.dart';
import 'package:sizer/sizer.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'free_driver_home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true; // للتحكم في رؤية كلمة المرور

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
      // فكرة الإيميل الذكي عبقرية لتجنب الـ OTP حالياً
      String smartEmail = "${_phoneController.text.trim()}@aksab.com";

      UserCredential userCredential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: smartEmail,
        password: _passwordController.text,
      );

      String uid = userCredential.user!.uid;
      Map<String, dynamic>? userData;

      // البحث في المجموعات المختلفة
      var repSnap = await FirebaseFirestore.instance.collection('deliveryReps').doc(uid).get();
      var freeSnap = await FirebaseFirestore.instance.collection('freeDrivers').doc(uid).get();
      var managerSnap = await FirebaseFirestore.instance.collection('managers').doc(uid).get();

      if (repSnap.exists) {
        userData = repSnap.data();
      } else if (freeSnap.exists) {
        userData = freeSnap.data();
      } else if (managerSnap.exists) {
        userData = managerSnap.data();
      }

      if (userData != null && userData['status'] == 'approved') {
        if (userData['role'] == 'free_driver') {
          String config = userData['vehicleConfig'] ?? 'motorcycleConfig';
          await _saveVehicleInfo(config);
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const FreeDriverHomeScreen()),
          );
        } else {
          _navigateToHome(userData['role'] ?? 'user');
        }
      } else {
        await FirebaseAuth.instance.signOut();
        _showError("❌ حسابك قيد المراجعة أو غير مفعل.");
      }
    } on FirebaseAuthException catch (e) {
      _showError("فشل الدخول: تأكد من رقم الهاتف وكلمة المرور");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _navigateToHome(String role) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("مرحباً بك.. دورك: $role")));
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, textAlign: TextAlign.right, style: TextStyle(fontFamily: 'Cairo')),
      backgroundColor: Colors.redAccent,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.orange))
          : SingleChildScrollView(
              padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 10.h),
              child: Column(
                children: [
                  // أيقونة تعبر عن التطبيق بدلاً من القفل
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.orange[50],
                      shape: BoxType.circle,
                    ),
                    child: Icon(Icons.moped_rounded, size: 70.sp, color: Colors.orange[900]),
                  ),
                  SizedBox(height: 3.h),
                  Text("أكسب مناديب", 
                    style: TextStyle(fontSize: 22.sp, fontWeight: FontWeight.w900, color: Colors.black87)),
                  Text("سجل دخولك لبدء استقبال الطلبات", 
                    style: TextStyle(fontSize: 10.sp, color: Colors.grey[600])),
                  SizedBox(height: 5.h),
                  
                  _buildInput(_phoneController, "رقم الهاتف", Icons.phone, type: TextInputType.phone),
                  _buildInput(_passwordController, "كلمة المرور", Icons.lock, isPass: true),
                  
                  SizedBox(height: 2.h),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black87, // خليناه أسود عشان يتماشى مع هوية "البريميوم"
                      minimumSize: Size(100.w, 7.h),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                      elevation: 5,
                    ),
                    onPressed: _handleLogin,
                    child: Text("دخول للنظام", style: TextStyle(color: Colors.white, fontSize: 13.sp, fontWeight: FontWeight.bold)),
                  ),
                  
                  SizedBox(height: 2.h),
                  TextButton(
                    onPressed: () => Navigator.pushNamed(context, '/register'),
                    child: Text("ليس لديك حساب؟ انضم لعائلة أكسب الآن", 
                      style: TextStyle(color: Colors.orange[900], fontWeight: FontWeight.w600)),
                  )
                ],
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
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, color: Colors.orange[800]),
          suffixIcon: isPass 
            ? IconButton(
                icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility, color: Colors.grey),
                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
              ) 
            : null,
          filled: true,
          fillColor: Colors.grey[100],
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: BorderSide(color: Colors.orange[800]!, width: 1.5),
          ),
        ),
      ),
    );
  }
}


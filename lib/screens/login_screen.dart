import 'package:flutter/material.dart';
import 'package:sizer/sizer.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart'; // 💡 مكتبة التخزين المحلي

import 'free_driver_home_screen.dart';

class LoginScreen extends StatefulWidget {
  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;

  // 🎯 دالة حفظ نوع المركبة محلياً
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
      Map<String, dynamic>? userData;

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
        
        // 🎯 جلب وتخزين نوع المركبة للمندوب الحر
        if (userData['role'] == 'free_driver') {
          String config = userData['vehicleConfig'] ?? 'motorcycleConfig';
          await _saveVehicleInfo(config); // حفظها تحت مفتاح user_vehicle_config
          
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
      setState(() => _isLoading = false);
    }
  }

  // ... باقي الدوال المساعدة (buildInput, showMsg, navigateToHome) تبقى كما هي
  void _navigateToHome(String role) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("مرحباً بك.. دورك: $role")));
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg, textAlign: TextAlign.right)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: _isLoading 
        ? Center(child: CircularProgressIndicator(color: Colors.orange))
        : SingleChildScrollView(
            padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 12.h),
            child: Column(
              children: [
                Icon(Icons.lock_outline, size: 60.sp, color: Colors.orange[800]),
                SizedBox(height: 4.h),
                Text("تسجيل الدخول", style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.bold)),
                SizedBox(height: 5.h),
                _buildInput(_phoneController, "رقم الهاتف", Icons.phone, type: TextInputType.phone), 
                _buildInput(_passwordController, "كلمة المرور", Icons.lock, isPass: true),
                SizedBox(height: 4.h),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange[800],
                    minimumSize: Size(100.w, 7.h),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _handleLogin,
                  child: Text("دخول", style: TextStyle(color: Colors.white, fontSize: 14.sp)),
                ),
                TextButton(
                  onPressed: () => Navigator.pushNamed(context, '/register'),
                  child: Text("ليس لديك حساب؟ سجل الآن", style: TextStyle(color: Colors.orange[900])),
                )
              ],
            ),
          ),
    );
  }

  Widget _buildInput(TextEditingController controller, String label, IconData icon, 
      {bool isPass = false, TextInputType type = TextInputType.text}) {
    return Padding(
      padding: EdgeInsets.only(bottom: 3.h),
      child: TextField(
        controller: controller,
        obscureText: isPass,
        keyboardType: type,
        textAlign: TextAlign.right,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, color: Colors.orange[800]),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
}

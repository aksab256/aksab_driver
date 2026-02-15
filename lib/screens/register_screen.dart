import 'package:flutter/material.dart';
import 'package:sizer/sizer.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart'; 

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  _RegisterScreenState createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  String _selectedRole = 'free_driver';
  String _vehicleConfig = 'motorcycleConfig';
  bool _isLoading = false;
  bool _obscurePassword = true;

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  Future<void> _launchPrivacyPolicy() async {
    final Uri url = Uri.parse('https://aksab.shop/');
    try {
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        _showMsg("تعذر فتح الرابط حالياً");
      }
    } catch (e) {
      debugPrint("Privacy Policy Error: $e");
    }
  }

  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      String smartEmail = "${_phoneController.text.trim()}@aksab.com";
      UserCredential userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: smartEmail,
        password: _passwordController.text,
      );

      String collectionName;
      if (_selectedRole == 'free_driver') {
        collectionName = 'pendingFreeDrivers';
      } else if (_selectedRole == 'delivery_rep') {
        collectionName = 'pendingReps';
      } else {
        collectionName = 'pendingManagers';
      }

      await FirebaseFirestore.instance.collection(collectionName).doc(userCredential.user!.uid).set({
        'fullname': _nameController.text.trim(),
        'email': smartEmail,
        'phone': _phoneController.text.trim(),
        'address': _addressController.text.trim(),
        'role': _selectedRole,
        'vehicleConfig': _selectedRole == 'free_driver' ? _vehicleConfig : 'none',
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
        'uid': userCredential.user!.uid,
      });

      _showSuccessDialog();
    } on FirebaseAuthException catch (e) {
      _showMsg("خطأ: ${e.message}");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: const BackButton(color: Colors.black),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.orange))
          : SafeArea(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(horizontal: 7.w, vertical: 2.h),
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      Text(
                        "انضم لعائلة أكسب",
                        style: TextStyle(
                          fontSize: 24.sp,
                          color: Colors.orange[900],
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Cairo'
                        ),
                      ),
                      SizedBox(height: 1.h),
                      Text(
                        "سجل بياناتك وسيتم مراجعتها خلال 24 ساعة",
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13.sp, color: Colors.grey[600], fontFamily: 'Cairo'),
                      ),
                      SizedBox(height: 4.h),
                      _buildInput(_nameController, "الاسم الكامل كما في البطاقة", Icons.person),
                      _buildInput(_phoneController, "رقم الهاتف", Icons.phone, type: TextInputType.phone),
                      _buildInput(_addressController, "محل الإقامة الحالي", Icons.map),
                      _buildInput(_passwordController, "كلمة مرور قوية", Icons.lock, isPass: true),
                      const Divider(height: 40, thickness: 1.2),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          "نوع الانضمام:",
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16.sp, color: Colors.black87, fontFamily: 'Cairo'),
                        ),
                      ),
                      SizedBox(height: 1.h),
                      
                      _roleOption("مندوب توصيل حر (امتلك مركبة)", "free_driver"),
                      if (_selectedRole == 'free_driver') _buildVehiclePicker(),
                      _roleOption("مندوب تحصيل (موظف بشركة)", "delivery_rep"),
                      _roleOption("مشرف تحصيل (إشراف ميداني)", "delivery_supervisor"),
                      _roleOption("مدير تحصيل (إدارة النظام)", "delivery_manager"),

                      SizedBox(height: 2.h),

                      // --- رابط سياسة الخصوصية المعدل (أكبر وأوضح) ---
                      GestureDetector(
                        onTap: _launchPrivacyPolicy,
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 12.sp), // زيادة مساحة الضغط
                          child: Text(
                            "بتسجيلك أنت توافق على سياسة الخصوصية",
                            style: TextStyle(
                              fontSize: 13.sp, // تكبير الخط ليكون واضحاً للمراجعين
                              color: Colors.blueGrey[700], // لون أغمق قليلاً
                              decoration: TextDecoration.underline,
                              fontFamily: 'Cairo',
                              fontWeight: FontWeight.w500
                            ),
                          ),
                        ),
                      ),

                      SizedBox(height: 1.h),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black87,
                          minimumSize: Size(100.w, 8.h),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        ),
                        onPressed: _handleRegister,
                        child: Text(
                          "إرسال طلب الانضمام",
                          style: TextStyle(color: Colors.white, fontSize: 16.sp, fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
                        ),
                      ),
                      SizedBox(height: 4.h),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildVehiclePicker() {
    return Container(
      margin: EdgeInsets.symmetric(vertical: 2.h),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.orange[50],
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.orange[100]!, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("اختر نوع مركبتك:", style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.bold, color: Colors.orange[900], fontFamily: 'Cairo')),
          DropdownButtonFormField<String>(
            value: _vehicleConfig,
            isExpanded: true,
            dropdownColor: Colors.orange[50],
            style: TextStyle(fontSize: 14.sp, color: Colors.black, fontWeight: FontWeight.w500, fontFamily: 'Cairo'),
            decoration: const InputDecoration(border: InputBorder.none),
            items: const [
              DropdownMenuItem(value: 'motorcycleConfig', child: Text("موتوسيكل (Motorcycle)")),
              DropdownMenuItem(value: 'pickupConfig', child: Text("سيارة ربع نقل (Pickup)")),
              DropdownMenuItem(value: 'jumboConfig', child: Text("جامبو / نقل ثقيل (Jumbo)")),
            ],
            onChanged: (val) => setState(() => _vehicleConfig = val!),
          ),
        ],
      ),
    );
  }

  Widget _roleOption(String title, String value) {
    return RadioListTile(
      title: Text(title, style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600, fontFamily: 'Cairo')),
      value: value,
      groupValue: _selectedRole,
      onChanged: (v) => setState(() => _selectedRole = v.toString()),
      activeColor: Colors.orange[900],
      contentPadding: EdgeInsets.zero,
    );
  }

  Widget _buildInput(TextEditingController ctrl, String label, IconData icon, {bool isPass = false, TextInputType type = TextInputType.text}) {
    return Padding(
      padding: EdgeInsets.only(bottom: 2.5.h),
      child: TextFormField(
        controller: ctrl,
        obscureText: isPass ? _obscurePassword : false,
        keyboardType: type,
        textAlign: TextAlign.right,
        style: TextStyle(fontSize: 15.sp, fontFamily: 'Cairo'),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(fontFamily: 'Cairo', fontSize: 13.sp),
          prefixIcon: Icon(icon, color: Colors.orange[900]),
          suffixIcon: isPass ? IconButton(icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility), onPressed: () => setState(() => _obscurePassword = !_obscurePassword)) : null,
          filled: true,
          fillColor: Colors.grey[50],
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
        ),
        validator: (v) => v!.isEmpty ? "هذا الحقل مطلوب" : null,
      ),
    );
  }

  void _showMsg(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m, style: const TextStyle(fontFamily: 'Cairo'))));

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
        title: const Icon(Icons.check_circle, color: Colors.green, size: 70),
        content: Text("تم استلام طلبك بنجاح!\nسيتم مراجعة البيانات وتفعيل الحساب قريباً.", 
          textAlign: TextAlign.center, style: TextStyle(fontFamily: 'Cairo', fontSize: 14.sp)),
        actions: [
          Center(child: ElevatedButton(onPressed: () { Navigator.pop(context); Navigator.pop(context); }, child: const Text("فهمت", style: TextStyle(fontFamily: 'Cairo')))),
        ],
      ),
    );
  }
}

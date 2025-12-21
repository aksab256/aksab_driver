import 'package:flutter/material.dart';
import 'package:sizer/sizer.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class RegisterScreen extends StatefulWidget {
  @override
  _RegisterScreenState createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  String _selectedRole = 'free_driver';
  
  // المفاتيح المعتمدة في النظام القديم
  String _vehicleConfig = 'motorcycleConfig'; 
  
  bool _isLoading = false;

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

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
        // حفظ نوع المركبة بالمفتاح المتوافق مع التطبيق القديم
        'vehicleConfig': _selectedRole == 'free_driver' ? _vehicleConfig : 'none',
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
        'uid': userCredential.user!.uid,
      });

      _showSuccessDialog();
    } on FirebaseAuthException catch (e) {
      _showMsg("خطأ: ${e.message}");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // تحسين حجم خط الراديو
  Widget _roleOption(String title, String value) {
    return RadioListTile(
      title: Text(title, style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w500)),
      value: value,
      groupValue: _selectedRole,
      onChanged: (v) => setState(() => _selectedRole = v.toString()),
      activeColor: Color(0xFF43B97F),
      contentPadding: EdgeInsets.zero,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: Color(0xFF43B97F)))
          : SingleChildScrollView(
              padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 6.h),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    Text("تسجيل حساب جديد", 
                      style: TextStyle(fontSize: 22.sp, color: Color(0xFF43B97F), fontWeight: FontWeight.bold)),
                    SizedBox(height: 3.h),
                    _buildInput(_nameController, "الاسم الكامل", Icons.person),
                    _buildInput(_phoneController, "رقم الهاتف", Icons.phone, type: TextInputType.phone),
                    _buildInput(_addressController, "العنوان بالتفصيل", Icons.map),
                    _buildInput(_passwordController, "كلمة المرور", Icons.lock, isPass: true),
                    
                    const Divider(),
                    
                    Align(
                      alignment: Alignment.centerRight, 
                      child: Text("نوع الحساب:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.sp))
                    ),
                    _roleOption("مندوب توصيل حر", "free_driver"),

                    // 🎯 قسم اختيار نوع المركبة (المفاتيح القديمة)
                    if (_selectedRole == 'free_driver')
                      Container(
                        margin: EdgeInsets.symmetric(vertical: 2.h),
                        padding: EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.grey[50],
                          borderRadius: BorderRadius.circular(15),
                          border: Border.all(color: Colors.grey[200]!),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("نوع المركبة المتاحة معك:", 
                              style: TextStyle(fontSize: 11.sp, fontWeight: FontWeight.bold, color: Colors.black54)),
                            DropdownButtonFormField<String>(
                              value: _vehicleConfig,
                              decoration: const InputDecoration(border: InputBorder.none),
                              items: [
                                DropdownMenuItem(value: 'motorcycleConfig', child: Text("موتوسيكل (Motorcycle)", style: TextStyle(fontSize: 12.sp))),
                                DropdownMenuItem(value: 'pickupConfig', child: Text("سيارة ربع نقل (Pickup)", style: TextStyle(fontSize: 12.sp))),
                                DropdownMenuItem(value: 'jumboConfig', child: Text("جامبو / نقل ثقيل (Jumbo)", style: TextStyle(fontSize: 12.sp))),
                              ],
                              onChanged: (val) => setState(() => _vehicleConfig = val!),
                            ),
                          ],
                        ),
                      ),

                    _roleOption("مندوب تحصيل (موظف)", "delivery_rep"),
                    _roleOption("مشرف تحصيل", "delivery_supervisor"),
                    _roleOption("مدير تحصيل", "delivery_manager"),

                    SizedBox(height: 3.h),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Color(0xFF43B97F),
                        minimumSize: Size(100.w, 8.h),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                      ),
                      onPressed: _handleRegister,
                      child: Text("إنشاء الحساب", style: TextStyle(color: Colors.white, fontSize: 15.sp, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildInput(TextEditingController ctrl, String label, IconData icon, 
      {bool isPass = false, TextInputType type = TextInputType.text}) {
    return Padding(
      padding: EdgeInsets.only(bottom: 2.5.h),
      child: TextFormField(
        controller: ctrl,
        obscureText: isPass,
        keyboardType: type,
        textAlign: TextAlign.right,
        style: TextStyle(fontSize: 13.sp), // زيادة حجم خط الكتابة
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(fontSize: 12.sp), // زيادة حجم خط العنوان
          suffixIcon: Icon(icon, color: Color(0xFF43B97F), size: 18.sp),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
          contentPadding: EdgeInsets.symmetric(vertical: 2.h, horizontal: 4.w),
        ),
        validator: (v) => v!.isEmpty ? "هذا الحقل مطلوب" : null,
      ),
    );
  }

  void _showMsg(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  void _showSuccessDialog() {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text("تم بنجاح", textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text("تم إرسال بياناتك للإدارة بنجاح.\nيرجى الانتظار حتى يتم تفعيل حسابك.", 
          textAlign: TextAlign.center, style: TextStyle(fontSize: 12.sp)),
        actions: [
          Center(
            child: TextButton(
              onPressed: () => Navigator.pop(context), 
              child: Text("حسناً", style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.bold, color: Color(0xFF43B97F)))
            ),
          )
        ],
      ),
    ).then((_) => Navigator.pop(context));
  }
}


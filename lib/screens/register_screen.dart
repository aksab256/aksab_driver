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
  String _selectedRole = 'free_driver'; // القيمة الافتراضية للمندوب الحر
  bool _isLoading = false;

  // المتحكمات (Controllers) لجمع البيانات
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  // دالة التعامل مع التسجيل وحفظ البيانات في مجموعات الانتظار
  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      // 1. إنشاء حساب في Firebase Auth
      UserCredential userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      // 2. تحديد مجموعة الانتظار بناءً على الدور (Role) كما اتفقنا
      String collectionName;
      if (_selectedRole == 'free_driver') {
        collectionName = 'pendingFreeDrivers'; // مجموعة انتظار المندوب الحر
      } else if (_selectedRole == 'delivery_rep') {
        collectionName = 'pendingReps'; // مجموعة انتظار مندوب التحصيل
      } else {
        collectionName = 'pendingManagers'; // مجموعة المشرفين والمديرين
      }

      // 3. حفظ البيانات في Firestore مع حالة "pending"
      await FirebaseFirestore.instance.collection(collectionName).doc(userCredential.user!.uid).set({
        'fullname': _nameController.text.trim(),
        'email': _emailController.text.trim(),
        'phone': _phoneController.text.trim(),
        'address': _addressController.text.trim(),
        'role': _selectedRole,
        'status': 'pending', // الحالة الافتراضية عند التسجيل
        'createdAt': FieldValue.serverTimestamp(),
        'uid': userCredential.user!.uid,
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("✅ تم التسجيل بنجاح، في انتظار موافقة الإدارة.")),
      );
      
      // يمكن هنا توجيهه لصفحة تسجيل الدخول أو شاشة "بانتظار الموافقة"
    } on FirebaseAuthException catch (e) {
      String message = "حدث خطأ في التسجيل";
      if (e.code == 'email-already-in-use') message = "البريد الإلكتروني مستخدم بالفعل";
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("❌ $message")));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text("إنشاء حساب مندوب", style: TextStyle(color: Colors.black)),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      body: _isLoading 
          ? Center(child: CircularProgressIndicator(color: Color(0xFF43B97F)))
          : SingleChildScrollView(
              padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    Icon(Icons.delivery_dining, size: 50.sp, color: Color(0xFF43B97F)),
                    SizedBox(height: 3.h),
                    
                    _buildInput(_nameController, "الاسم الكامل", Icons.person),
                    _buildInput(_emailController, "البريد الإلكتروني", Icons.email, type: TextInputType.emailAddress),
                    _buildInput(_phoneController, "رقم الهاتف", Icons.phone, type: TextInputType.phone),
                    _buildInput(_addressController, "العنوان بالتفصيل", Icons.location_on),
                    _buildInput(_passwordController, "كلمة المرور", Icons.lock, isPass: true),

                    SizedBox(height: 2.h),
                    Align(alignment: Alignment.centerRight, child: Text("نوع الحساب:", style: TextStyle(fontWeight: FontWeight.bold))),
                    
                    _roleRadio("مندوب توصيل حر", "free_driver"),
                    _roleRadio("مندوب تحصيل (موظف)", "delivery_rep"),
                    _roleRadio("مشرف/مدير تحصيل", "delivery_manager"),

                    SizedBox(height: 4.h),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Color(0xFF43B97F),
                        minimumSize: Size(100.w, 7.h),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: _handleRegister,
                      child: Text("تسجيل الحساب", style: TextStyle(color: Colors.white, fontSize: 13.sp)),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildInput(TextEditingController controller, String label, IconData icon, {bool isPass = false, TextInputType type = TextInputType.text}) {
    return Padding(
      padding: EdgeInsets.only(bottom: 2.h),
      child: TextFormField(
        controller: controller,
        obscureText: isPass,
        keyboardType: type,
        textAlign: TextAlign.right,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, color: Color(0xFF43B97F)),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
        validator: (v) => v!.isEmpty ? "هذا الحقل مطلوب" : null,
      ),
    );
  }

  Widget _roleRadio(String title, String value) {
    return RadioListTile(
      title: Text(title, textAlign: TextAlign.right),
      value: value,
      groupValue: _selectedRole,
      activeColor: Color(0xFF43B97F),
      onChanged: (val) => setState(() => _selectedRole = val.toString()),
    );
  }
}

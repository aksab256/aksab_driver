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
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      _showMsg("تعذر فتح الرابط حالياً");
    }
  }

  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      // الامتداد الجديد لضمان عدم التداخل مع تطبيق العملاء
      String smartEmail = "${_phoneController.text.trim()}@aksabship.com";
      
      UserCredential userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: smartEmail,
        password: _passwordController.text,
      );

      String collectionName = _getCollectionName(_selectedRole);

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
      if (e.code == 'email-already-in-use') {
        _showMsg("❌ هذا الرقم مسجل مسبقاً في نظام المناديب");
      } else {
        _showMsg("خطأ: ${e.message}");
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _getCollectionName(String role) {
    switch (role) {
      case 'free_driver': return 'pendingFreeDrivers';
      case 'delivery_rep': return 'pendingReps';
      default: return 'pendingManagers';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.orange))
          : Stack(
              children: [
                // خلفية جمالية علوية
                Container(
                  height: 25.h,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.orange[900]!, Colors.orange[700]!],
                      begin: Alignment.topRight,
                      end: Alignment.bottomLeft,
                    ),
                    borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(80)),
                  ),
                ),
                SafeArea(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.symmetric(horizontal: 6.w),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          SizedBox(height: 3.h),
                          // أيقونة التطبيق (فلاتي)
                          _buildAppLogo(),
                          SizedBox(height: 2.h),
                          _buildHeaderCard(),
                          SizedBox(height: 3.h),
                          _buildInputSection(),
                          SizedBox(height: 3.h),
                          _buildRoleSelection(),
                          if (_selectedRole == 'free_driver') _buildVehiclePicker(),
                          SizedBox(height: 4.h),
                          _buildSubmitButton(),
                          _buildPrivacyLink(),
                          SizedBox(height: 4.h),
                        ],
                      ),
                    ),
                  ),
                ),
                Position Navigator.canPop(context) ? const BackButton(color: Colors.white) : const SizedBox(),
              ],
            ),
    );
  }

  Widget _buildAppLogo() {
    return Center(
      child: Container(
        height: 12.h,
        width: 12.h,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 20, spreadRadius: 5)],
        ),
        child: ClipOval(
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Icon(Icons.moped_rounded, size: 50.sp, color: Colors.orange[900]), // استبدلها بـ Image.asset لو اللوجو جاهز
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderCard() {
    return Column(
      children: [
        Text(
          "انضم لعائلة أكسب",
          style: TextStyle(fontSize: 22.sp, fontWeight: FontWeight.w900, color: Colors.white, fontFamily: 'Cairo'),
        ),
        Text(
          "كن شريكاً في النجاح وابدأ الربح الآن",
          style: TextStyle(fontSize: 12.sp, color: Colors.white.withOpacity(0.9), fontFamily: 'Cairo'),
        ),
      ],
    );
  }

  Widget _buildInputSection() {
    return Container(
      padding: EdgeInsets.all(5.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 15)],
      ),
      child: Column(
        children: [
          _buildField(_nameController, "الاسم بالكامل", Icons.person_outline),
          _buildField(_phoneController, "رقم الهاتف", Icons.phone_android_outlined, type: TextInputType.phone),
          _buildField(_addressController, "العنوان الحالي", Icons.location_on_outlined),
          _buildField(_passwordController, "كلمة المرور", Icons.lock_outline, isPass: true),
        ],
      ),
    );
  }

  Widget _buildRoleSelection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(right: 2.w, bottom: 1.h),
          child: Text("حدد نوع الانضمام", style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
        ),
        _roleCard("مندوب حر (صاحب مركبة)", "free_driver", Icons.delivery_dining),
        _roleCard("مندوب تحصيل (موظف شركة)", "delivery_rep", Icons.business_center_outlined),
        _roleCard("مشرف / مدير نظام", "delivery_manager", Icons.admin_panel_settings_outlined),
      ],
    );
  }

  Widget _roleCard(String title, String value, IconData icon) {
    bool isSelected = _selectedRole == value;
    return GestureDetector(
      onTap: () => setState(() => _selectedRole = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        margin: EdgeInsets.only(bottom: 1.5.h),
        padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 1.8.h),
        decoration: BoxDecoration(
          color: isSelected ? Colors.orange[50] : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? Colors.orange[900]! : Colors.transparent, width: 1.5),
        ),
        child: Row(
          children: [
            Icon(icon, color: isSelected ? Colors.orange[900] : Colors.grey),
            SizedBox(width: 4.w),
            Text(title, style: TextStyle(fontFamily: 'Cairo', fontWeight: isSelected ? FontWeight.bold : FontWeight.normal, fontSize: 13.sp)),
            const Spacer(),
            if (isSelected) Icon(Icons.check_circle, color: Colors.orange[900], size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildVehiclePicker() {
    return Container(
      margin: EdgeInsets.only(top: 1.h),
      padding: EdgeInsets.symmetric(horizontal: 4.w),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
      child: DropdownButtonFormField<String>(
        value: _vehicleConfig,
        style: TextStyle(fontFamily: 'Cairo', color: Colors.black, fontSize: 13.sp),
        decoration: const InputDecoration(labelText: "نوع المركبة", border: InputBorder.none),
        items: const [
          DropdownMenuItem(value: 'motorcycleConfig', child: Text("موتوسيكل")),
          DropdownMenuItem(value: 'pickupConfig', child: Text("ربع نقل")),
          DropdownMenuItem(value: 'jumboConfig', child: Text("جامبو / نقل ثقيل")),
        ],
        onChanged: (val) => setState(() => _vehicleConfig = val!),
      ),
    );
  }

  Widget _buildSubmitButton() {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.black87,
        minimumSize: Size(100.w, 7.5.h),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        elevation: 10,
        shadowColor: Colors.black45,
      ),
      onPressed: _handleRegister,
      child: Text("إرسال الطلب", style: TextStyle(color: Colors.white, fontSize: 16.sp, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
    );
  }

  Widget _buildPrivacyLink() {
    return TextButton(
      onPressed: _launchPrivacyPolicy,
      child: Text(
        "بالتسجيل، أنت توافق على شروط سياسة الخصوصية",
        style: TextStyle(color: Colors.grey[600], fontSize: 11.sp, fontFamily: 'Cairo', decoration: TextDecoration.underline),
      ),
    );
  }

  Widget _buildField(TextEditingController ctrl, String label, IconData icon, {bool isPass = false, TextInputType type = TextInputType.text}) {
    return Padding(
      padding: EdgeInsets.only(bottom: 1.5.h),
      child: TextFormField(
        controller: ctrl,
        obscureText: isPass ? _obscurePassword : false,
        keyboardType: type,
        textAlign: TextAlign.right,
        style: TextStyle(fontSize: 14.sp, fontFamily: 'Cairo'),
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, color: Colors.orange[900], size: 20),
          suffixIcon: isPass ? IconButton(icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility), onPressed: () => setState(() => _obscurePassword = !_obscurePassword)) : null,
          border: UnderlineInputBorder(borderSide: BorderSide(color: Colors.grey[200]!)),
          enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.grey[200]!)),
          focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.orange[900]!)),
        ),
        validator: (v) => v!.isEmpty ? "مطلوب" : null,
      ),
    );
  }

  void _showMsg(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m, textAlign: TextAlign.right, style: const TextStyle(fontFamily: 'Cairo'))));

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.mark_email_read_outlined, color: Colors.green, size: 80),
            SizedBox(height: 2.h),
            Text("طلبك قيد المراجعة", style: TextStyle(fontFamily: 'Cairo', fontSize: 18.sp, fontWeight: FontWeight.bold)),
            SizedBox(height: 1.h),
            Text("شكراً لانضمامك. سيتم مراجعة بياناتك وتفعيل حسابك خلال 24 ساعة.", textAlign: TextAlign.center, style: TextStyle(fontFamily: 'Cairo', fontSize: 12.sp, color: Colors.grey[600])),
            SizedBox(height: 3.h),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange[900], shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
              onPressed: () { Navigator.pop(context); Navigator.pop(context); },
              child: const Text("تم", style: TextStyle(color: Colors.white, fontFamily: 'Cairo')),
            ),
          ],
        ),
      ),
    );
  }
}

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
  
  // متغيرات الحالة
  String? _vehicleConfig; 
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _privacyAccepted = false;

  // المتحكمات (Controllers)
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController(); 
  final TextEditingController _referralController = TextEditingController(); 

  // فتح سياسة الخصوصية
  Future<void> _launchPrivacyPolicy() async {
    final Uri url = Uri.parse('https://aksab.shop/');
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      _showMsg("تعذر فتح الرابط حالياً");
    }
  }

  // دالة التسجيل الرئيسية
  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;
    
    // التأكد من تطابق كلمة المرور
    if (_passwordController.text != _confirmPasswordController.text) {
      _showMsg("❌ كلمات المرور غير متطابقة");
      return;
    }

    // التأكد من الموافقة على الشروط
    if (!_privacyAccepted) {
      _showMsg("يجب الموافقة على سياسة الخصوصية أولاً");
      return;
    }

    setState(() => _isLoading = true);

    try {
      // إنشاء بريد إلكتروني ذكي بناءً على الرقم
      String smartEmail = "${_phoneController.text.trim()}@aksabship.com";

      // 1. إنشاء الحساب في Firebase Authentication
      UserCredential userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: smartEmail,
        password: _passwordController.text,
      );

      // تحديد اسم المجموعة بناءً على الدور
      String collectionName = _getCollectionName(_selectedRole);
      
      // 2. تجهيز مستند البيانات (Document)
      Map<String, dynamic> userData = {
        'fullname': _nameController.text.trim(),
        'email': smartEmail,
        'phone': _phoneController.text.trim(),
        'address': _addressController.text.trim(),
        'role': _selectedRole,
        'status': 'pending', // الحالة الافتراضية للمراجعة
        'createdAt': FieldValue.serverTimestamp(),
        'uid': userCredential.user!.uid,
      };

      // إضافة تفاصيل المندوب الحر ونظام الإحالة
      if (_selectedRole == 'free_driver') {
        userData['vehicleConfig'] = _vehicleConfig;
        
        // نظام الإحالة المزدوج
        userData['referredBy'] = _referralController.text.trim(); // الكود الذي أدخله المندوب (من زميله)
        userData['myReferralCode'] = ""; // سيتم توليده عند التفعيل من لوحة الإدارة
        
        // البيانات اللوجستية والمالية
        userData['walletBalance'] = 0.0;
        userData['insurance_points'] = 0.0;
        userData['totalReferralsCount'] = 0; // عداد الأشخاص الذين سجلوا بكوده لاحقاً
      }

      // 3. حفظ البيانات في Firestore
      await FirebaseFirestore.instance
          .collection(collectionName)
          .doc(userCredential.user!.uid)
          .set(userData);

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
                // خلفية الهيدر المتدرجة
                Container(
                  height: 28.h,
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
                          _buildAppLogo(),
                          SizedBox(height: 2.h),
                          _buildHeaderCard(),
                          SizedBox(height: 4.h),
                          _buildInputSection(),
                          SizedBox(height: 4.h),
                          _buildRoleSelection(),
                          
                          // حقول إضافية للمندوب الحر فقط
                          if (_selectedRole == 'free_driver') ...[
                            SizedBox(height: 2.h),
                            _buildVehiclePicker(),
                            SizedBox(height: 2.h),
                            _buildReferralField(),
                          ],
                          
                          SizedBox(height: 3.h),
                          _buildPrivacyCheckbox(),
                          SizedBox(height: 2.h),
                          _buildSubmitButton(),
                          SizedBox(height: 4.h),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 5.h,
                  right: 2.w,
                  child: Navigator.canPop(context) ? const BackButton(color: Colors.white) : const SizedBox(),
                ),
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
        child: Icon(Icons.delivery_dining_rounded, size: 50.sp, color: Colors.orange[900]),
      ),
    );
  }

  Widget _buildHeaderCard() {
    return Column(
      children: [
        Text("انضم لعائلة أكسب", 
          style: TextStyle(fontSize: 24.sp, fontWeight: FontWeight.w900, color: Colors.white, fontFamily: 'Cairo')),
        Text("سجل بياناتك للبدء في إدارة العهدة", 
          style: TextStyle(fontSize: 13.sp, color: Colors.white.withOpacity(0.9), fontFamily: 'Cairo')),
      ],
    );
  }

  Widget _buildInputSection() {
    return Container(
      padding: EdgeInsets.all(6.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 20)],
      ),
      child: Column(
        children: [
          _buildField(_nameController, "الاسم بالكامل", Icons.person_outline),
          _buildField(_phoneController, "رقم الهاتف للدخول", Icons.phone_android_outlined, type: TextInputType.phone),
          _buildField(_addressController, "العنوان الحالي", Icons.location_on_outlined),
          _buildField(_passwordController, "كلمة المرور", Icons.lock_outline, isPass: true, passType: 1),
          _buildField(_confirmPasswordController, "تأكيد كلمة المرور", Icons.lock_reset_outlined, isPass: true, passType: 2),
        ],
      ),
    );
  }

  Widget _buildRoleSelection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(right: 2.w, bottom: 1.5.h),
          child: Text("نوع الحساب المستهدف", 
            style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold, fontFamily: 'Cairo', color: Colors.orange[900])),
        ),
        _roleCard("مندوب حر (صاحب مركبة)", "free_driver", Icons.moped_rounded),
        _roleCard("مندوب تحصيل (موظف)", "delivery_rep", Icons.badge_outlined),
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
        padding: EdgeInsets.symmetric(horizontal: 5.w, vertical: 2.h),
        decoration: BoxDecoration(
          color: isSelected ? Colors.orange[50] : Colors.white,
          borderRadius: BorderRadius.circular(25),
          border: Border.all(color: isSelected ? Colors.orange[900]! : Colors.grey[200]!, width: 2),
        ),
        child: Row(
          children: [
            Icon(icon, color: isSelected ? Colors.orange[900] : Colors.grey, size: 22.sp),
            SizedBox(width: 4.w),
            Text(title, 
              style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 13.sp)),
            const Spacer(),
            if (isSelected) Icon(Icons.check_circle, color: Colors.orange[900], size: 25),
          ],
        ),
      ),
    );
  }

  Widget _buildVehiclePicker() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 5.w, vertical: 1.h),
      decoration: BoxDecoration(
        color: Colors.white, 
        borderRadius: BorderRadius.circular(25), 
        border: Border.all(color: Colors.grey[300]!, width: 1.5)
      ),
      child: DropdownButtonFormField<String>(
        value: _vehicleConfig,
        hint: Text("اختر نوع المركبة (إجباري)", 
          style: TextStyle(fontFamily: 'Cairo', fontSize: 13.sp, fontWeight: FontWeight.bold)),
        style: TextStyle(fontFamily: 'Cairo', color: Colors.black, fontSize: 14.sp, fontWeight: FontWeight.bold),
        decoration: const InputDecoration(border: InputBorder.none),
        items: const [
          DropdownMenuItem(value: 'motorcycleConfig', child: Text("موتوسيكل")),
          DropdownMenuItem(value: 'pickupConfig', child: Text("ربع نقل")),
          DropdownMenuItem(value: 'jumboConfig', child: Text("جامبو / نقل ثقيل")),
        ],
        onChanged: (val) => setState(() => _vehicleConfig = val),
        validator: (v) => v == null ? "يجب تحديد نوع المركبة" : null,
      ),
    );
  }

  Widget _buildReferralField() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 5.w, vertical: 0.5.h),
      decoration: BoxDecoration(
        color: Colors.white, 
        borderRadius: BorderRadius.circular(25), 
        border: Border.all(color: Colors.green[200]!, width: 1.5)
      ),
      child: TextFormField(
        controller: _referralController,
        keyboardType: TextInputType.phone,
        style: TextStyle(fontFamily: 'Cairo', fontSize: 14.sp, fontWeight: FontWeight.bold),
        decoration: InputDecoration(
          labelText: "كود الإحالة (اختياري)",
          labelStyle: TextStyle(color: Colors.green[700], fontSize: 12.sp),
          hintText: "كود الزميل الذي دعاك",
          hintStyle: TextStyle(fontSize: 11.sp),
          border: InputBorder.none,
          prefixIcon: const Icon(Icons.card_giftcard, color: Colors.green),
        ),
      ),
    );
  }

  Widget _buildPrivacyCheckbox() {
    return CheckboxListTile(
      value: _privacyAccepted,
      onChanged: (v) => setState(() => _privacyAccepted = v!),
      activeColor: Colors.orange[900],
      title: InkWell(
        onTap: _launchPrivacyPolicy,
        child: Text(
          "أوافق على سياسة الخصوصية وشروط العمل في أكسب",
          style: TextStyle(fontFamily: 'Cairo', fontSize: 12.sp, decoration: TextDecoration.underline, fontWeight: FontWeight.bold),
        ),
      ),
      controlAffinity: ListTileControlAffinity.leading,
    );
  }

  Widget _buildSubmitButton() {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: _privacyAccepted ? Colors.black87 : Colors.grey,
        minimumSize: Size(100.w, 8.h),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
        elevation: 5,
      ),
      onPressed: _handleRegister,
      child: Text("إرسال طلب الانضمام", 
        style: TextStyle(color: Colors.white, fontSize: 16.sp, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
    );
  }

  Widget _buildField(TextEditingController ctrl, String label, IconData icon, {bool isPass = false, int passType = 0, TextInputType type = TextInputType.text}) {
    bool obscure = passType == 1 ? _obscurePassword : _obscureConfirmPassword;
    
    return Padding(
      padding: EdgeInsets.only(bottom: 1.5.h),
      child: TextFormField(
        controller: ctrl,
        obscureText: isPass ? obscure : false,
        keyboardType: type,
        textAlign: TextAlign.right,
        style: TextStyle(fontSize: 14.sp, fontFamily: 'Cairo', fontWeight: FontWeight.bold),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(fontSize: 12.sp, color: Colors.grey[700]),
          prefixIcon: Icon(icon, color: Colors.orange[900], size: 22.sp),
          suffixIcon: isPass ? IconButton(
            icon: Icon(obscure ? Icons.visibility_off : Icons.visibility), 
            onPressed: () => setState(() {
              if (passType == 1) _obscurePassword = !_obscurePassword;
              else _obscureConfirmPassword = !_obscureConfirmPassword;
            })
          ) : null,
          border: UnderlineInputBorder(borderSide: BorderSide(color: Colors.grey[300]!)),
          enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.grey[300]!)),
          focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.orange[900]!, width: 2)),
        ),
        validator: (v) => v!.isEmpty ? "هذا الحقل مطلوب" : null,
      ),
    );
  }

  void _showMsg(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(m, textAlign: TextAlign.right, style: TextStyle(fontFamily: 'Cairo', fontSize: 12.sp))));

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(35)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_outline, color: Colors.green, size: 85),
            SizedBox(height: 2.h),
            Text("طلبك قيد المراجعة", 
              style: TextStyle(fontFamily: 'Cairo', fontSize: 18.sp, fontWeight: FontWeight.bold)),
            SizedBox(height: 1.h),
            Text("سيتم مراجعة بياناتك وتفعيل حسابك خلال 24 ساعة كحد أقصى.", 
              textAlign: TextAlign.center, style: TextStyle(fontFamily: 'Cairo', fontSize: 12.sp, color: Colors.grey[700])),
            SizedBox(height: 4.h),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange[900], 
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  padding: EdgeInsets.symmetric(vertical: 1.5.h)
                ),
                onPressed: () { 
                  Navigator.pop(context); // غلق الديالوج
                  Navigator.pop(context); // العودة للشاشة السابقة (Login)
                },
                child: Text("فهمت ذلك", 
                  style: TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 14.sp, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

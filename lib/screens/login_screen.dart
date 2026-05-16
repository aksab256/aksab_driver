import 'package:flutter/material.dart';
import 'package:sizer/sizer.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:convert';

// استدعاء ملف خدمة أكيدلي الموحد
//  السطر الجديد الصحيح
import 'package:aksab_driver/services/akedly_auth_service.dart';

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
  final AkedlyAuthService _akedlyService = AkedlyAuthService();
  
  bool _isLoading = false;
  String? _transactionReqID; // لتخزين معرف عملية التحقق المستلم من أكيدلي

  Future<void> _launchPrivacyPolicy() async {
    final Uri url = Uri.parse('https://aksab.shop/');
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      _showError("تعذر فتح الرابط حالياً");
    }
  }

  // إرسال توكن الإشعارات الموحد للفيس بوك والفايرستور بدلاً من الـ AWS الملغاة
  Future<void> _sendNotificationDataToFCM(String role) async {
    try {
      String? token = await FirebaseMessaging.instance.getToken();
      String? uid = FirebaseAuth.instance.currentUser?.uid;
      if (token != null && uid != null) {
        final collections = ['deliveryReps', 'freeDrivers', 'managers'];
        for (var col in collections) {
          var docRef = FirebaseFirestore.instance.collection(col).doc(uid);
          var docSnap = await docRef.get();
          if (docSnap.exists) {
            await docRef.update({
              'insurance_points_token': token, // متوافق مع المسميات اللوجستية المعتمدة لمتطلبات مراجعة جوجل
              'last_login': FieldValue.serverTimestamp(),
            });
            break;
          }
        }
      }
    } catch (e) {
      debugPrint("❌ FCM Notification Update Error: $e");
    }
  }

  Future<void> _saveVehicleInfo(String config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_vehicle_config', config);
  }

  // دالة المعالجة الأساسية المعتمدة على أكيدلي
  Future<void> _handlePhoneLogin() async {
    if (_phoneController.text.isEmpty) {
      _showError("من فضلك أدخل رقم الهاتف أولاً");
      return;
    }

    setState(() => _isLoading = true);

    try {
      String phone = _phoneController.text.trim();
      
      // التجهيز للفحص الذكي لجميع صيغ إدخال رقم الهاتف في قواعد البيانات
      bool userExists = false;
      final collections = ['deliveryReps', 'freeDrivers', 'managers'];

      final String phoneWithZero = phone.startsWith('0') ? phone : '0$phone';
      final String phoneWithoutZero = phone.startsWith('0') ? phone.substring(1) : phone;
      final String formattedPhone = phone.startsWith('0') ? '20${phone.substring(1)}' : (phone.startsWith('20') ? phone : '20$phone');
      final List<String> searchVariations = [phoneWithZero, phoneWithoutZero, formattedPhone];

      // التأكد من وجود الكابتن مسجلاً في إحدى المجموعات قبل إرسال كود التفعيل لتقنين التكلفة والأمان
      for (var col in collections) {
        var query = await FirebaseFirestore.instance
            .collection(col)
            .where('phone', whereIn: searchVariations)
            .limit(1)
            .get();
        if (query.docs.isNotEmpty) {
          userExists = true;
          break;
        }
      }

      if (!userExists) {
        setState(() => _isLoading = false);
        _showError("❌ عذراً، هذا الرقم غير مسجل كمناديب أو مشرفين بالنظام.");
        return;
      }

      // رقم الهاتف بصيغة أكيدلي الدولية المطلوبة (مثال: +2010xxxxxxxx)
      String akedlyFormattedPhone = phone.startsWith('+') 
          ? phone 
          : (phone.startsWith('0') ? '+2${phone}' : '+20$phone');

      // استدعاء محرك أكيدلي وحل التحدي محلياً بشكل صامت
      final authResult = await _akedlyService.sendOtpDetailed(akedlyFormattedPhone);

      setState(() => _isLoading = false);

      if (authResult.isSuccess && authResult.data != null) {
        _transactionReqID = authResult.data;
        _showOTPDialog(akedlyFormattedPhone);
      } else {
        _showError(authResult.message ?? "فشل إرسال كود التحقق من أكيدلي");
      }
      
    } catch (e) {
      setState(() => _isLoading = false);
      _showError("حدث خطأ تقني أثناء محاولة الدخول");
    }
  }

  // نافذة إدخال كود التحقق مع تكبير الخطوط والتحقق المباشر
  void _showOTPDialog(String formattedPhone) {
    final otpController = TextEditingController();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
        title: Text(
          "تأكيد الهوية", 
          textAlign: TextAlign.center, 
          style: TextStyle(fontFamily: 'Cairo', fontSize: 18.sp, fontWeight: FontWeight.bold)
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "أدخل كود التحقق المرسل إلى الرقم\n$formattedPhone", 
              textAlign: TextAlign.center, 
              style: TextStyle(fontFamily: 'Cairo', fontSize: 13.sp, color: Colors.grey[700])
            ),
            SizedBox(height: 3.h),
            TextField(
              controller: otpController,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              // تم تكبير خط الأرقام لتسهيل الرؤية
              style: TextStyle(letterSpacing: 6, fontSize: 22.sp, fontWeight: FontWeight.bold, color: const Color(0xFFFF5722)),
              decoration: InputDecoration(
                hintText: "------",
                filled: true,
                fillColor: Colors.grey[100],
                contentPadding: const EdgeInsets.symmetric(vertical: 15),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15),
                  borderSide: BorderSide.none
                ),
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 2.w, vertical: 1.h),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text("إلغاء", style: TextStyle(fontFamily: 'Cairo', color: Colors.grey, fontSize: 14.sp, fontWeight: FontWeight.bold)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF5722),
                    padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 1.5.h),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                  ),
                  onPressed: () async {
                    if (otpController.text.trim().length < 6) return;
                    
                    Navigator.pop(context); // إغلاق الديالوج
                    setState(() => _isLoading = true);

                    try {
                      // التحقق من صحة الكود عبر خادم أكيدلي
                      bool isVerified = await _akedlyService.verifyOtp(_transactionReqID!, otpController.text.trim());

                      if (isVerified) {
                        // تطبيق المعادلة الذكية للدخول الصامت على الفايربيز بدون كلمات مرور معقدة للمندوب
                        String cleanPhone = _phoneController.text.trim();
                        String standardPhone = cleanPhone.startsWith('0') ? cleanPhone : '0$cleanPhone';
                        String generatedEmail = "${standardPhone}@aksab.com";
                        String generatedPassword = "Rabia_${standardPhone}";

                        try {
                          // محاولة الدخول المباشر بالحساب الصامت الصادر من الفايربيز
                          await FirebaseAuth.instance.signInWithEmailAndPassword(
                            email: generatedEmail, 
                            password: generatedPassword
                          );
                        } catch (firebaseError) {
                          // في حال كان الكابتن تم الموافقة عليه وتوثيقه حديثاً ولم ينشأ له الحساب على الـ Auth نقوم بإنشائه فوراً
                          await FirebaseAuth.instance.createUserWithEmailAndPassword(
                            email: generatedEmail, 
                            password: generatedPassword
                          );
                        }

                        // فحص الأذونات والتوجه للشاشة الصحيحة طبقاً لدوره البرمجي المعتمد
                        _checkUserAccess();
                      } else {
                        setState(() => _isLoading = false);
                        _showError("رمز التحقق غير صحيح، يرجى المحاولة مرة أخرى");
                      }
                    } catch (e) {
                      setState(() => _isLoading = false);
                      _showError("حدث خطأ أثناء تأكيد رمز التحقق");
                    }
                  },
                  child: Text("تأكيد", style: TextStyle(fontFamily: 'Cairo', color: Colors.white, fontSize: 14.sp, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }

  // دالة فحص الصلاحيات الأصلية والتوجه إلى شاشات التطبيق المتعددة (مندوب حر، مندوب شركة، مشرف/مدير)
  Future<void> _checkUserAccess() async {
    try {
      String uid = FirebaseAuth.instance.currentUser!.uid;

      // 1. التحقق من مناديب الشركات
      var repSnap = await FirebaseFirestore.instance.collection('deliveryReps').doc(uid).get();
      if (repSnap.exists) {
        var userData = repSnap.data()!;
        if (userData['status'] == 'approved') {
          await _sendNotificationDataToFCM('delivery_rep');
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
          await _sendNotificationDataToFCM('free_driver');
          if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const FreeDriverHomeScreen()));
          return;
        } else {
          await FirebaseAuth.instance.signOut();
          _showError("❌ حسابك قيد المراجعة أو غير مفعل.");
          return;
        }
      }

      // 3. التحقق من المدراء والمشرفين للمنظومة اللوجستية
      var managerSnap = await FirebaseFirestore.instance.collection('managers').doc(uid).get();
      if (managerSnap.exists) {
        var managerData = managerSnap.data()!;
        String role = managerData['role'] ?? '';
        if (role == 'delivery_manager' || role == 'delivery_supervisor') {
          await _sendNotificationDataToFCM(role);
          if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const DeliveryAdminDashboard()));
          return;
        }
      }

      _showError("عذراً، هذا الحساب لا يملك صلاحيات دخول على منظومة الكابتن");
      await FirebaseAuth.instance.signOut();

    } catch (e) {
      _showError("خطأ في جلب بيانات الحساب وتأكيد الصلاحيات");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, textAlign: TextAlign.right, style: TextStyle(fontSize: 14.sp, fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
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
                              Text("رابية أحلى - كابتن", style: TextStyle(fontSize: 28.sp, fontWeight: FontWeight.bold, color: Colors.white, fontFamily: 'Cairo')),
                              Text("منصة إدارة العهدة واللوجستيات", style: TextStyle(fontSize: 14.sp, color: Colors.white70, fontFamily: 'Cairo')),
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
                              SizedBox(height: 4.h),
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
                          style: TextStyle(fontFamily: 'Cairo', fontSize: 14.sp, color: Colors.black87),
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

  Widget _buildCustomField(TextEditingController controller, String label, IconData icon, {TextInputType type = TextInputType.text}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(label, style: TextStyle(fontFamily: 'Cairo', fontSize: 14.sp, color: Colors.grey[800], fontWeight: FontWeight.bold)),
        SizedBox(height: 1.5.h),
        TextField(
          controller: controller,
          keyboardType: type,
          textAlign: TextAlign.right,
          // تم تكبير حجم نص الإدخال
          style: TextStyle(fontSize: 16.sp, fontFamily: 'Cairo', fontWeight: FontWeight.bold, letterSpacing: 1),
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.grey[50],
            prefixIcon: Icon(icon, color: const Color(0xFFFF5722), size: 24.sp),
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
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
        minimumSize: Size(100.w, 9.h), // زيادة الارتفاع ليتناسب مع الخط الكبير
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        elevation: 10,
      ),
      onPressed: _handlePhoneLogin,
      child: Text("دخول للنظام", style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
    );
  }

  Widget _buildPrivacyButton() {
    return InkWell(
      onTap: _launchPrivacyPolicy,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.shield_outlined, size: 15.sp, color: Colors.grey),
          SizedBox(width: 2.w),
          Text("سياسة الخصوصية وشروط الاستخدام", style: TextStyle(color: Colors.grey[600], fontSize: 12.sp, fontFamily: 'Cairo', fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
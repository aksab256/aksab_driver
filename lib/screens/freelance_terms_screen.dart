import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:sizer/sizer.dart';

class FreelanceTermsScreen extends StatefulWidget {
  final String userId;
  const FreelanceTermsScreen({super.key, required this.userId});

  @override
  State<FreelanceTermsScreen> createState() => _FreelanceTermsScreenState();
}

class _FreelanceTermsScreenState extends State<FreelanceTermsScreen> {
  bool _isUpdating = false;
  bool _showSuccess = false; // لإظهار علامة الصح

  Future<void> _handleAcceptance() async {
    if (_isUpdating) return;

    setState(() => _isUpdating = true);

    try {
      // 1. تحديث Firestore (نستخدم مجموعة deliveryReps كما في الكود الرئيسي)
      await FirebaseFirestore.instance
          .collection('deliveryReps')
          .doc(widget.userId)
          .set({
        'hasAcceptedTerms': true,
        'termsAcceptedDate': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // 2. إظهار علامة الصح الخضراء لثانية واحدة
      setState(() {
        _isUpdating = false;
        _showSuccess = true;
      });

      await Future.delayed(const Duration(milliseconds: 1000));

      // 3. الإغلاق وإرجاع قيمة true للشاشة الرئيسية
      if (mounted) {
        // نستخدم rootNavigator لضمان إغلاق الـ BottomSheet بنجاح
        Navigator.of(context, rootNavigator: true).pop(true);
      }
    } catch (e) {
      setState(() => _isUpdating = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("خطأ في الاتصال: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 90.h,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(topLeft: Radius.circular(25), topRight: Radius.circular(25)),
      ),
      child: Column(
        children: [
          // شريط السحب العلوي
          Container(
            margin: const EdgeInsets.symmetric(vertical: 12),
            width: 40,
            height: 5,
            decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10)),
          ),
          
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Center(
                    child: Text("شروط وإلتزامات العمل الحر",
                        style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w900, fontSize: 18, color: Color(0xFF2C3E50))),
                  ),
                  const SizedBox(height: 20),
                  _buildTermItem("1. الالتزام بمواعيد الاستلام والتسليم المحددة في الطلب."),
                  _buildTermItem("2. الحفاظ على سلامة الطرود والمنتجات من أي تلف أو كسر."),
                  _buildTermItem("3. تفعيل خاصية الموقع الجغرافي (GPS) بشكل دائم أثناء العمل."),
                  _buildTermItem("4. الالتزام بالمظهر اللائق والتعامل الاحترافي مع العملاء."),
                  _buildTermItem("5. تحصيل المبالغ المالية بدقة وتوريدها للمنصة في المواعيد المقررة."),
                  _buildTermItem("6. يمنع منعاً باتاً فتح الطرود أو التدخل في خصوصية محتواها."),
                  _buildTermItem("7. المنصة غير مسؤولة عن أي مخالفات مرورية يقوم بها المندوب."),
                  _buildTermItem("8. يحق للمنصة إيقاف الحساب في حال ثبوت تلاعب أو شكاوى متكررة."),
                ],
              ),
            ),
          ),

          // منطقة الزر المعدلة
          Container(
            padding: EdgeInsets.fromLTRB(20, 10, 20, MediaQuery.of(context).padding.bottom + 20),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -5))]
            ),
            child: _showSuccess 
              ? const Column(
                  children: [
                    Icon(Icons.check_circle_rounded, color: Colors.green, size: 50),
                    SizedBox(height: 5),
                    Text("تمت الموافقة بنجاح", style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, color: Colors.green)),
                  ],
                )
              : _isUpdating 
                ? const Center(child: CircularProgressIndicator())
                : SizedBox(
                    width: double.infinity,
                    height: 55, // ارتفاع متناسق
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1565C0),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                        elevation: 0,
                      ),
                      onPressed: _handleAcceptance,
                      child: const Text(
                        "أوافق على الشروط والالتزامات",
                        style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildTermItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check_circle_outline, color: Colors.blue, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: const TextStyle(fontFamily: 'Cairo', fontSize: 14, height: 1.5, color: Colors.black87)),
          ),
        ],
      ),
    );
  }
}

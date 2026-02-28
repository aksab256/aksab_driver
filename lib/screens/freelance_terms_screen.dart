// lib/screens/freelance_terms_screen.dart
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
  bool _showSuccess = false;

  Future<void> _handleAcceptance() async {
    if (_isUpdating) return;
    setState(() => _isUpdating = true);

    try {
      await FirebaseFirestore.instance
          .collection('freeDrivers')
          .doc(widget.userId)
          .set({
        'hasAcceptedTerms': true,
        'termsAcceptedDate': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      setState(() {
        _isUpdating = false;
        _showSuccess = true;
      });

      await Future.delayed(const Duration(milliseconds: 1200));

      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop(true);
      }
    } catch (e) {
      setState(() => _isUpdating = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("عذراً، حدث خطأ: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 92.h,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(topLeft: Radius.circular(30), topRight: Radius.circular(30)),
      ),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 15),
            width: 50,
            height: 5,
            decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10)),
          ),
          
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 25),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Center(
                    child: Column(
                      children: [
                        Icon(Icons.gavel_rounded, color: Color(0xFF2C3E50), size: 40),
                        SizedBox(height: 10),
                        Text("اتفاقية وقواعد إدارة العهدة",
                            style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w900, fontSize: 18, color: Color(0xFF2C3E50))),
                      ],
                    ),
                  ),
                  const SizedBox(height: 25),
                  
                  // 1. العلاقة القانونية
                  _buildTermItem(
                    "1. طبيعة الارتباط التقني:", 
                    "يقر المستخدم بأن منصة 'أكسب' هي أداة تقنية لتنظيم الدعم اللوجستي وتوجيه طلبات النقل، ولا تعتبر المنصة طرفاً تعاقدياً في ملكية الشحنات، والمندوب مسؤول بشكل مستقل عن تنفيذ المهام المسندة إليه."
                  ),
                  
                  // 2. المسؤولية الجنائية (قوية جداً قانونياً)
                  _buildTermItem(
                    "2. فحص الأمانات والمحظورات القانونية:", 
                    "يتحمل المندوب المسؤولية القانونية (الجنائية والمدنية) الكاملة عن فحص الأمانة قبل استلامها في عهدته. يحظر قطعيًا نقل أي مواد تخالف التشريعات المصرية (مثل المواد المخدرة، الأسلحة، أو المهربات). استلامك للطلب هو إقرار رسمي بخلوه من أي محظورات."
                  ),
                  
                  // 3. الضمان المالي
                  _buildTermItem(
                    "3. حماية العهدة والضمان:", 
                    "يلتزم المندوب بضمان وصول الشحنة بحالتها الأصلية. في حال ثبوت الإهمال أو التلف، يلتزم المندوب بتعويض القيمة المقابلة لنقاط الأمان المحجوزة لتغطية العهدة المستلمة."
                  ),
                  
                  // 4. الخصوصية
                  _buildTermItem(
                    "4. بيانات الموقع والتشغيل اللوجستي:", 
                    "لضمان دقة الرادار اللوجستي وتتبع مسار العهدة، يوافق المندوب على مشاركة بيانات الموقع الجغرافي بشكل مستمر أثناء تفعيل وضع الاتصال، وذلك لحماية حقوق جميع الأطراف."
                  ),
                  
                  // 5. إدارة نقاط الأمان (التعديل المهم لجوجل)
                  _buildTermItem(
                    "5. تسوية العهدة ونقاط التأمين:", 
                    "يلتزم المندوب بتسوية العهدة المالية وتأكيد استلام الأمانات فور انتهاء المهمة. يتم تخصيص (نقاط تأمين عهدة) من رصيد الحساب لضمان النقل الآمن، ولا يعتبر ذلك نشاطاً بنكياً بل إجراءً تنظيمياً داخلياً لضمان الأمانات."
                  ),
                  
                  // 6. السلوك العام
                  _buildTermItem(
                    "6. جودة الخدمة وسياسة الاستخدام:", 
                    "تلتزم إدارة المنصة بحظر أي حساب يثبت تكرار إخلاله ببروتوكول تسليم العهدة أو سوء التعامل مع أطراف العملية اللوجستية، حفاظاً على معايير الأمان والجودة."
                  ),
                  
                  const SizedBox(height: 20),
                  const Text(
                    "* بالنقر أدناه، أنت تقر رسمياً بقبولك لكافة البنود السابقة بصيغتها القانونية واللوجستية.",
                    style: TextStyle(fontFamily: 'Cairo', fontSize: 10, color: Colors.grey, fontStyle: FontStyle.italic),
                  ),
                ],
              ),
            ),
          ),

          // منطقة الزر
          Container(
            padding: EdgeInsets.fromLTRB(25, 15, 25, MediaQuery.of(context).padding.bottom + 20),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 15, offset: const Offset(0, -5))]
            ),
            child: _showSuccess 
              ? const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle_rounded, color: Colors.green, size: 60),
                    SizedBox(height: 10),
                    Text("تم حفظ موافقتك القانونية", 
                      style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 18, color: Colors.green)),
                  ],
                )
              : _isUpdating 
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF1565C0)))
                : SizedBox(
                    width: double.infinity,
                    height: 55,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1565C0),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
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

  Widget _buildTermItem(String title, String description) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.security_outlined, color: Color(0xFF1565C0), size: 22),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, 
                  style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black87)),
                const SizedBox(height: 5),
                Text(description, 
                  style: const TextStyle(fontFamily: 'Cairo', fontSize: 12, height: 1.6, color: Colors.black54)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

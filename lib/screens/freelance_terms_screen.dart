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
      // التحديث في مجموعة deliveryReps لضمان تزامن الأذونات
      await FirebaseFirestore.instance
          .collection('deliveryReps')
          .doc(widget.userId)
          .set({
        'hasAcceptedTerms': true,
        'termsAcceptedDate': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      setState(() {
        _isUpdating = false;
        _showSuccess = true;
      });

      // انتظار لرؤية علامة الصح قبل الإغلاق
      await Future.delayed(const Duration(milliseconds: 1200));

      if (mounted) {
        // إرجاع true لإخطار الهوم سكرين بفتح طلب إذن الإشعارات
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
          // مقبض السحب العلوي
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
                        Text("اتفاقية وقواعد العمل الحر",
                            style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w900, fontSize: 18, color: Color(0xFF2C3E50))),
                      ],
                    ),
                  ),
                  const SizedBox(height: 25),
                  
                  _buildTermItem(
                    "1. طبيعة العلاقة (وسيط تقني):", 
                    "يقر الكابتن بأن منصة 'أكسب' هي وسيط تقني يربط بين مقدم الخدمة وطالبها، ولا تعتبر المنصة طرفاً في عملية البيع أو صاحب عمل، والمندوب يعمل بشكل حر ومستقل."
                  ),
                  
                  _buildTermItem(
                    "2. معاينة الطرود والمحظورات:", 
                    "يتحمل المندوب المسؤولية الجنائية والمدنية الكاملة عن معاينة الطرد قبل استلامه. يحظر تماماً نقل الأسلحة، المخدرات، السجائر المهربة، أو أي مواد تخالف القانون المصري."
                  ),
                  
                  _buildTermItem(
                    "3. سلامة الشحنة والضمان:", 
                    "يلتزم المندوب بالحفاظ على الشحنة من لحظة الاستلام وحتى التسليم. في حال حدوث تلف أو فقدان ناتج عن إهمال، يحق للمنصة خصم قيمتها من مستحقات المندوب."
                  ),
                  
                  _buildTermItem(
                    "4. الموقع الجغرافي والخصوصية:", 
                    "لضمان تشغيل رادار الطلبات، يوافق المندوب على مشاركة موقعه الجغرافي مع التطبيق (حتى في حال كان التطبيق مغلقاً أو في الخلفية) أثناء فترات الاتصال."
                  ),
                  
                  _buildTermItem(
                    "5. التحصيل المالي والأمانة:", 
                    "يلتزم المندوب بتحصيل المبالغ الموضحة في التطبيق فقط، وتوريد عمولة المنصة بشكل فوري عبر وسائل الشحن المتاحة لضمان استمرار عمل الحساب."
                  ),
                  
                  _buildTermItem(
                    "6. سياسة الإلغاء والسلوك:", 
                    "يجب التعامل مع العملاء بأقصى درجات الاحترام. يحق للإدارة حظر الحساب في حال تكرار إلغاء الطلبات بعد قبولها أو ثبوت سوء سلوك مع العميل."
                  ),
                  
                  const SizedBox(height: 20),
                  const Text(
                    "* بالضغط على الزر أدناه، أنت تقر بقراءة وفهم كافة الشروط وتلتزم بالعمل بموجبها.",
                    style: TextStyle(fontFamily: 'Cairo', fontSize: 10, color: Colors.grey, fontStyle: FontStyle.italic),
                  ),
                ],
              ),
            ),
          ),

          // منطقة الزر التفاعلية
          Container(
            padding: EdgeInsets.fromLTRB(25, 15, 25, MediaQuery.of(context).padding.bottom + 20),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 15, offset: const Offset(0, -5))]
            ),
            child: _showSuccess 
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.check_circle_rounded, color: Colors.green, size: 60),
                    const SizedBox(height: 10),
                    Text("تم تسجيل موافقتك بنجاح", 
                      style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 14.sp, color: Colors.green)),
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

  Widget _buildTermItem(String title, String description) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.verified_user_rounded, color: Color(0xFF1565C0), size: 22),
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

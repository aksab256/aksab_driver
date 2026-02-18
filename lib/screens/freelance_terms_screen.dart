import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:sizer/sizer.dart';

class FreelanceTermsScreen extends StatefulWidget {
  final String userId; // لتحديث حالة الموافقة في قاعدة البيانات

  const FreelanceTermsScreen({super.key, required this.userId});

  @override
  State<FreelanceTermsScreen> createState() => _FreelanceTermsScreenState();
}

class _FreelanceTermsScreenState extends State<FreelanceTermsScreen> {
  bool _isUpdating = false;

  @override
  Widget build(BuildContext context) {
    // WillPopScope لمنع زر الرجوع في الأندرويد من إغلاق الشاشة
    return WillPopScope(
      onWillPop: () async => false,
      child: Container(
        height: 90.h, // تأخذ 90% من طول الشاشة
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: Column(
          children: [
            // شريط الإمساك العلوي
            SizedBox(height: 15.sp),
            Container(
              width: 40,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            
            // العنوان الرئيسي
            Padding(
              padding: EdgeInsets.all(15.sp),
              child: Text(
                "شروط وقواعد الانضمام (كابتن حر)",
                style: TextStyle(
                  fontSize: 15.sp, 
                  fontWeight: FontWeight.bold, 
                  color: Colors.blue[900]
                ),
              ),
            ),
            const Divider(),

            // محتوى البنود (قابلة للتمرير)
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(horizontal: 15.sp),
                child: Column(
                  children: [
                    _buildSection(
                      "1. دور المنصة (وسيط تقني)",
                      "تعد منصة 'أكسب' وسيطاً تقنياً فقط يربط بين صاحب الطرد والمندوب الحر. ولا تنشأ عن هذه العلاقة أي صلة وظيفية أو تأمينية، والمندوب مسؤول عن ضرائبه وتراخيص مركباته بشكل مستقل.",
                    ),
                    _buildSection(
                      "2. فحص الطرود والقانونية",
                      "يقر المندوب بمسؤوليته عن معاينة الطرد قبل استلامه. يحظر تماماً نقل الأسلحة، المواد المخدرة، الأموال، أو أي مواد تخالف قانون جمهورية مصر العربية. وفي حال الشك، يجب إلغاء الرحلة وإبلاغ الإدارة فوراً.",
                    ),
                    _buildSection(
                      "3. الحفاظ على الشحنة",
                      "المندوب هو الضامن الوحيد لسلامة الطرد منذ لحظة الاستلام وحتى التسليم. أي تلف أو فقدان ناتج عن إهمال الكابتن يقع تحت مسؤوليته المالية والقانونية المباشرة أمام العميل.",
                    ),
                    _buildSection(
                      "4. عمولة المنصة والتحصيل",
                      "يوافق الكابتن على استقطاع النسبة المقررة للمنصة من قيمة كل رحلة. وفي حال التحصيل النقدي، يلتزم بتوريد المبالغ عبر القنوات المعتمدة في التطبيق دون تأخير.",
                    ),
                    _buildSection(
                      "5. سياسة الخصوصية والموقع",
                      "بموافقتك، يمنحك التطبيق إذناً بتتبع موقعك الجغرافي (حتى في الخلفية) أثناء تفعيل وضع العمل، وذلك لضمان توجيه الطلبات الأقرب إليك وحفظ حقوق الأطراف في تتبع مسار الرحلة.",
                    ),
                    _buildSection(
                      "6. السلوك والحظر",
                      "يُحظر التواصل مع العملاء خارج إطار الرحلة لأي سبب. التقييمات المنخفضة المتكررة أو سوء السلوك مع العملاء يؤدي إلى حظر الحساب نهائياً دون الرجوع للمندوب.",
                    ),
                    SizedBox(height: 20.sp),
                  ],
                ),
              ),
            ),

            // منطقة الأزرار
            Padding(
              padding: EdgeInsets.all(15.sp),
              child: _isUpdating 
                ? const CircularProgressIndicator()
                : SizedBox(
                    width: double.infinity,
                    height: 50.sp,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue[800],
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                        elevation: 5,
                      ),
                      onPressed: () => _handleAcceptance(),
                      child: Text(
                        "أوافق على الشروط والالتزامات",
                        style: TextStyle(
                          fontSize: 13.sp, 
                          color: Colors.white, 
                          fontWeight: FontWeight.bold
                        ),
                      ),
                    ),
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(String title, String body) {
    return Padding(
      padding: EdgeInsets.only(bottom: 15.sp),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.verified_user, color: Colors.green, size: 20),
              SizedBox(width: 8.sp),
              Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.sp)),
            ],
          ),
          SizedBox(height: 5.sp),
          Text(
            body,
            style: TextStyle(fontSize: 11.sp, color: Colors.grey[800], height: 1.5),
          ),
        ],
      ),
    );
  }

  Future<void> _handleAcceptance() async {
    setState(() => _isUpdating = true);
    try {
      // تحديث حالة الموافقة في Firestore
      await FirebaseFirestore.instance
          .collection('deliveryReps')
          .doc(widget.userId)
          .update({
        'hasAcceptedTerms': true,
        'termsAcceptedDate': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        Navigator.pop(context); // إغلاق المنبثقة والعودة للتطبيق
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("حدث خطأ أثناء حفظ الموافقة: $e"))
      );
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }
}

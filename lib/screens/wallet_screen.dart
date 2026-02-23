import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:sizer/sizer.dart';
import 'package:url_launcher/url_launcher.dart';

class WalletScreen extends StatelessWidget {
  const WalletScreen({super.key});

  // --- 💸 1. سداد رسوم تشغيل (الـ Lambda ستقوم بإنشاء رابط Paymob) ---
  Future<void> _processCharge(BuildContext context, double amount) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    _showLoading(context);
    try {
      // نضع الطلب في مجموعة "pendingInvoices" 
      // الـ Lambda (V2_create_invoice) ستلتقط هذا المستند وتضيف له paymentUrl
      await FirebaseFirestore.instance.collection('pendingInvoices').add({
        'driverId': uid,
        'amount': amount,
        'status': 'pay_now', // حالة تخبر اللمدا أن تبدأ المعالجة
        'type': 'OPERATIONAL_FEES', 
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (context.mounted) Navigator.pop(context); // إغلاق اللودينج
      _showInfoSheet(context, "تم استلام طلبك", "جاري تجهيز رابط السداد الآمن، سيظهر في السجل أسفل الشاشة خلال ثوانٍ.");
    } catch (e) {
      if (context.mounted) Navigator.pop(context);
      _showInfoSheet(context, "خطأ", "فشل الاتصال بالخادم.");
    }
  }

  // --- 💰 2. تسوية مستحقات (الـ Lambda ستتحقق من الرصيد وتنفذ التحويل) ---
  Future<void> _executeWithdrawal(BuildContext context, double amount) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    _showLoading(context);
    try {
      // الـ Lambda (V2_process_withdrawal) ستراقب هذه المجموعة
      await FirebaseFirestore.instance.collection('withdrawRequests').add({
        'driverId': uid,
        'amount': amount,
        'status': 'pending',
        'type': 'EARNINGS_SETTLEMENT', 
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (context.mounted) {
        Navigator.pop(context);
        _showInfoSheet(context, "تم إرسال طلب التسوية", "سيتم مراجعة مستحقاتك وتحويلها إلى محفظتك خلال 24 ساعة عمل.");
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context);
        _showInfoSheet(context, "خطأ", "فشل إرسال الطلب، حاول مجدداً.");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return Scaffold(
      backgroundColor: const Color(0xFFFBFBFB),
      appBar: AppBar(
        title: const Text("حساب العهدة والعملات", 
          style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Cairo', fontSize: 16)),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black,
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('freeDrivers').doc(uid).snapshots(),
        builder: (context, driverSnap) {
          if (!driverSnap.hasData) return const Center(child: CircularProgressIndicator(color: Colors.orange));
          
          var userData = driverSnap.data!.data() as Map<String, dynamic>?;
          double walletBalance = (userData?['walletBalance'] ?? 0.0).toDouble();
          double creditLimit = (userData?['creditLimit'] ?? 50.0).toDouble();

          return SingleChildScrollView(
            child: Column(
              children: [
                // كارت الرصيد المتطور
                _buildAdvancedBalanceCard(walletBalance, creditLimit, walletBalance + creditLimit),
                
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text("المستحقات القابلة للتسوية: ${walletBalance.toStringAsFixed(2)} ج.م",
                    style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w900, fontFamily: 'Cairo', color: Colors.blueGrey[800])),
                ),

                // أزرار الأكشن
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  child: Row(
                    children: [
                      Expanded(child: _actionBtn(Icons.account_balance_wallet_outlined, "سداد رسوم", Colors.green[700]!, () => _showChargePicker(context))),
                      const SizedBox(width: 15),
                      Expanded(child: _actionBtn(Icons.assignment_turned_in_outlined, "طلب تسوية", Colors.blueGrey[800]!, () => _showWithdrawDialog(context, walletBalance))),
                    ],
                  ),
                ),

                _sectionHeader("سجل العمليات الإدارية"),

                // عرض السجل (المدمج بين الفواتير الجاهزة واللوجز)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _buildCombinedHistory(uid),
                ),

                _buildLegalDisclaimer(),
              ],
            ),
          );
        },
      ),
    );
  }

  // --- 🛠️ دوال بناء العناصر الفرعية ---

  Widget _buildCombinedHistory(String? uid) {
    return StreamBuilder<QuerySnapshot>(
      // 1. عرض الفواتير التي جهزتها اللمدا برابط الدفع (status: ready_for_payment)
      stream: FirebaseFirestore.instance.collection('pendingInvoices')
          .where('driverId', isEqualTo: uid)
          .where('status', isEqualTo: 'ready_for_payment')
          .snapshots(),
      builder: (context, pendingSnap) {
        return StreamBuilder<QuerySnapshot>(
          // 2. عرض العمليات التي تمت بالفعل وتأثر بها الرصيد
          stream: FirebaseFirestore.instance.collection('walletLogs')
              .where('driverId', isEqualTo: uid)
              .orderBy('timestamp', descending: true)
              .limit(10)
              .snapshots(),
          builder: (context, logSnap) {
            List<Map<String, dynamic>> allItems = [];
            
            if (pendingSnap.hasData) {
              for (var doc in pendingSnap.data!.docs) {
                var d = doc.data() as Map<String, dynamic>;
                d['isInvoice'] = true;
                allItems.add(d);
              }
            }
            if (logSnap.hasData) {
              for (var doc in logSnap.data!.docs) {
                var d = doc.data() as Map<String, dynamic>;
                d['isInvoice'] = false;
                allItems.add(d);
              }
            }

            if (allItems.isEmpty) {
              return Container(
                height: 150,
                alignment: Alignment.center,
                child: Text("لا توجد عمليات سابقة", style: TextStyle(fontFamily: 'Cairo', color: Colors.grey[400])),
              );
            }

            return ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: allItems.length,
              itemBuilder: (context, index) {
                var item = allItems[index];
                bool isInvoice = item['isInvoice'] ?? false;
                double amount = (item['amount'] ?? 0.0).toDouble();

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15), 
                    side: BorderSide(color: isInvoice ? Colors.orange : Colors.grey[100]!),
                  ),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: isInvoice ? Colors.orange[50] : Colors.grey[50],
                      child: Icon(isInvoice ? Icons.payment : Icons.history, 
                        color: isInvoice ? Colors.orange : Colors.blueGrey, size: 20),
                    ),
                    title: Text(isInvoice ? "رابط سداد جاهز" : (amount > 0 ? "تسوية مستحقات" : "خصم رسوم تشغيل"),
                        style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 13)),
                    subtitle: Text(isInvoice ? "اضغط للسداد الآن" : "عملية مكتملة", 
                        style: const TextStyle(fontFamily: 'Cairo', fontSize: 11)),
                    trailing: isInvoice 
                      ? ElevatedButton(
                          onPressed: () => _launchPaymentUrl(item['paymentUrl']),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange[900],
                            padding: const EdgeInsets.symmetric(horizontal: 15),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                          child: const Text("سداد", style: TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 12)),
                        )
                      : Text("${amount > 0 ? '+' : ''}${amount.toStringAsFixed(1)} ج.م", 
                          style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w900, 
                          color: amount > 0 ? Colors.green : Colors.red)),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  // (بقية الدوال المساعدة تظل كما هي في كودك الأصلي...)
  // _buildAdvancedBalanceCard, _actionBtn, _sectionHeader, _launchPaymentUrl, إلخ.

  Widget _buildAdvancedBalanceCard(double w, double c, double t) => Container(
    margin: const EdgeInsets.all(20), padding: const EdgeInsets.all(25),
    decoration: BoxDecoration(
      gradient: const LinearGradient(colors: [Color(0xFF1a1a1a), Color(0xFF3a3a3a)], begin: Alignment.topLeft, end: Alignment.bottomRight),
      borderRadius: BorderRadius.circular(30),
    ),
    child: Column(children: [
      const Text("إجمالي الرصيد التشغيلي", style: TextStyle(color: Colors.white70, fontFamily: 'Cairo', fontSize: 14)),
      const SizedBox(height: 5),
      Text("${t.toStringAsFixed(2)} ج.م", style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900)),
      const Divider(color: Colors.white24, height: 30),
      Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
        _miniInfo("متاح للتسوية", "${w.toStringAsFixed(1)}"),
        _miniInfo("حد العمل", "${c.toStringAsFixed(1)}"),
      ])
    ]),
  );

  Widget _miniInfo(String l, String v) => Column(children: [
    Text(l, style: const TextStyle(color: Colors.white60, fontSize: 11, fontFamily: 'Cairo')),
    Text(v, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16)),
  ]);

  void _launchPaymentUrl(String? url) async {
    if (url == null || url.isEmpty) return;
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      debugPrint("Could not launch $url");
    }
  }

  Widget _actionBtn(IconData icon, String label, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(15),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: Colors.white, 
          borderRadius: BorderRadius.circular(15), 
          border: Border.all(color: Colors.grey[200]!),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 26.sp),
            const SizedBox(height: 10),
            Text(label, style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w900, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
      child: Align(
        alignment: Alignment.centerRight,
        child: Text(title, style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w900, fontSize: 16, color: Colors.black87)),
      ),
    );
  }

  Widget _buildLegalDisclaimer() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(30, 10, 30, 30),
      child: Text(
        "هذا الحساب مخصص حصرياً لإدارة العمولات التشغيلية وتسوية مستحقات الكابتن الناتجة عن خدمات التوصيل داخل منصة أكسب. لا يقدم التطبيق خدمات مصرفية أو محافظ مالية للجمهور.",
        textAlign: TextAlign.center,
        style: TextStyle(fontFamily: 'Cairo', fontSize: 8.sp, color: Colors.grey[400], height: 1.5),
      ),
    );
  }

  void _showLoading(BuildContext context) => showDialog(context: context, barrierDismissible: false, builder: (c) => const Center(child: CircularProgressIndicator(color: Colors.orange)));
  
  void _showInfoSheet(BuildContext context, String t, String m) => showModalBottomSheet(
    context: context, 
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
    builder: (c) => SafeArea(
      child: Padding(padding: const EdgeInsets.all(25), child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(t, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, fontFamily: 'Cairo')),
        const SizedBox(height: 10),
        Text(m, textAlign: TextAlign.center, style: const TextStyle(fontFamily: 'Cairo', color: Colors.grey)),
        const SizedBox(height: 25),
        SizedBox(width: double.infinity, child: ElevatedButton(onPressed: () => Navigator.pop(context), child: const Text("تم", style: TextStyle(fontFamily: 'Cairo'))))
      ])),
    )
  );

  void _showChargePicker(BuildContext context) {
    showModalBottomSheet(
      context: context, 
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (c) => SafeArea(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 15),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("سداد رسوم تشغيل الحساب", style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w900, fontSize: 16)),
              const SizedBox(height: 10),
              const Text("اختر المبلغ المطلوب سداده لتفعيل استقبال الطلبات", style: TextStyle(fontFamily: 'Cairo', fontSize: 11, color: Colors.grey)),
              const SizedBox(height: 20),
              Wrap(spacing: 10, runSpacing: 10, alignment: WrapAlignment.center, children: [50, 100, 200, 500].map((a) => ActionChip(
                label: Text("$a ج.م", style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
                onPressed: () { Navigator.pop(context); _processCharge(context, a.toDouble()); }
              )).toList()),
              const SizedBox(height: 15),
            ],
          ),
        ),
      )
    );
  }

  void _showWithdrawDialog(BuildContext context, double current) {
    final ctrl = TextEditingController();
    showDialog(
      context: context, 
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("تسوية مستحقات الكابتن", style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold), textAlign: TextAlign.center),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("رصيدك الحالي: $current ج.م", style: const TextStyle(fontSize: 12, color: Colors.grey, fontFamily: 'Cairo')),
            const SizedBox(height: 10),
            TextField(controller: ctrl, keyboardType: TextInputType.number, decoration: const InputDecoration(hintText: "أدخل المبلغ المراد تسويته")),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("إلغاء", style: TextStyle(fontFamily: 'Cairo'))),
          ElevatedButton(
            onPressed: () {
              double? amount = double.tryParse(ctrl.text);
              if (amount != null && amount > 0 && amount <= current) {
                Navigator.pop(context);
                _executeWithdrawal(context, amount);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("المبلغ غير صحيح")));
              }
            },
            child: const Text("طلب تسوية", style: TextStyle(fontFamily: 'Cairo')),
          )
        ],
      )
    );
  }
}

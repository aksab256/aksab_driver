import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:sizer/sizer.dart';
import 'package:url_launcher/url_launcher.dart';

class WalletScreen extends StatelessWidget {
  const WalletScreen({super.key});

  // دالة مساعدة لتحويل القيم من Firestore إلى Double بأمان
  double _toDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is int) return value.toDouble();
    if (value is double) return value;
    return 0.0;
  }

  // --- 💸 1. طلب شحن نقاط الأمان ---
  Future<void> _processCharge(BuildContext context, double amount) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    _showLoading(context);
    try {
      await FirebaseFirestore.instance.collection('pendingInvoices').add({
        'driverId': uid,
        'amount': amount,
        'status': 'pay_now',
        'type': 'OPERATIONAL_FEES', 
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (context.mounted) Navigator.pop(context);
      _showInfoSheet(context, "تم استلام طلبك", "جاري تجهيز رابط سداد آمن لتعبئة (نقاط الأمان)، ستظهر في سجل العمليات فور جاهزيتها.");
    } catch (e) {
      if (context.mounted) Navigator.pop(context);
      _showInfoSheet(context, "خطأ", "فشل الاتصال بالخادم، يرجى المحاولة لاحقاً.");
    }
  }

  // --- 💰 2. طلب تسوية أرباح (سحب) ---
  Future<void> _executeWithdrawal(BuildContext context, double amount) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    _showLoading(context);
    try {
      await FirebaseFirestore.instance.collection('withdrawRequests').add({
        'driverId': uid,
        'amount': amount,
        'status': 'pending',
        'type': 'EARNINGS_SETTLEMENT', 
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (context.mounted) {
        Navigator.pop(context);
        _showInfoSheet(context, "طلب التسوية قيد المراجعة", "سيتم مراجعة سجل العهدة وتحويل المبالغ المتاحة لحسابك خلال 24 ساعة.");
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
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: () => Navigator.of(context).pop(), // رجوع خطوة واحدة
        ),
        title: const Text("إدارة العهدة ونقاط الأمان", 
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

          // قراءة البيانات من مستند المندوب مباشرة (كما في لقطة شاشة Firestore)
          double walletBalance = _toDouble(userData?['walletBalance']);
          double creditLimit = _toDouble(userData?['creditLimit']);
          double lockedInsurance = _toDouble(userData?['insurance_points']); // القراءة المباشرة للعهدة المحجوزة

          return SingleChildScrollView(
            child: Column(
              children: [
                _buildMainAssetCard(walletBalance, creditLimit, lockedInsurance),
                
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text("إجمالي الأمانات بالذمة: ${(walletBalance + lockedInsurance).toStringAsFixed(2)} ج.م",
                    style: TextStyle(fontSize: 11.sp, fontWeight: FontWeight.bold, fontFamily: 'Cairo', color: Colors.blueGrey[600])),
                ),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  child: Row(
                    children: [
                      Expanded(child: _actionBtn(Icons.add_moderator_outlined, "تعبئة نقاط", Colors.green[700]!, () => _showChargePicker(context))),
                      const SizedBox(width: 15),
                      Expanded(child: _actionBtn(Icons.account_balance_outlined, "طلب تسوية", Colors.blueGrey[800]!, () => _showWithdrawDialog(context, walletBalance))),
                    ],
                  ),
                ),

                _sectionHeader("سجل تأمين العهدة"),

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

  // --- كارت الأرصدة الرئيسي ---
  Widget _buildMainAssetCard(double available, double limit, double locked) => Container(
    margin: const EdgeInsets.all(20), padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      gradient: const LinearGradient(colors: [Color(0xFF232526), Color(0xFF414345)], begin: Alignment.topLeft, end: Alignment.bottomRight),
      borderRadius: BorderRadius.circular(25),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 10, offset: const Offset(0, 5))],
    ),
    child: Column(children: [
      const Text("نقاط الأمان المتاحة", style: TextStyle(color: Colors.white70, fontFamily: 'Cairo', fontSize: 13)),
      const SizedBox(height: 5),
      Text(available.toStringAsFixed(2), style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900)),
      const Divider(color: Colors.white24, height: 30),
      Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
        _miniInfo("تأمين عهدة", locked.toStringAsFixed(1), Colors.orangeAccent),
        _miniInfo("سقف المديونية", limit.toStringAsFixed(1), Colors.cyanAccent),
      ])
    ]),
  );

  Widget _miniInfo(String label, String value, Color valColor) => Column(children: [
    Text(label, style: const TextStyle(color: Colors.white60, fontSize: 10, fontFamily: 'Cairo')),
    Text(value, style: TextStyle(color: valColor, fontWeight: FontWeight.w900, fontSize: 16)),
  ]);

  // بناء السجل المدمج (فواتير + لوجز)
  Widget _buildCombinedHistory(String? uid) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('pendingInvoices')
          .where('driverId', isEqualTo: uid)
          .where('status', isEqualTo: 'ready_for_payment')
          .snapshots(),
      builder: (context, pendingSnap) {
        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('walletLogs')
              .where('driverId', isEqualTo: uid)
              .orderBy('timestamp', descending: true)
              .limit(15)
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
              return Container(height: 150, alignment: Alignment.center, child: Text("سجل العهدة فارغ", style: TextStyle(fontFamily: 'Cairo', color: Colors.grey[400])));
            }

            return ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: allItems.length,
              itemBuilder: (context, index) {
                var item = allItems[index];
                bool isInvoice = item['isInvoice'] ?? false;
                double amount = _toDouble(item['amount']);

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: BorderSide(color: isInvoice ? Colors.orange : Colors.grey[100]!)),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: isInvoice ? Colors.orange[50] : Colors.blueGrey[50],
                      child: Icon(isInvoice ? Icons.qr_code_scanner : Icons.swap_vert, color: isInvoice ? Colors.orange : Colors.blueGrey, size: 20),
                    ),
                    title: Text(isInvoice ? "رابط تفعيل نقاط الأمان" : _getLogTitle(item['type'], amount),
                        style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 13)),
                    subtitle: Text(isInvoice ? "اضغط لإتمام العملية" : "تحديث تلقائي للنظام", style: const TextStyle(fontFamily: 'Cairo', fontSize: 10)),
                    trailing: isInvoice 
                      ? ElevatedButton(
                          onPressed: () => _launchPaymentUrl(item['paymentUrl']),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.orange[800], shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                          child: const Text("دفع", style: TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 11)),
                        )
                      : Text("${amount > 0 ? '+' : ''}${amount.toStringAsFixed(1)}", 
                          style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w900, color: amount > 0 ? Colors.green : Colors.red)),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  String _getLogTitle(String? type, double amount) {
    if (type == 'ORDER_REVENUE') return "تسوية أرباح شحنة";
    if (type == 'insurance_lock') return "تأمين عهدة (محجوز)";
    if (type == 'operational_fee') return "شحن نقاط أمان";
    return amount > 0 ? "إيداع نقاط" : "تخصيص عهدة";
  }

  Widget _actionBtn(IconData icon, String label, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(15),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.grey[200]!)),
        child: Column(children: [
            Icon(icon, color: color, size: 24.sp),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w900, fontSize: 11)),
        ]),
      ),
    );
  }

  Widget _sectionHeader(String title) => Padding(padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
    child: Align(alignment: Alignment.centerRight, child: Text(title, style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w900, fontSize: 14, color: Colors.black87))));

  Widget _buildLegalDisclaimer() => Padding(padding: const EdgeInsets.fromLTRB(30, 20, 30, 30),
    child: Text("إدارة العهدة: يتم تخصيص نقاط أمان تعادل قيمة الشحنة لضمان النقل، وتُعاد لرصيدك المتاح فور تأكيد الاستلام من قبل التاجر أو العميل.",
      textAlign: TextAlign.center, style: TextStyle(fontFamily: 'Cairo', fontSize: 8.5.sp, color: Colors.grey[500], height: 1.6)));

  void _showLoading(BuildContext context) => showDialog(context: context, barrierDismissible: false, builder: (c) => const Center(child: CircularProgressIndicator(color: Colors.orange)));

  void _showInfoSheet(BuildContext context, String t, String m) => showModalBottomSheet(context: context, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
    builder: (c) => SafeArea(child: Padding(padding: const EdgeInsets.all(25), child: Column(mainAxisSize: MainAxisSize.min, children: [
      Text(t, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, fontFamily: 'Cairo')),
      const SizedBox(height: 10),
      Text(m, textAlign: TextAlign.center, style: const TextStyle(fontFamily: 'Cairo', color: Colors.grey, fontSize: 13)),
      const SizedBox(height: 25),
      SizedBox(width: double.infinity, child: ElevatedButton(onPressed: () => Navigator.pop(context), child: const Text("حسناً", style: TextStyle(fontFamily: 'Cairo'))))
    ]))));

  void _launchPaymentUrl(String? url) async {
    if (url == null || url.isEmpty) return;
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) debugPrint("Could not launch $url");
  }

  void _showChargePicker(BuildContext context) {
    showModalBottomSheet(context: context, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (c) => SafeArea(child: Container(padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 15),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text("تعبئة نقاط الأمان", style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w900, fontSize: 16)),
          const SizedBox(height: 10),
          const Text("اختر القيمة لتفعيل حسابك واستلام الشحنات", style: TextStyle(fontFamily: 'Cairo', fontSize: 11, color: Colors.grey)),
          const SizedBox(height: 20),
          Wrap(spacing: 12, runSpacing: 12, alignment: WrapAlignment.center, children: [100, 200, 500, 1000].map((a) => ActionChip(
            label: Text("$a نقطة", style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
            onPressed: () { Navigator.pop(context); _processCharge(context, a.toDouble()); }
          )).toList()),
          const SizedBox(height: 20),
        ]))));
  }

  void _showWithdrawDialog(BuildContext context, double current) {
    final ctrl = TextEditingController();
    showDialog(context: context, builder: (c) => AlertDialog(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text("تسوية رصيد الأمانات", style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 16), textAlign: TextAlign.center),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text("الرصيد المتاح حالياً: ${current.toStringAsFixed(2)} ج.م", style: const TextStyle(fontSize: 12, color: Colors.blueGrey, fontFamily: 'Cairo')),
        const SizedBox(height: 15),
        TextField(controller: ctrl, keyboardType: TextInputType.number, 
          decoration: InputDecoration(hintText: "أدخل المبلغ المطلوب تسويته", hintStyle: const TextStyle(fontSize: 12, fontFamily: 'Cairo'),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)))),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("إلغاء", style: TextStyle(fontFamily: 'Cairo', color: Colors.grey))),
        ElevatedButton(onPressed: () {
            double? amount = double.tryParse(ctrl.text);
            if (amount != null && amount > 0 && amount <= current) { Navigator.pop(context); _executeWithdrawal(context, amount); }
            else { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("القيمة المدخلة غير صحيحة أو تتجاوز الرصيد"))); }
          }, child: const Text("تأكيد التسوية", style: TextStyle(fontFamily: 'Cairo')))
      ]));
  }
}

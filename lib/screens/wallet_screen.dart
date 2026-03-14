import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:sizer/sizer.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';

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
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
              Navigator.of(context).pushReplacementNamed('/free_home');
            }
          },
        ),
        title: const Text("إدارة العهدة ونقاط الأمان",
            style: TextStyle(fontWeight: FontWeight.w900, fontFamily: 'Cairo', fontSize: 18)),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black,
      ),
      body: SafeArea(
        child: StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance.collection('freeDrivers').doc(uid).snapshots(),
          builder: (context, driverSnap) {
            if (!driverSnap.hasData) return const Center(child: CircularProgressIndicator(color: Colors.orange));
            
            var userData = driverSnap.data!.data() as Map<String, dynamic>?;

            double walletBalance = _toDouble(userData?['walletBalance']);
            double creditLimit = _toDouble(userData?['creditLimit']);
            double lockedInsurance = _toDouble(userData?['insurance_points']);

            return SingleChildScrollView(
              padding: EdgeInsets.only(bottom: 120.sp), // مسافة للسيف أريا السفلية
              child: Column(
                children: [
                  _buildMainAssetCard(walletBalance, creditLimit, lockedInsurance),

                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      decoration: BoxDecoration(color: Colors.blueGrey[50], borderRadius: BorderRadius.circular(30)),
                      child: Text("إجمالي الأمانات بالذمة: ${(walletBalance + lockedInsurance).toStringAsFixed(2)} ج.م",
                        style: TextStyle(fontSize: 10.sp, fontWeight: FontWeight.bold, fontFamily: 'Cairo', color: Colors.blueGrey[800])),
                    ),
                  ),

                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                    child: Row(
                      children: [
                        Expanded(child: _actionBtn(Icons.add_moderator_outlined, "تعبئة نقاط", const Color(0xFF2E7D32), () => _showChargePicker(context))),
                        const SizedBox(width: 15),
                        Expanded(child: _actionBtn(Icons.account_balance_outlined, "طلب تسوية", const Color(0xFF37474F), () => _showWithdrawDialog(context, walletBalance))),
                      ],
                    ),
                  ),

                  _sectionHeader("سجل العمليات والروابط"),

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
      ),
    );
  }

  // --- كارت الأرصدة المطور ---
  Widget _buildMainAssetCard(double available, double limit, double locked) => Container(
    margin: const EdgeInsets.all(20),
    padding: const EdgeInsets.all(25),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xFF1E293B), Color(0xFF334155)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(32),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 20, offset: const Offset(0, 10))],
    ),
    child: Column(children: [
      const Text("نقاط الأمان المتاحة", style: TextStyle(color: Colors.white70, fontFamily: 'Cairo', fontSize: 14)),
      const SizedBox(height: 8),
      Text(available.toStringAsFixed(2), style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w900, letterSpacing: 1.2)),
      const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Divider(color: Colors.white10, height: 1),
      ),
      Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
        _miniInfo("تأمين عهدة", locked.toStringAsFixed(1), Colors.orangeAccent),
        _miniInfo("سقف المديونية", limit.toStringAsFixed(1), Colors.cyanAccent),
      ])
    ]),
  );

  Widget _miniInfo(String label, String value, Color valColor) => Column(children: [
    Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11, fontFamily: 'Cairo')),
    const SizedBox(height: 4),
    Text(value, style: TextStyle(color: valColor, fontWeight: FontWeight.w900, fontSize: 18)),
  ]);

  // بناء السجل المدمج مع فلترة الروابط (6 ساعات)
  Widget _buildCombinedHistory(String? uid) {
    return StreamBuilder<QuerySnapshot>(
      // جلب الروابط الجاهزة للدفع فقط
      stream: FirebaseFirestore.instance.collection('pendingInvoices')
          .where('driverId', isEqualTo: uid)
          .where('status', isEqualTo: 'ready_for_payment')
          .snapshots(),
      builder: (context, pendingSnap) {
        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('walletLogs')
              .where('driverId', isEqualTo: uid)
              .orderBy('timestamp', descending: true)
              .limit(10)
              .snapshots(),
          builder: (context, logSnap) {
            List<Map<String, dynamic>> allItems = [];

            if (pendingSnap.hasData) {
              DateTime now = DateTime.now();
              for (var doc in pendingSnap.data!.docs) {
                var d = doc.data() as Map<String, dynamic>;
                
                // --- 🛡️ منطق حماية الرابط (6 ساعات) ---
                if (d['createdAt'] != null) {
                  DateTime createdAt = (d['createdAt'] as Timestamp).toDate();
                  if (now.difference(createdAt).inHours < 6) {
                    d['isInvoice'] = true;
                    allItems.add(d);
                  }
                }
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
                padding: const EdgeInsets.symmetric(vertical: 40),
                alignment: Alignment.center,
                child: Column(
                  children: [
                    Icon(Icons.history_toggle_off, size: 40.sp, color: Colors.grey[300]),
                    const SizedBox(height: 10),
                    Text("لا توجد عمليات نشطة حالياً", style: TextStyle(fontFamily: 'Cairo', color: Colors.grey[400])),
                  ],
                ),
              );
            }

            return ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: allItems.length,
              itemBuilder: (context, index) {
                var item = allItems[index];
                bool isInvoice = item['isInvoice'] ?? false;
                double amount = _toDouble(item['amount']);

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: isInvoice ? Colors.orange.withOpacity(0.3) : Colors.grey[100]!),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10)],
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
                    leading: CircleAvatar(
                      radius: 22,
                      backgroundColor: isInvoice ? Colors.orange[50] : Colors.blueGrey[50],
                      child: Icon(isInvoice ? Icons.bolt : Icons.sync_alt_rounded, 
                          color: isInvoice ? Colors.orange[800] : Colors.blueGrey[600], size: 22),
                    ),
                    title: Text(isInvoice ? "رابط شحن نقاط الأمان" : _getLogTitle(item['type'], amount),
                        style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 13.5)),
                    subtitle: Text(isInvoice ? "صالح لمدة محدودة" : "تحديث نظام آلي", 
                        style: TextStyle(fontFamily: 'Cairo', fontSize: 10, color: isInvoice ? Colors.orange[900] : Colors.grey)),
                    trailing: isInvoice
                      ? ElevatedButton(
                          onPressed: () => _launchPaymentUrl(item['paymentUrl']),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange[900],
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(horizontal: 15)
                          ),
                          child: const Text("سداد", style: TextStyle(color: Colors.white, fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                        )
                      : Text("${amount > 0 ? '+' : ''}${amount.toStringAsFixed(1)}",
                          style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w900, fontSize: 14.sp, color: amount > 0 ? Colors.green[700] : Colors.red[700])),
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
    if (type == 'insurance_lock') return "حجز تأمين عهدة";
    if (type == 'operational_fee') return "شحن نقاط أمان";
    return amount > 0 ? "إيداع نقاط" : "تخصيص عهدة";
  }

  Widget _actionBtn(IconData icon, String label, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 22),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 15, offset: const Offset(0, 8))],
          border: Border.all(color: Colors.white),
        ),
        child: Column(children: [
            Icon(icon, color: color, size: 28.sp),
            const SizedBox(height: 10),
            Text(label, style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w900, fontSize: 12.sp, color: color)),
        ]),
      ),
    );
  }

  Widget _sectionHeader(String title) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 25, 20, 15),
    child: Align(
      alignment: Alignment.centerRight,
      child: Text(title, style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w900, fontSize: 16, color: Color(0xFF1E293B)))
    ),
  );

  Widget _buildLegalDisclaimer() => Padding(
    padding: const EdgeInsets.all(35),
    child: Text(
      "إدارة العهدة: يتم تخصيص نقاط أمان تعادل قيمة الشحنة لضمان النقل الآمن، وتُعاد لرصيدك المتاح فور تأكيد استلام الأمانات من قبل العميل.",
      textAlign: TextAlign.center,
      style: TextStyle(fontFamily: 'Cairo', fontSize: 9.sp, color: Colors.grey[500], height: 1.6),
    ),
  );

  void _showLoading(BuildContext context) => showDialog(context: context, barrierDismissible: false, builder: (c) => const Center(child: CircularProgressIndicator(color: Colors.orange)));

  void _showInfoSheet(BuildContext context, String t, String m) => showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
    builder: (c) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10))),
            const SizedBox(height: 25),
            Text(t, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20, fontFamily: 'Cairo')),
            const SizedBox(height: 12),
            Text(m, textAlign: TextAlign.center, style: const TextStyle(fontFamily: 'Cairo', color: Colors.blueGrey, fontSize: 14, height: 1.5)),
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E293B), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                onPressed: () => Navigator.pop(context), 
                child: const Text("فهمت ذلك", style: TextStyle(fontFamily: 'Cairo', color: Colors.white, fontWeight: FontWeight.bold))
              ),
            )
          ],
        ),
      ),
    ),
  );

  void _launchPaymentUrl(String? url) async {
    if (url == null || url.isEmpty) return;
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) debugPrint("Could not launch $url");
  }

  void _showChargePicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
      builder: (c) => SafeArea(
        child: Container(
          padding: const EdgeInsets.all(30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("تعبئة نقاط الأمان", style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w900, fontSize: 18)),
              const SizedBox(height: 10),
              const Text("اختر القيمة المطلوبة لشحن العهدة وتفعيل حسابك", style: TextStyle(fontFamily: 'Cairo', fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 25),
              Wrap(
                spacing: 15,
                runSpacing: 15,
                alignment: WrapAlignment.center,
                children: [100, 200, 500, 1000].map((a) => InkWell(
                  onTap: () { Navigator.pop(context); _processCharge(context, a.toDouble()); },
                  child: Container(
                    width: 35.w,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    decoration: BoxDecoration(
                      color: Colors.orange[50],
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(color: Colors.orange[200]!),
                    ),
                    child: Center(child: Text("$a نقطة", style: const TextStyle(fontWeight: FontWeight.w900, fontFamily: 'Cairo', color: Colors.orange))),
                  ),
                )).toList(),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  void _showWithdrawDialog(BuildContext context, double current) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        title: const Text("تسوية رصيد الأمانات", style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 18), textAlign: TextAlign.center),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("الرصيد القابل للتسوية: ${current.toStringAsFixed(2)} ج.م", style: const TextStyle(fontSize: 13, color: Colors.blueGrey, fontFamily: 'Cairo')),
            const SizedBox(height: 20),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              decoration: InputDecoration(
                hintText: "أدخل المبلغ",
                hintStyle: const TextStyle(fontSize: 14, fontFamily: 'Cairo', fontWeight: FontWeight.normal),
                filled: true,
                fillColor: Colors.grey[100],
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
              ),
            ),
          ],
        ),
        actionsPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
        actions: [
          Row(
            children: [
              Expanded(child: TextButton(onPressed: () => Navigator.pop(context), child: const Text("إلغاء", style: TextStyle(fontFamily: 'Cairo', color: Colors.red)))),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E293B), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  onPressed: () {
                    double? amount = double.tryParse(ctrl.text);
                    if (amount != null && amount > 0 && amount <= current) {
                      Navigator.pop(context);
                      _executeWithdrawal(context, amount);
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("القيمة المدخلة غير صحيحة")));
                    }
                  },
                  child: const Text("تأكيد", style: TextStyle(fontFamily: 'Cairo', color: Colors.white)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}


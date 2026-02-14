import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:sizer/sizer.dart';
import 'package:url_launcher/url_launcher.dart';

class WalletScreen extends StatelessWidget {
  const WalletScreen({super.key});

  Future<void> _processCharge(BuildContext context, double amount) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    _showLoading(context);
    try {
      await FirebaseFirestore.instance.collection('pendingInvoices').add({
        'driverId': uid,
        'amount': amount,
        'status': 'pay_now',
        'type': 'WALLET_TOPUP',
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (context.mounted) Navigator.pop(context);
      _showInfoSheet(context, "تم استلام طلبك", "جاري تجهيز الرابط، سيظهر في السجل خلال ثوانٍ.");
    } catch (e) {
      if (context.mounted) Navigator.pop(context);
      _showInfoSheet(context, "خطأ", "فشل الاتصال بالخادم.");
    }
  }

  Future<void> _executeWithdrawal(BuildContext context, double amount) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    _showLoading(context);
    try {
      await FirebaseFirestore.instance.collection('withdrawRequests').add({
        'driverId': uid,
        'amount': amount,
        'status': 'pending',
        'type': 'CASH_OUT',
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (context.mounted) {
        Navigator.pop(context);
        _showInfoSheet(context, "تم إرسال الطلب", "سيتم المراجعة والتحويل خلال 24 ساعة.");
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
        title: const Text("المحفظة الذكية", style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Cairo', fontSize: 20)),
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
          double finalLimit = (userData?['creditLimit'] ?? 50.0).toDouble();

          return Column(
            children: [
              _buildAdvancedBalanceCard(walletBalance, finalLimit, walletBalance + finalLimit),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text("الرصيد القابل للسحب: ${walletBalance.toStringAsFixed(2)} ج.م",
                  style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w900, fontFamily: 'Cairo', color: Colors.blueGrey[800])),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                child: Row(
                  children: [
                    Expanded(child: _actionBtn(Icons.add_card, "شحن رصيد", Colors.green[700]!, () => _showChargePicker(context))),
                    const SizedBox(width: 15),
                    Expanded(child: _actionBtn(Icons.payments_outlined, "سحب كاش", Colors.blueGrey[800]!, () => _showWithdrawDialog(context, walletBalance))),
                  ],
                ),
              ),
              _sectionHeader("سجل العمليات والروابط النشطة"),
              Expanded(child: _buildCombinedHistory(uid)),
            ],
          );
        },
      ),
    );
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
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10)],
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 28.sp),
            const SizedBox(height: 10),
            Text(label, style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w900, fontSize: 14)),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 25, 20, 15),
      child: Align(
        alignment: Alignment.centerRight,
        child: Text(title, style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w900, fontSize: 18, color: Colors.black87)),
      ),
    );
  }

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
              .limit(10)
              .snapshots(),
          builder: (context, logSnap) {
            List<Map<String, dynamic>> allItems = [];

            if (pendingSnap.hasData && pendingSnap.data!.docs.isNotEmpty) {
              for (var doc in pendingSnap.data!.docs) {
                var d = doc.data() as Map<String, dynamic>;
                if (d['createdAt'] != null) {
                  DateTime createdTime = (d['createdAt'] as Timestamp).toDate();
                  if (DateTime.now().difference(createdTime).inMinutes < 120) {
                    d['isPendingLink'] = true;
                    allItems.add(d);
                  }
                }
              }
            }

            if (logSnap.hasData) {
              for (var doc in logSnap.data!.docs) {
                var d = doc.data() as Map<String, dynamic>;
                d['isPendingLink'] = false;
                allItems.add(d);
              }
            }

            if (allItems.isEmpty) {
              return Center(child: Text("لا توجد عمليات سابقة", style: TextStyle(fontFamily: 'Cairo', color: Colors.grey[400], fontSize: 13.sp)));
            }

            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 100.sp), // مسافة آمنة من الأسفل
              itemCount: allItems.length,
              itemBuilder: (context, index) {
                var item = allItems[index];
                bool isPending = item['isPendingLink'] ?? false;
                double amount = (item['amount'] ?? 0.0).toDouble();

                return Card(
                  margin: const EdgeInsets.only(bottom: 15),
                  elevation: isPending ? 4 : 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(color: isPending ? Colors.orange : Colors.grey[100]!, width: 1.5),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    leading: CircleAvatar(
                      radius: 25,
                      backgroundColor: isPending ? Colors.orange[50] : Colors.grey[50],
                      child: Icon(isPending ? Icons.link : Icons.history, 
                        color: isPending ? Colors.orange[900] : Colors.grey[600]),
                    ),
                    title: Text(isPending ? "رابط شحن متاح" : (amount > 0 ? "شحن رصيد" : "خصم / سحب"),
                        style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w900, fontSize: 15)),
                    subtitle: Text(isPending ? "صالح لمدة ساعتين" : "تمت العملية بنجاح", style: const TextStyle(fontFamily: 'Cairo', fontSize: 11)),
                    trailing: isPending 
                      ? ElevatedButton(
                          onPressed: () => _launchPaymentUrl(item['paymentUrl']),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.orange[900], shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                          child: const Text("ادفع", style: TextStyle(color: Colors.white, fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                        )
                      : Text("${amount.toStringAsFixed(1)} ج.م", 
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

  void _launchPaymentUrl(String? url) async {
    if (url == null || url.isEmpty) return;
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Widget _buildAdvancedBalanceCard(double w, double c, double t) => Container(
    margin: const EdgeInsets.all(20), padding: const EdgeInsets.all(30),
    decoration: BoxDecoration(
      gradient: const LinearGradient(colors: [Color(0xFF0F172A), Color(0xFF334155)], begin: Alignment.topLeft, end: Alignment.bottomRight),
      borderRadius: BorderRadius.circular(35),
      boxShadow: [BoxShadow(color: Colors.blueGrey.withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 10))]
    ),
    child: Column(children: [
      const Text("إجمالي المحفظة المتوفر", style: TextStyle(color: Colors.white70, fontFamily: 'Cairo', fontSize: 16)),
      const SizedBox(height: 8),
      Text("${t.toStringAsFixed(2)} ج.م", style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w900)),
      const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Divider(color: Colors.white12, thickness: 1),
      ),
      Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
        _miniInfo("كاش متاح", "${w.toStringAsFixed(1)}"),
        _miniInfo("حد المديونية", "${c.toStringAsFixed(1)}"),
      ])
    ]),
  );

  Widget _miniInfo(String l, String v) => Column(children: [
    Text(l, style: const TextStyle(color: Colors.white60, fontSize: 13, fontFamily: 'Cairo')),
    const SizedBox(height: 4),
    Text(v, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18)),
  ]);

  void _showLoading(BuildContext context) => showDialog(context: context, barrierDismissible: false, builder: (c) => const Center(child: CircularProgressIndicator(color: Colors.orange)));
  
  void _showInfoSheet(BuildContext context, String t, String m) => showModalBottomSheet(
    context: context, 
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
    builder: (c) => SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(25, 15, 25, 25), 
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 45, height: 5, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10))),
          const SizedBox(height: 25),
          Text(t, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20, fontFamily: 'Cairo')),
          const SizedBox(height: 12),
          Text(m, textAlign: TextAlign.center, style: const TextStyle(fontFamily: 'Cairo', color: Colors.grey, fontSize: 15)),
          const SizedBox(height: 30),
          SizedBox(
            width: double.infinity, 
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.black87, padding: const EdgeInsets.symmetric(vertical: 15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
              onPressed: () => Navigator.pop(context), 
              child: const Text("فهمت", style: TextStyle(fontFamily: 'Cairo', color: Colors.white, fontWeight: FontWeight.bold))
            )
          )
        ])
      ),
    )
  );

  void _showChargePicker(BuildContext context) {
    showModalBottomSheet(
      context: context, 
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(25),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 45, height: 5, margin: const EdgeInsets.only(bottom: 20), decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10))),
              Text("اختر مبلغ الشحن", style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w900, fontSize: 18)),
              const SizedBox(height: 25),
              Wrap(
                spacing: 15, runSpacing: 15, alignment: WrapAlignment.center,
                children: [50, 100, 200, 500].map((a) => InkWell(
                  onTap: () { Navigator.pop(context); _processCharge(context, a.toDouble()); },
                  child: Container(
                    width: 38.w, padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(color: Colors.orange[50], borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.orange[100]!)),
                    child: Column(children: [
                      Icon(Icons.flash_on, color: Colors.orange[900]),
                      const SizedBox(height: 8),
                      Text("$a ج.م", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20, fontFamily: 'Cairo')),
                    ]),
                  ),
                )).toList()
              ),
              const SizedBox(height: 20),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
        title: const Text("طلب سحب كاش", style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold), textAlign: TextAlign.center),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("الرصيد المتاح حالياً: $current ج.م", style: const TextStyle(fontSize: 13, color: Colors.grey, fontFamily: 'Cairo')),
            const SizedBox(height: 15),
            TextField(
              controller: ctrl, 
              keyboardType: TextInputType.number, 
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
              decoration: InputDecoration(
                hintText: "المبلغ",
                filled: true, fillColor: Colors.grey[100],
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none)
              ),
            ),
          ],
        ),
        actionsPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 15),
        actions: [
          Row(children: [
            Expanded(child: TextButton(onPressed: () => Navigator.pop(context), child: const Text("إلغاء", style: TextStyle(fontFamily: 'Cairo', color: Colors.red)))),
            Expanded(child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey[800], shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              onPressed: () {
                double? amount = double.tryParse(ctrl.text);
                if (amount != null && amount > 0 && amount <= current) {
                  Navigator.pop(context);
                  _executeWithdrawal(context, amount);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("المبلغ غير متاح أو غير صحيح")));
                }
              },
              child: const Text("سحب", style: TextStyle(fontFamily: 'Cairo', color: Colors.white)),
            )),
          ])
        ],
      )
    );
  }
}

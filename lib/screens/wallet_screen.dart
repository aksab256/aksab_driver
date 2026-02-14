// lib/screens/wallet_screen.dart
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
      _showInfoSheet(context, "تم استلام طلبك", "جاري تجهيز الرابط، سيظهر هنا خلال ثوانٍ.");
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
        title: const Text("المحفظة الذكية", style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
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
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text("الرصيد القابل للسحب: ${walletBalance.toStringAsFixed(2)} ج.م",
                  style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.bold, fontFamily: 'Cairo', color: Colors.blueGrey[800])),
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

  // ✅ تم إصلاح Border.all هنا ليتوافق مع متطلبات BoxDecoration
  Widget _actionBtn(IconData icon, String label, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 15),
        decoration: BoxDecoration(
          color: Colors.white, 
          borderRadius: BorderRadius.circular(15), 
          border: Border.all(color: Colors.grey[200]!), // الإصلاح هنا
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24.sp),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
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
        child: Text(title, style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 16)),
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
              return Center(child: Text("لا توجد عمليات سابقة", style: TextStyle(fontFamily: 'Cairo', color: Colors.grey[400])));
            }

            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 30),
              itemCount: allItems.length,
              itemBuilder: (context, index) {
                var item = allItems[index];
                bool isPending = item['isPendingLink'] ?? false;
                double amount = (item['amount'] ?? 0.0).toDouble();

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  elevation: isPending ? 3 : 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                    side: BorderSide(color: isPending ? Colors.orange : Colors.grey[200]!),
                  ),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: isPending ? Colors.orange[50] : Colors.grey[50],
                      child: Icon(isPending ? Icons.link : Icons.history, 
                        color: isPending ? Colors.orange[900] : Colors.grey),
                    ),
                    title: Text(isPending ? "رابط شحن متاح" : (amount > 0 ? "شحن رصيد" : "خصم / سحب"),
                        style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 14)),
                    trailing: isPending 
                      ? ElevatedButton(
                          onPressed: () => _launchPaymentUrl(item['paymentUrl']),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.orange[900]),
                          child: const Text("ادفع", style: TextStyle(color: Colors.white, fontFamily: 'Cairo')),
                        )
                      : Text("${amount.toStringAsFixed(2)} ج.م", 
                          style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, color: amount > 0 ? Colors.green : Colors.red)),
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
    margin: const EdgeInsets.all(20), padding: const EdgeInsets.all(25),
    decoration: BoxDecoration(
      gradient: const LinearGradient(colors: [Color(0xFF1a1a1a), Color(0xFF3a3a3a)], begin: Alignment.topLeft, end: Alignment.bottomRight),
      borderRadius: BorderRadius.circular(30),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 10, offset: const Offset(0, 5))]
    ),
    child: Column(children: [
      const Text("إجمالي المحفظة المتوفر", style: TextStyle(color: Colors.white70, fontFamily: 'Cairo', fontSize: 14)),
      const SizedBox(height: 5),
      Text("${t.toStringAsFixed(2)} ج.م", style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)),
      const Divider(color: Colors.white24, height: 30),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        _miniInfo("كاش", "${w.toStringAsFixed(1)}"),
        _miniInfo("مديونية", "${c.toStringAsFixed(1)}"),
      ])
    ]),
  );

  Widget _miniInfo(String l, String v) => Column(children: [
    Text(l, style: const TextStyle(color: Colors.white60, fontSize: 12, fontFamily: 'Cairo')),
    Text(v, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
  ]);

  void _showLoading(BuildContext context) => showDialog(context: context, barrierDismissible: false, builder: (c) => const Center(child: CircularProgressIndicator(color: Colors.orange)));
  
  void _showInfoSheet(BuildContext context, String t, String m) => showModalBottomSheet(
    context: context, 
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (c) => Padding(padding: const EdgeInsets.all(25), child: Column(mainAxisSize: MainAxisSize.min, children: [
      Text(t, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, fontFamily: 'Cairo')),
      const SizedBox(height: 10),
      Text(m, textAlign: TextAlign.center, style: const TextStyle(fontFamily: 'Cairo', color: Colors.grey)),
      const SizedBox(height: 20),
      SizedBox(width: double.infinity, child: ElevatedButton(onPressed: () => Navigator.pop(context), child: const Text("تم", style: TextStyle(fontFamily: 'Cairo'))))
    ]))
  );

  void _showChargePicker(BuildContext context) {
    showModalBottomSheet(
      context: context, 
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (c) => Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Wrap(children: [50, 100, 200, 500].map((a) => ListTile(
          leading: const Icon(Icons.add_circle_outline, color: Colors.green),
          title: Text("شحن مبلغ $a ج.م", style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
          onTap: () { Navigator.pop(context); _processCharge(context, a.toDouble()); }
        )).toList()),
      )
    );
  }

  void _showWithdrawDialog(BuildContext context, double current) {
    final ctrl = TextEditingController();
    showDialog(
      context: context, 
      builder: (c) => AlertDialog(
        title: const Text("طلب سحب كاش", style: TextStyle(fontFamily: 'Cairo')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("الرصيد المتاح: $current ج.م", style: const TextStyle(fontSize: 12, color: Colors.grey)),
            TextField(controller: ctrl, keyboardType: TextInputType.number, decoration: const InputDecoration(hintText: "أدخل المبلغ")),
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
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("تأكد من المبلغ المكتوب")));
              }
            },
            child: const Text("سحب", style: TextStyle(fontFamily: 'Cairo')),
          )
        ],
      )
    );
  }
}

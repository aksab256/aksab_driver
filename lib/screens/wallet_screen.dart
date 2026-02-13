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
      _showInfoSheet(context, "خطأ", "فشل الاتصال.");
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
        _showInfoSheet(context, "خطأ", "حاول مجدداً.");
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
        centerTitle: true, backgroundColor: Colors.white, elevation: 0,
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('freeDrivers').doc(uid).snapshots(),
        builder: (context, driverSnap) {
          if (!driverSnap.hasData) return const Center(child: CircularProgressIndicator());
          var userData = driverSnap.data!.data() as Map<String, dynamic>?;
          double walletBalance = (userData?['walletBalance'] ?? 0.0).toDouble();
          double finalLimit = (userData?['creditLimit'] ?? 50.0).toDouble();

          return Column(
            children: [
              _buildAdvancedBalanceCard(walletBalance, finalLimit, walletBalance + finalLimit),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text("الرصيد القابل للسحب: ${walletBalance.toStringAsFixed(2)} ج.م",
                  style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
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
              _sectionHeader("سجل العمليات"),
              Expanded(child: _buildCombinedHistory(uid)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildCombinedHistory(String? uid) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('pendingInvoices')
          .where('driverId', isEqualTo: uid)
          .where('status', isEqualTo: 'ready_for_payment')
          .orderBy('createdAt', descending: true).limit(1).snapshots(),
      builder: (context, pendingSnap) {
        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('walletLogs')
              .where('driverId', isEqualTo: uid)
              .orderBy('timestamp', descending: true).limit(10).snapshots(),
          builder: (context, logSnap) {
            List<Map<String, dynamic>> allItems = [];
            if (pendingSnap.hasData && pendingSnap.data!.docs.isNotEmpty) {
              var d = pendingSnap.data!.docs.first.data() as Map<String, dynamic>;
              if (d['createdAt'] != null) {
                DateTime createdTime = (d['createdAt'] as Timestamp).toDate();
                if (DateTime.now().difference(createdTime).inMinutes < 120) {
                  d['isPendingLink'] = true;
                  allItems.add(d);
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
            return ListView.builder(
              padding: const EdgeInsets.only(left: 20, right: 20, bottom: 20), // ✅ تم إصلاح الخطأ هنا
              itemCount: allItems.length,
              itemBuilder: (context, index) {
                var item = allItems[index];
                bool isPending = item['isPendingLink'] ?? false;
                double amount = (item['amount'] ?? 0.0).toDouble();
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    leading: Icon(isPending ? Icons.link : Icons.history, color: isPending ? Colors.orange : Colors.grey),
                    title: Text(isPending ? "رابط دفع نشط" : (amount > 0 ? "شحن" : "خصم"), style: const TextStyle(fontFamily: 'Cairo')),
                    trailing: isPending 
                      ? ElevatedButton(onPressed: () => launchUrl(Uri.parse(item['paymentUrl'])), child: const Text("ادفع"))
                      : Text("${amount.toStringAsFixed(2)}"),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  // --- دوال مساعدة مختصرة للـ UI ---
  Widget _buildAdvancedBalanceCard(double w, double c, double t) => Container(
    margin: const EdgeInsets.all(20), padding: const EdgeInsets.all(25),
    decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF1a1a1a), Color(0xFF3a3a3a)]), borderRadius: BorderRadius.circular(30)),
    child: Column(children: [
      const Text("إجمالي الرصيد", style: TextStyle(color: Colors.white70, fontFamily: 'Cairo')),
      Text("${t.toStringAsFixed(2)} ج.م", style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
    ]),
  );

  void _showLoading(BuildContext context) => showDialog(context: context, builder: (c) => const Center(child: CircularProgressIndicator()));
  
  void _showInfoSheet(BuildContext context, String t, String m) => showModalBottomSheet(context: context, builder: (c) => Padding(padding: const EdgeInsets.all(20), child: Text("$t\n$m", textAlign: TextAlign.center, style: const TextStyle(fontFamily: 'Cairo'))));

  void _showChargePicker(BuildContext context) {
    showModalBottomSheet(context: context, builder: (c) => Wrap(children: [50, 100, 200].map((a) => ListTile(title: Text("$a ج.م"), onTap: () { Navigator.pop(context); _processCharge(context, a.toDouble()); })).toList()));
  }

  void _showWithdrawDialog(BuildContext context, double current) {
    final ctrl = TextEditingController();
    showDialog(context: context, builder: (c) => AlertDialog(title: const Text("سحب"), content: TextField(controller: ctrl, keyboardType: TextInputType.number), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("إلغاء")), TextButton(onPressed: () { Navigator.pop(context); _executeWithdrawal(context, double.parse(ctrl.text)); }, child: const Text("سحب"))]));
  }

  Widget _sectionHeader(String t) => Padding(padding: const EdgeInsets.all(20), child: Text(t, style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Cairo')));

  Widget _actionBtn(IconData i, String l, Color c, VoidCallback o) => ElevatedButton.icon(onPressed: o, icon: Icon(i), label: Text(l, style: const TextStyle(fontFamily: 'Cairo')), style: ElevatedButton.styleFrom(backgroundColor: c, foregroundColor: Colors.white));
}

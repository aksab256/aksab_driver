import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:sizer/sizer.dart';
import 'package:url_launcher/url_launcher.dart';

class WalletScreen extends StatelessWidget {
  const WalletScreen({super.key});

  // ✅ طلب الشحن وإرسال البيانات للسيرفر
  Future<void> _processCharge(BuildContext context, double amount) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator(color: Colors.orange)),
    );

    try {
      // 1. إرسال الطلب للسيرفر
      await FirebaseFirestore.instance.collection('pendingInvoices').add({
        'driverId': uid,
        'amount': amount,
        'status': 'pay_now',
        'type': 'WALLET_TOPUP',
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (!context.mounted) return;
      Navigator.pop(context); // إغلاق اللودينج

      // 2. إظهار رسالة توجيهية للمندوب
      _showInfoSheet(context, "تم استلام طلبك", "جاري تجهيز رابط الدفع. يمكنك الضغط على 'ادفع الآن' من سجل العمليات بالأسفل بمجرد ظهوره.");

    } catch (e) {
      if (context.mounted) Navigator.pop(context);
      _showInfoSheet(context, "خطأ", "فشل الاتصال، حاول مجدداً");
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      backgroundColor: const Color(0xFFFBFBFB),
      appBar: AppBar(
        title: const Text("المحفظة الذكية", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black, fontFamily: 'Cairo')),
        centerTitle: true, backgroundColor: Colors.white, elevation: 0,
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('systemConfiguration').doc('globalCreditSettings').snapshots(),
        builder: (context, globalSnap) {
          double defaultGlobalLimit = 50.0;
          if (globalSnap.hasData && globalSnap.data!.exists) {
            defaultGlobalLimit = (globalSnap.data!['defaultLimit'] ?? 50.0).toDouble();
          }

          return StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance.collection('freeDrivers').doc(uid).snapshots(),
            builder: (context, driverSnap) {
              if (!driverSnap.hasData) return const Center(child: CircularProgressIndicator());
              
              var userData = driverSnap.data!.data() as Map<String, dynamic>?;
              double walletBalance = (userData?['walletBalance'] ?? 0.0).toDouble();
              double finalLimit = (userData?['creditLimit'] ?? defaultGlobalLimit).toDouble();
              double totalBalance = walletBalance + finalLimit;

              return Column(
                children: [
                  _buildAdvancedBalanceCard(walletBalance, finalLimit, totalBalance),
                  const SizedBox(height: 10),
                  Text("⚠️ الرصيد القابل للسحب: ${walletBalance.toStringAsFixed(2)} ج.م",
                      style: TextStyle(color: Colors.grey[600], fontSize: 9.sp, fontFamily: 'Cairo')),
                  
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                    child: Row(
                      children: [
                        Expanded(child: _actionBtn(Icons.add_card, "شحن رصيد", Colors.green[700]!, () => _showAmountPicker(context))),
                        const SizedBox(width: 15),
                        Expanded(child: _actionBtn(Icons.payments_outlined, "سحب كاش", Colors.blueGrey[800]!, () {
                          _showInfoSheet(context, "طلب سحب", "سيتم مراجعة طلبك وتحويل الرصيد خلال 24 ساعة.");
                        })),
                      ],
                    ),
                  ),
                  
                  _sectionHeader("سجل العمليات الأخير"),
                  Expanded(child: _buildTransactionHistory(uid)),
                ],
              );
            },
          );
        },
      ),
    );
  }

  // ✅ السجل الذكي: يكتشف وجود رابط الدفع ويظهره للمندوب
  Widget _buildTransactionHistory(String? uid) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('pendingInvoices') // بنراقب الطلبات هنا
          .where('driverId', isEqualTo: uid)
          .where('type', isEqualTo: 'WALLET_TOPUP')
          .limit(5)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
           return const Center(child: Text("لا توجد طلبات شحن حالية", style: TextStyle(fontFamily: 'Cairo', color: Colors.grey)));
        }
        
        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: snapshot.data!.docs.length,
          itemBuilder: (context, index) {
            var data = snapshot.data!.docs[index].data() as Map<String, dynamic>;
            String status = data['status'] ?? '';
            String? paymentUrl = data['paymentUrl'];
            double amount = (data['amount'] ?? 0.0).toDouble();

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white, 
                borderRadius: BorderRadius.circular(15), 
                border: Border.all(color: status == 'ready_for_payment' ? Colors.green : Colors.grey[200]!)
              ),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: status == 'paid' ? Colors.green[50] : Colors.orange[50],
                  child: Icon(status == 'paid' ? Icons.check : Icons.hourglass_empty, color: status == 'paid' ? Colors.green : Colors.orange, size: 18),
                ),
                title: Text("شحن رصيد ${amount.toStringAsFixed(0)} ج.م", style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
                subtitle: Text(status == 'ready_for_payment' ? "الرابط جاهز للدفع" : "الحالة: $status", style: const TextStyle(fontSize: 10, fontFamily: 'Cairo')),
                trailing: status == 'ready_for_payment' && paymentUrl != null
                  ? ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                      onPressed: () => launchUrl(Uri.parse(paymentUrl), mode: LaunchMode.externalApplication),
                      child: const Text("ادفع الآن", style: TextStyle(fontFamily: 'Cairo', fontSize: 10)),
                    )
                  : Text(status == 'paid' ? "تم بنجاح" : "جاري..", style: const TextStyle(fontSize: 10, color: Colors.grey)),
              ),
            );
          },
        );
      },
    );
  }

  // --- الودجتات المساعدة (نفس التصميم الاحترافي) ---

  Widget _buildAdvancedBalanceCard(double wallet, double credit, double total) {
    return Container(
      width: double.infinity, margin: const EdgeInsets.all(20), padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF1a1a1a), Color(0xFF3a3a3a)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Column(children: [
        const Text("إجمالي رصيد التشغيل", style: TextStyle(color: Colors.white70, fontSize: 12, fontFamily: 'Cairo')),
        Text("${total.toStringAsFixed(2)} ج.م", style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)),
        const SizedBox(height: 20),
        Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
          _balanceDetail("المحفظة", wallet, Colors.greenAccent),
          _balanceDetail("الكريدت", credit, Colors.orangeAccent),
        ]),
      ]),
    );
  }

  Widget _balanceDetail(String label, double value, Color color) {
    return Column(children: [
      Text(label, style: const TextStyle(color: Colors.white54, fontSize: 10, fontFamily: 'Cairo')),
      Text("${value.toStringAsFixed(2)}", style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.bold)),
    ]);
  }

  Widget _sectionHeader(String title) {
    return Padding(padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 10),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
        const Icon(Icons.refresh, size: 18, color: Colors.grey),
      ]),
    );
  }

  Widget _actionBtn(IconData icon, String label, Color color, VoidCallback onTap) {
    return ElevatedButton.icon(
      onPressed: onTap, icon: Icon(icon, size: 18),
      label: Text(label, style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 12)),
      style: ElevatedButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
    );
  }

  void _showAmountPicker(BuildContext context) {
    showModalBottomSheet(context: context, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (context) => Container(padding: const EdgeInsets.all(25), child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text("اختر مبلغ الشحن", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
        const SizedBox(height: 20),
        Wrap(spacing: 15, runSpacing: 15, children: [50, 100, 200, 500].map((amt) => _amountOption(context, amt)).toList()),
        const SizedBox(height: 30),
      ])),
    );
  }

  Widget _amountOption(BuildContext context, int amt) {
    return InkWell(
      onTap: () { Navigator.pop(context); _processCharge(context, amt.toDouble()); },
      child: Container(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(color: Colors.orange[50], borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.orange[200]!)),
        child: Text("$amt ج.م", style: TextStyle(color: Colors.orange[900], fontWeight: FontWeight.bold)),
      ),
    );
  }

  void _showInfoSheet(BuildContext context, String title, String msg) {
    showModalBottomSheet(context: context, builder: (context) => Container(padding: const EdgeInsets.all(30), child: Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.info_outline, size: 40, color: Colors.orange), const SizedBox(height: 15), Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'Cairo')), const SizedBox(height: 10), Text(msg, textAlign: TextAlign.center, style: const TextStyle(fontFamily: 'Cairo', fontSize: 12))])));
  }
}

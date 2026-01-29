import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:sizer/sizer.dart';
import 'package:url_launcher/url_launcher.dart';

class WalletScreen extends StatelessWidget {
  const WalletScreen({super.key});

  // ✅ طلب الشحن
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
      Navigator.pop(context);
      _showInfoSheet(context, "تم استلام طلبك", "جاري تجهيز الرابط، سيظهر في السجل بالأسفل خلال ثوانٍ.");
    } catch (e) {
      Navigator.pop(context);
      _showInfoSheet(context, "خطأ", "عذراً، فشل الاتصال بالسيرفر.");
    }
  }

  // ✅ طلب سحب كاش (مع الحجز المنطقي)
  Future<void> _processWithdraw(BuildContext context, double amount, double currentWallet) async {
    if (amount > currentWallet) {
      _showInfoSheet(context, "رصيد غير كافٍ", "لا يمكنك سحب مبلغ أكبر من رصيد المحفظة الحالي.");
      return;
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    _showLoading(context);

    try {
      await FirebaseFirestore.instance.collection('withdrawRequests').add({
        'driverId': uid,
        'amount': amount,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });
      
      Navigator.pop(context);
      _showInfoSheet(context, "طلب سحب قيد المعالجة", "تم تسجيل طلبك لسحب $amount ج.م. سيتم مراجعته وتحويله خلال 24 ساعة.");
    } catch (e) {
      Navigator.pop(context);
      _showInfoSheet(context, "خطأ", "فشل إرسال الطلب، حاول مجدداً.");
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
                  
                  // ✅ تكبير وتحسين جملة الرصيد القابل للسحب
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 20),
                    child: Text(
                      "الرصيد القابل للسحب الفوري: ${walletBalance.toStringAsFixed(2)} ج.م",
                      style: TextStyle(color: Colors.blueGrey[800], fontSize: 13.sp, fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
                    ),
                  ),
                  
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    child: Row(
                      children: [
                        Expanded(child: _actionBtn(Icons.add_card, "شحن رصيد", Colors.green[700]!, () => _showAmountPicker(context, isWithdraw: false, currentWallet: walletBalance))),
                        const SizedBox(width: 15),
                        Expanded(child: _actionBtn(Icons.payments_outlined, "سحب كاش", Colors.blueGrey[800]!, () => _showAmountPicker(context, isWithdraw: true, currentWallet: walletBalance))),
                      ],
                    ),
                  ),
                  
                  _sectionHeader("سجل العمليات الأخير"),
                  Expanded(child: _buildCombinedHistory(uid)),
                ],
              );
            },
          );
        },
      ),
    );
  }

  // ✅ السجل المدمج (روابط نشطة + آخر 10 عمليات)
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
              .limit(10) // ✅ تحديد آخر 10 عمليات فقط
              .snapshots(),
          builder: (context, logSnap) {
            List<Map<String, dynamic>> allItems = [];

            // إضافة الروابط الجاهزة أولاً
            if (pendingSnap.hasData) {
              for (var doc in pendingSnap.data!.docs) {
                var d = doc.data() as Map<String, dynamic>;
                d['isPendingLink'] = true;
                allItems.add(d);
              }
            }

            // إضافة السجلات التاريخية
            if (logSnap.hasData) {
              for (var doc in logSnap.data!.docs) {
                var d = doc.data() as Map<String, dynamic>;
                d['isPendingLink'] = false;
                allItems.add(d);
              }
            }

            if (allItems.isEmpty) return const Center(child: Text("لا توجد عمليات حالية"));

            return ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: allItems.length,
              itemBuilder: (context, index) {
                var item = allItems[index];
                bool isPending = item['isPendingLink'] ?? false;
                double amount = (item['amount'] ?? 0.0).toDouble();

                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: isPending ? Colors.green[50] : Colors.white,
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: isPending ? Colors.green : Colors.grey[100]!),
                  ),
                  child: ListTile(
                    leading: Icon(isPending ? Icons.bolt : Icons.history, color: isPending ? Colors.green : Colors.grey),
                    title: Text(isPending ? "رابط شحن جاهز" : (amount > 0 ? "شحن رصيد" : "خصم عمولة"),
                        style: const TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.bold)),
                    subtitle: Text(isPending ? "اضغط للدفع الآن" : _formatTimestamp(item['timestamp']),
                        style: const TextStyle(fontFamily: 'Cairo', fontSize: 10)),
                    trailing: isPending
                        ? ElevatedButton(
                            onPressed: () => launchUrl(Uri.parse(item['paymentUrl']), mode: LaunchMode.externalApplication),
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.green, padding: EdgeInsets.zero),
                            child: const Text("ادفع", style: TextStyle(fontSize: 10, color: Colors.white)),
                          )
                        : Text("${amount.toStringAsFixed(2)} ج.م", 
                            style: TextStyle(fontWeight: FontWeight.bold, color: amount > 0 ? Colors.green : Colors.red)),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  // --- المساعدات الودجت ---

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

  void _showAmountPicker(BuildContext context, {required bool isWithdraw, required double currentWallet}) {
    showModalBottomSheet(context: context, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (context) => Container(padding: const EdgeInsets.all(25), child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(isWithdraw ? "تحديد مبلغ السحب" : "اختر مبلغ الشحن", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
        const SizedBox(height: 20),
        Wrap(spacing: 15, runSpacing: 15, children: [50, 100, 200, 500].map((amt) {
          return InkWell(
            onTap: () {
              Navigator.pop(context);
              if (isWithdraw) {
                _processWithdraw(context, amt.toDouble(), currentWallet);
              } else {
                _processCharge(context, amt.toDouble());
              }
            },
            child: Container(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(color: isWithdraw ? Colors.blueGrey[50] : Colors.orange[50], borderRadius: BorderRadius.circular(12), border: Border.all(color: isWithdraw ? Colors.blueGrey[200]! : Colors.orange[200]!)),
              child: Text("$amt ج.م", style: TextStyle(color: isWithdraw ? Colors.blueGrey[900] : Colors.orange[900], fontWeight: FontWeight.bold)),
            ),
          );
        }).toList()),
        const SizedBox(height: 30),
      ])),
    );
  }

  void _showLoading(BuildContext context) {
    showDialog(context: context, barrierDismissible: false, builder: (context) => const Center(child: CircularProgressIndicator(color: Colors.orange)));
  }

  String _formatTimestamp(dynamic ts) {
    if (ts == null) return "";
    DateTime date = (ts as Timestamp).toDate();
    return "${date.day}/${date.month} ${date.hour}:${date.minute.toString().padLeft(2, '0')}";
  }

  void _showInfoSheet(BuildContext context, String title, String msg) {
    showModalBottomSheet(context: context, builder: (context) => Container(padding: const EdgeInsets.all(30), child: Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.info_outline, size: 40, color: Colors.orange), const SizedBox(height: 15), Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'Cairo')), const SizedBox(height: 10), Text(msg, textAlign: TextAlign.center, style: const TextStyle(fontFamily: 'Cairo', fontSize: 12))])));
  }

  Widget _sectionHeader(String title) {
    return Padding(padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 10),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
        const Icon(Icons.history, size: 18, color: Colors.grey),
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
}

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:sizer/sizer.dart';
import 'package:url_launcher/url_launcher.dart';

class WalletScreen extends StatelessWidget {
  const WalletScreen({super.key});

  // ✅ طلب الشحن (أرقام ثابتة)
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
      }).timeout(const Duration(seconds: 10));
      Navigator.pop(context);
      _showInfoSheet(context, "تم استلام طلبك", "جاري تجهيز الرابط، سيظهر في السجل بالأسفل خلال ثوانٍ.");
    } catch (e) {
      Navigator.pop(context);
      _showInfoSheet(context, "خطأ", "فشل الاتصال، تأكد من الإنترنت.");
    }
  }

  // ✅ تنفيذ عملية السحب بعد التأكيد
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
      }).timeout(const Duration(seconds: 10));
      
      Navigator.pop(context); // إغلاق اللودينج
      _showInfoSheet(context, "تم إرسال الطلب", "سيتم مراجعة طلب سحب $amount ج.م وتحويله خلال 24 ساعة.");
    } catch (e) {
      Navigator.pop(context);
      _showInfoSheet(context, "خطأ", "حدث خطأ أثناء إرسال الطلب، حاول مجدداً.");
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
                  
                  // ✅ تكبير خط الرصيد القابل للسحب
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Text(
                      "الرصيد القابل للسحب: ${walletBalance.toStringAsFixed(2)} ج.م",
                      style: TextStyle(color: Colors.blueGrey[900], fontSize: 15.sp, fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
                    ),
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

  // ✅ نافذة سحب الكاش اليدوية
  void _showWithdrawDialog(BuildContext context, double currentWallet) {
    final TextEditingController amountController = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 25, right: 25, top: 25),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("أدخل مبلغ السحب", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
            const SizedBox(height: 15),
            TextField(
              controller: amountController,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                hintText: "0.00",
                suffixText: "ج.م",
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueGrey[800],
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))
              ),
              onPressed: () {
                double? val = double.tryParse(amountController.text);
                if (val == null || val <= 0) return;
                if (val > currentWallet) {
                  Navigator.pop(context);
                  _showInfoSheet(context, "عذراً", "المبلغ المطلوب أكبر من رصيدك الحالي.");
                  return;
                }
                Navigator.pop(context);
                _confirmWithdrawFees(context, val);
              },
              child: const Text("استمرار", style: TextStyle(fontFamily: 'Cairo', color: Colors.white)),
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  // ✅ رسالة تأكيد الرسوم
  void _confirmWithdrawFees(BuildContext context, double amount) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("تأكيد السحب", textAlign: TextAlign.right, style: TextStyle(fontFamily: 'Cairo')),
        content: Text("سيتم طلب سحب $amount ج.م.\nيرجى العلم أنه سيتم خصم رسوم التحويل من المبلغ المستلم حسب مزود الخدمة.", 
          textAlign: TextAlign.right, style: const TextStyle(fontFamily: 'Cairo')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("إلغاء", style: TextStyle(color: Colors.red))),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _executeWithdrawal(context, amount);
            },
            child: const Text("موافق وإرسال"),
          ),
        ],
      ),
    );
  }

  // ✅ اختيار مبلغ الشحن (أرقام ثابتة)
  void _showChargePicker(BuildContext context) {
    showModalBottomSheet(context: context, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (context) => Container(padding: const EdgeInsets.all(25), child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text("اختر مبلغ الشحن", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
        const SizedBox(height: 20),
        Wrap(spacing: 15, runSpacing: 15, children: [50, 100, 200, 500].map((amt) => InkWell(
          onTap: () { Navigator.pop(context); _processCharge(context, amt.toDouble()); },
          child: Container(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(color: Colors.orange[50], borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.orange[200]!)),
            child: Text("$amt ج.م", style: TextStyle(color: Colors.orange[900], fontWeight: FontWeight.bold)),
          ),
        )).toList()),
        const SizedBox(height: 30),
      ])),
    );
  }

  // ✅ السجل المدمج
  Widget _buildCombinedHistory(String? uid) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('pendingInvoices')
          .where('driverId', isEqualTo: uid)
          .where('status', isEqualTo: 'ready_for_payment').snapshots(),
      builder: (context, pendingSnap) {
        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('walletLogs')
              .where('driverId', isEqualTo: uid)
              .orderBy('timestamp', descending: true).limit(10).snapshots(),
          builder: (context, logSnap) {
            List<Map<String, dynamic>> allItems = [];
            if (pendingSnap.hasData) {
              for (var doc in pendingSnap.data!.docs) {
                var d = doc.data() as Map<String, dynamic>;
                d['isPendingLink'] = true;
                allItems.add(d);
              }
            }
            if (logSnap.hasData) {
              for (var doc in logSnap.data!.docs) {
                var d = doc.data() as Map<String, dynamic>;
                d['isPendingLink'] = false;
                allItems.add(d);
              }
            }
            if (allItems.isEmpty) return const Center(child: Text("لا توجد عمليات"));

            return ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: allItems.length,
              itemBuilder: (context, index) {
                var item = allItems[index];
                bool isPending = item['isPendingLink'] ?? false;
                double amount = (item['amount'] ?? 0.0).toDouble();

                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(color: isPending ? Colors.green[50] : Colors.white, borderRadius: BorderRadius.circular(15), border: Border.all(color: isPending ? Colors.green : Colors.grey[100]!)),
                  child: ListTile(
                    leading: Icon(isPending ? Icons.bolt : Icons.history, color: isPending ? Colors.green : Colors.grey),
                    title: Text(isPending ? "رابط شحن جاهز" : (amount > 0 ? "شحن رصيد" : "خصم عمولة"), style: const TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.bold)),
                    subtitle: Text(isPending ? "اضغط للدفع الآن" : _formatTimestamp(item['timestamp']), style: const TextStyle(fontFamily: 'Cairo', fontSize: 10)),
                    trailing: isPending
                        ? ElevatedButton(onPressed: () => launchUrl(Uri.parse(item['paymentUrl']), mode: LaunchMode.externalApplication), style: ElevatedButton.styleFrom(backgroundColor: Colors.green, padding: EdgeInsets.zero), child: const Text("ادفع", style: TextStyle(fontSize: 10, color: Colors.white)))
                        : Text("${amount.toStringAsFixed(2)} ج.م", style: TextStyle(fontWeight: FontWeight.bold, color: amount > 0 ? Colors.green : Colors.red)),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  // --- المساعدات (UI) ---
  Widget _buildAdvancedBalanceCard(double wallet, double credit, double total) {
    return Container(
      width: double.infinity, margin: const Offset(0, 10).distance > 0 ? const EdgeInsets.all(20) : EdgeInsets.zero, padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF1a1a1a), Color(0xFF3a3a3a)]), borderRadius: BorderRadius.circular(30)),
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

  void _showLoading(BuildContext context) {
    showDialog(context: context, barrierDismissible: false, builder: (context) => const Center(child: CircularProgressIndicator(color: Colors.orange)));
  }

  void _showInfoSheet(BuildContext context, String title, String msg) {
    showModalBottomSheet(context: context, builder: (context) => Container(padding: const EdgeInsets.all(30), child: Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.info_outline, size: 40, color: Colors.orange), const SizedBox(height: 15), Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'Cairo')), const SizedBox(height: 10), Text(msg, textAlign: TextAlign.center, style: const TextStyle(fontFamily: 'Cairo', fontSize: 12))])));
  }

  String _formatTimestamp(dynamic ts) {
    if (ts == null) return "";
    DateTime date = (ts as Timestamp).toDate();
    return "${date.day}/${date.month} ${date.hour}:${date.minute.toString().padLeft(2, '0')}";
  }

  Widget _sectionHeader(String title) {
    return Padding(padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 10), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, fontFamily: 'Cairo')), const Icon(Icons.history, size: 18, color: Colors.grey)]));
  }

  Widget _actionBtn(IconData icon, String label, Color color, VoidCallback onTap) {
    return ElevatedButton.icon(onPressed: onTap, icon: Icon(icon, size: 18), label: Text(label, style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 12)), style: ElevatedButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))));
  }
}

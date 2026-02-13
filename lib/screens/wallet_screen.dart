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
        'status': 'pay_now', // السيستم هيحولها لـ ready_for_payment ويضيف الـ URL
        'type': 'WALLET_TOPUP',
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (context.mounted) Navigator.pop(context);
      _showInfoSheet(context, "تم استلام طلبك", "جاري تجهيز الرابط، سيظهر في السجل بالأسفل خلال ثوانٍ.");
    } catch (e) {
      if (context.mounted) Navigator.pop(context);
      _showInfoSheet(context, "خطأ", "فشل الاتصال، تأكد من الإنترنت.");
    }
  }

  // ✅ تنفيذ عملية السحب (تم إصلاح اللودينج)
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
        Navigator.pop(context); // إغلاق اللودينج فوراً عند النجاح
        _showInfoSheet(context, "تم إرسال الطلب", "سيتم مراجعة طلب سحب $amount ج.م وتحويله خلال 24 ساعة.");
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context); // إغلاق اللودينج عند الخطأ
        _showInfoSheet(context, "خطأ", "حدث خطأ أثناء إرسال الطلب: $e");
      }
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

  // ✅ السجل المدمج مع فلترة "آخر رابط" و "صلاحية الساعتين"
  Widget _buildCombinedHistory(String? uid) {
    return StreamBuilder<QuerySnapshot>(
      // طلبنا آخر رابط واحد فقط ومرتب تنازلياً حسب الوقت
      stream: FirebaseFirestore.instance.collection('pendingInvoices')
          .where('driverId', isEqualTo: uid)
          .where('status', isEqualTo: 'ready_for_payment')
          .orderBy('createdAt', descending: true)
          .limit(1) 
          .snapshots(),
      builder: (context, pendingSnap) {
        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('walletLogs')
              .where('driverId', isEqualTo: uid)
              .orderBy('timestamp', descending: true).limit(10).snapshots(),
          builder: (context, logSnap) {
            List<Map<String, dynamic>> allItems = [];
            
            if (pendingSnap.hasData && pendingSnap.data!.docs.isNotEmpty) {
              var doc = pendingSnap.data!.docs.first;
              var d = doc.data() as Map<String, dynamic>;
              
              // ✅ فحص صلاحية الرابط (ساعتين = 120 دقيقة)
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

            if (allItems.isEmpty) return const Center(child: Text("لا توجد عمليات مؤخراً", style: TextStyle(fontFamily: 'Cairo')));

            return ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 20, bottom: 20),
              itemCount: allItems.length,
              itemBuilder: (context, index) {
                var item = allItems[index];
                bool isPending = item['isPendingLink'] ?? false;
                double amount = (item['amount'] ?? 0.0).toDouble();

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: isPending ? Colors.orange[50] : Colors.white, 
                    borderRadius: BorderRadius.circular(18), 
                    border: Border.all(color: isPending ? Colors.orange : Colors.grey[100]!)
                  ),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: isPending ? Colors.orange : Colors.blueGrey[50],
                      child: Icon(isPending ? Icons.link_rounded : Icons.history, color: isPending ? Colors.white : Colors.blueGrey),
                    ),
                    title: Text(isPending ? "رابط الدفع النشط" : (amount > 0 ? "شحن رصيد" : "خصم عمولة"), style: const TextStyle(fontFamily: 'Cairo', fontSize: 13, fontWeight: FontWeight.bold)),
                    subtitle: Text(isPending ? "صالح لمدة ساعتين من طلبه" : _formatTimestamp(item['timestamp']), style: const TextStyle(fontFamily: 'Cairo', fontSize: 10.5)),
                    trailing: isPending
                        ? ElevatedButton(
                            onPressed: () => launchUrl(Uri.parse(item['paymentUrl']), mode: LaunchMode.externalApplication), 
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange[900], shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))), 
                            child: const Text("ادفع", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)))
                        : Text("${amount > 0 ? '+' : ''}${amount.toStringAsFixed(2)} ج.م", style: TextStyle(fontWeight: FontWeight.bold, color: amount > 0 ? Colors.green : Colors.red)),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  // --- باقي الدوال المساعدة (بدون تغيير في الـ UI) ---
  // [أبقينا على _buildAdvancedBalanceCard و _showWithdrawDialog وغيرها كما هي لضمان استقرار التصميم]

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

  void _confirmWithdrawFees(BuildContext context, double amount) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("تأكيد السحب", textAlign: TextAlign.right, style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
        content: Text("سيتم طلب سحب $amount ج.م.\nسيتم التحويل خلال 24 ساعة لوسيلة الدفع المسجلة.", 
          textAlign: TextAlign.right, style: const TextStyle(fontFamily: 'Cairo')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("إلغاء", style: TextStyle(color: Colors.red, fontFamily: 'Cairo'))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () {
              Navigator.pop(context);
              _executeWithdrawal(context, amount);
            },
            child: const Text("تأكيد", style: TextStyle(fontFamily: 'Cairo', color: Colors.white)),
          ),
        ],
      ),
    );
  }

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

  Widget _buildAdvancedBalanceCard(double wallet, double credit, double total) {
    return Container(
      width: double.infinity, margin: const EdgeInsets.all(20), padding: const EdgeInsets.all(25),
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
    showModalBottomSheet(context: context, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))), builder: (context) => Container(padding: const EdgeInsets.all(30), child: Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.info_outline, size: 40, color: Colors.orange), const SizedBox(height: 15), Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'Cairo')), const SizedBox(height: 10), Text(msg, textAlign: TextAlign.center, style: const TextStyle(fontFamily: 'Cairo', fontSize: 12)), const SizedBox(height: 20)])));
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

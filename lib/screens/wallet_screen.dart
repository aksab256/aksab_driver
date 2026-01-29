import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:sizer/sizer.dart';
import 'package:url_launcher/url_launcher.dart';

class WalletScreen extends StatelessWidget {
  const WalletScreen({super.key});

  // ✅ الوظيفة المحدثة: تطلب الشحن عبر إضافة سجل للسيرفر
  Future<void> _processCharge(BuildContext context, double amount) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator(color: Colors.orange)),
    );

    try {
      // 🚀 الخطوة 1: رمي الطلب في كوليكشن pendingInvoices للسيرفر
      DocumentReference docRef = await FirebaseFirestore.instance.collection('pendingInvoices').add({
        'driverId': uid,
        'amount': amount,
        'status': 'pay_now', // لإثارة الـ Snapshot في السيرفر فوراً
        'type': 'WALLET_TOPUP',
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (!context.mounted) return;
      Navigator.pop(context); // إغلاق اللودينج

      // 🚀 الخطوة 2: مراقبة الوثيقة لحين ظهور الرابط من السيرفر
      _waitForPaymentUrl(context, docRef);

    } catch (e) {
      if (context.mounted) Navigator.pop(context);
      _showInfoSheet(context, "خطأ", "فشل الاتصال بالسيرفر، حاول مجدداً");
    }
  }

  // وظيفة تنتظر السيرفر يضيف الرابط وتفتحه تلقائياً
  void _waitForPaymentUrl(BuildContext context, DocumentReference ref) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.green),
            SizedBox(height: 15),
            Text("جاري تجهيز بوابة الدفع...", style: TextStyle(fontFamily: 'Cairo')),
          ],
        ),
      ),
    );

    // مراقبة لمرة واحدة حتى ظهور الرابط
    var listener = ref.snapshots().listen((snapshot) async {
      var data = snapshot.data() as Map<String, dynamic>?;
      if (data != null && data['paymentUrl'] != null) {
        Navigator.pop(context); // إغلاق رسالة الانتظار
        final Uri url = Uri.parse(data['paymentUrl']);
        if (await canLaunchUrl(url)) {
          await launchUrl(url, mode: LaunchMode.externalApplication);
        }
      }
    });

    // إغلاق المراقبة بعد 30 ثانية للأمان
    Future.delayed(const Duration(seconds: 30), () => listener.cancel());
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      backgroundColor: const Color(0xFFFBFBFB),
      appBar: AppBar(
        title: const Text("المحفظة الذكية", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black, fontFamily: 'Cairo')),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
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
              double? driverSpecificLimit = userData?['creditLimit']?.toDouble();

              double finalLimit = driverSpecificLimit ?? defaultGlobalLimit;
              double totalOperableBalance = walletBalance + finalLimit;

              return Column(
                children: [
                  _buildAdvancedBalanceCard(walletBalance, finalLimit, totalOperableBalance),
                  const SizedBox(height: 10),
                  Text("⚠️ الرصيد القابل للسحب هو رصيد المحفظة فقط (${walletBalance.toStringAsFixed(2)} ج.م)",
                      style: TextStyle(color: Colors.grey[600], fontSize: 9.sp, fontFamily: 'Cairo')),
                  
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                    child: Row(
                      children: [
                        Expanded(child: _actionBtn(Icons.add_card, "شحن رصيد", Colors.green[700]!, () => _showAmountPicker(context))),
                        const SizedBox(width: 15),
                        Expanded(child: _actionBtn(Icons.payments_outlined, "سحب كاش", Colors.blueGrey[800]!, () {
                          _showInfoSheet(context, "طلب سحب", "سيتم تفعيل السحب اليدوي قريباً عند وصول رصيدك لـ 100 ج.م");
                        })),
                      ],
                    ),
                  ),
                  
                  _sectionHeader("سجل العمليات"),
                  Expanded(child: _buildTransactionHistory(uid)),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildAdvancedBalanceCard(double wallet, double credit, double total) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(20),
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF1a1a1a), Color(0xFF3a3a3a)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(30),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 15, offset: const Offset(0, 8))],
      ),
      child: Column(
        children: [
          const Text("إجمالي رصيد التشغيل", style: TextStyle(color: Colors.white70, fontSize: 12, fontFamily: 'Cairo')),
          const SizedBox(height: 5),
          Text("${total.toStringAsFixed(2)} ج.م", style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(20)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _balanceDetail("المحفظة", wallet, Colors.greenAccent),
                Container(width: 1, height: 30, color: Colors.white24),
                _balanceDetail("الكريدت", credit, Colors.orangeAccent),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _balanceDetail(String label, double value, Color color) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 10, fontFamily: 'Cairo')),
        Text("${value.toStringAsFixed(2)}", style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
          const Icon(Icons.tune, size: 18, color: Colors.grey),
        ],
      ),
    );
  }

  Widget _buildTransactionHistory(String? uid) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('walletLogs')
          .where('driverId', isEqualTo: uid)
          .orderBy('timestamp', descending: true)
          .limit(10)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        if (snapshot.data!.docs.isEmpty) return const Center(child: Text("لا توجد عمليات حالياً"));
        
        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: snapshot.data!.docs.length,
          itemBuilder: (context, index) {
            var data = snapshot.data!.docs[index].data() as Map<String, dynamic>;
            double amount = (data['amount'] ?? 0.0).toDouble();
            bool isTopup = data['type'] == 'topup' || amount > 0;
            
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.grey[200]!)),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: isTopup ? Colors.green[50] : Colors.red[50],
                  child: Icon(isTopup ? Icons.add : Icons.remove, color: isTopup ? Colors.green : Colors.red, size: 18),
                ),
                title: Text(isTopup ? "شحن رصيد" : "خصم عمولة رحلة", style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, fontFamily: 'Cairo')),
                subtitle: Text(_formatTimestamp(data['timestamp']), style: const TextStyle(fontSize: 11, color: Colors.grey)),
                trailing: Text("${isTopup ? '+' : ''}${amount.toStringAsFixed(2)} ج.م", 
                  style: TextStyle(color: isTopup ? Colors.green[700] : Colors.red, fontWeight: FontWeight.bold, fontSize: 14)),
              ),
            );
          },
        );
      },
    );
  }

  // أزرار العمليات
  Widget _actionBtn(IconData icon, String label, Color color, VoidCallback onTap) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 20),
      label: Text(label, style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        elevation: 0
      ),
    );
  }

  void _showAmountPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (context) => Container(
        padding: const EdgeInsets.all(25),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("شحن محفظة أكسب", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
            const SizedBox(height: 25),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [50, 100, 200, 500].map((amt) => _amountOption(context, amt)).toList(),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _amountOption(BuildContext context, int amt) {
    return InkWell(
      onTap: () { Navigator.pop(context); _processCharge(context, amt.toDouble()); },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
        decoration: BoxDecoration(color: Colors.orange[50], borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.orange[200]!)),
        child: Text("$amt ج.م", style: TextStyle(color: Colors.orange[900], fontWeight: FontWeight.bold)),
      ),
    );
  }

  String _formatTimestamp(dynamic ts) {
    if (ts == null) return "";
    DateTime date = (ts as Timestamp).toDate();
    return "${date.day}/${date.month} - ${date.hour}:${date.minute.toString().padLeft(2, '0')}";
  }

  void _showInfoSheet(BuildContext context, String title, String msg) {
    showModalBottomSheet(context: context, builder: (context) => Container(padding: const EdgeInsets.all(30), child: Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.info_outline, size: 40, color: Colors.orange), const SizedBox(height: 15), Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, fontFamily: 'Cairo')), const SizedBox(height: 10), Text(msg, textAlign: TextAlign.center, style: const TextStyle(fontFamily: 'Cairo'))])));
  }
}

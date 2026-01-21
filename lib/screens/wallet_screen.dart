import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:sizer/sizer.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

class WalletScreen extends StatelessWidget {
  const WalletScreen({super.key});

  Future<void> _processCharge(BuildContext context, double amount) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    // تم تحديث الرابط للرابط الجديد الخاص بالدالة الشهرية
    const String lambdaApiUrl = "https://brdbg7u6wpn7fjoftwenecxhei0tvhwf.lambda-url.us-east-1.on.aws/";

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator(color: Colors.orange)),
    );

    try {
      final response = await http.post(
        Uri.parse(lambdaApiUrl),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "type": "WALLET_TOPUP", // تم التغيير ليتوافق مع شرط الدالة الجديدة
          "driverId": uid,
          "amount": amount,
        }),
      ).timeout(const Duration(seconds: 15));

      if (!context.mounted) return;
      Navigator.pop(context); // إغلاق لودينج

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);

        // التحقق من نجاح العملية ووجود الرابط (بناءً على تصميم الدالة الموحدة)
        if (data['status'] == 'success' && data['paymentUrl'] != null) {
          final Uri url = Uri.parse(data['paymentUrl']);
          if (await canLaunchUrl(url)) {
            // فتح صفحة الدفع (ستفتح صفحة المحافظ مباشرة لتجنب خطأ الـ Iframe)
            await launchUrl(url, mode: LaunchMode.externalApplication);
          } else {
            _showInfoSheet(context, "تنبيه", "لا يمكن فتح رابط الدفع حالياً.");
          }
        } else {
          _showInfoSheet(context, "خطأ", data['message'] ?? "فشل في توليد رابط الدفع.");
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("خطأ من السيرفر: ${response.statusCode}")),
        );
      }
    } catch (e) {
      if (context.mounted) Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("تحقق من اتصال الإنترنت وحاول مرة أخرى")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text("المحفظة الإلكترونية", 
          style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold, color: Colors.black)),
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
              double displayBalance = walletBalance + finalLimit;

              return Column(
                children: [
                  _buildBalanceCard(displayBalance),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    child: Row(
                      children: [
                        Expanded(child: _actionBtn(Icons.add_circle, "شحن رصيد", Colors.green, () => _showAmountPicker(context))),
                        const SizedBox(width: 15),
                        Expanded(child: _actionBtn(Icons.account_balance_wallet, "سحب", Colors.blueGrey, () {})),
                      ],
                    ),
                  ),
                  const Divider(height: 30),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 25),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Text("سجل العمليات الأخير", style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w900)),
                    ),
                  ),
                  Expanded(child: _buildTransactionHistory(uid)),
                ],
              );
            },
          );
        },
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
        if (!snapshot.hasData) return const SizedBox();
        if (snapshot.data!.docs.isEmpty) return Center(child: Text("لا توجد عمليات سابقة", style: TextStyle(color: Colors.grey, fontSize: 11.sp)));
        
        return ListView.builder(
          padding: const EdgeInsets.all(20),
          itemCount: snapshot.data!.docs.length,
          itemBuilder: (context, index) {
            var data = snapshot.data!.docs[index].data() as Map<String, dynamic>;
            double amount = (data['amount'] ?? 0.0).toDouble();
            String type = data['type'] == 'commission_deduction' ? "خصم عمولة" : "شحن رصيد";
            return _historyItem("$type", "${amount.toStringAsFixed(2)} ج.م", amount < 0 ? Colors.redAccent : Colors.green, data['timestamp'] as Timestamp?);
          },
        );
      },
    );
  }

  Widget _buildBalanceCard(double displayBalance) {
    bool isLow = displayBalance <= 5.0;

    return Container(
      width: double.infinity, margin: const EdgeInsets.all(20), padding: const EdgeInsets.all(30),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isLow ? [Colors.red[900]!, Colors.black87] : [Colors.orange[900]!, Colors.black87], 
          begin: Alignment.topLeft
        ),
        borderRadius: BorderRadius.circular(25),
        boxShadow: [BoxShadow(color: Colors.orange.withOpacity(0.3), blurRadius: 15, offset: const Offset(0, 10))],
      ),
      child: Column(children: [
        Text("الرصيد المتاح للتشغيل", style: TextStyle(color: Colors.white70, fontSize: 11.sp)),
        const SizedBox(height: 10),
        Text("${displayBalance.toStringAsFixed(2)} ج.م", style: TextStyle(color: Colors.white, fontSize: 26.sp, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        if (isLow) 
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), 
            decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(10)), 
            child: Text("يرجى الشحن لتتمكن من استقبال الطلبات", style: TextStyle(color: Colors.white, fontSize: 9.sp))
          )
      ]),
    );
  }

  Widget _actionBtn(IconData icon, String label, Color color, VoidCallback onTap) {
    return InkWell(onTap: onTap, child: Container(padding: const EdgeInsets.symmetric(vertical: 15), decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(15)), child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icon, color: Colors.white, size: 18.sp), const SizedBox(width: 8), Text(label, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12.sp))])));
  }

  Widget _historyItem(String title, String amount, Color color, Timestamp? time) {
    return ListTile(contentPadding: EdgeInsets.zero, leading: CircleAvatar(backgroundColor: Colors.grey[100], child: Icon(Icons.history, color: Colors.grey[600], size: 16.sp)), title: Text(title, style: TextStyle(fontSize: 11.sp, fontWeight: FontWeight.w600)), subtitle: Text(time != null ? "${time.toDate().hour}:${time.toDate().minute} - ${time.toDate().day}/${time.toDate().month}" : "", style: TextStyle(fontSize: 9.sp)), trailing: Text(amount, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12.sp)));
  }

  void _showAmountPicker(BuildContext context) {
    showModalBottomSheet(context: context, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))), builder: (context) => Container(padding: const EdgeInsets.all(25), child: Column(mainAxisSize: MainAxisSize.min, children: [Text("اختر مبلغ الشحن", style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.bold)), const SizedBox(height: 20), Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [50, 100, 200].map((amt) => ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.orange[900]), onPressed: () { Navigator.pop(context); _processCharge(context, amt.toDouble()); }, child: Text("$amt ج.م", style: const TextStyle(color: Colors.white)))).toList())])));
  }

  void _showInfoSheet(BuildContext context, String title, String msg) {
    showModalBottomSheet(context: context, builder: (context) => Container(padding: const EdgeInsets.all(30), child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.info_outline, size: 40.sp, color: Colors.orange), const SizedBox(height: 15), Text(title, style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.bold)), const SizedBox(height: 10), Text(msg, textAlign: TextAlign.center)])));
  }
}

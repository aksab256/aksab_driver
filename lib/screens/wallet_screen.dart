import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:sizer/sizer.dart';
import 'dart:convert';
import 'package:http/http.dart' as http; // تم تفعيل المكتبة
import 'package:url_launcher/url_launcher.dart'; // تم تفعيل المكتبة

class WalletScreen extends StatelessWidget {
  const WalletScreen({super.key});

  // دالة استدعاء الـ API (اللمدا) لشحن الرصيد بنجاح
  Future<void> _processCharge(BuildContext context, double amount) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    
    // الرابط الذي قمت بإنشائه ونشره على AWS
    const String lambdaApiUrl = "https://spmyeym5p4.execute-api.us-east-1.amazonaws.com/div/payment";

    // إظهار مؤشر تحميل
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator(color: Colors.orange)),
    );

    try {
      // إرسال الحمولة السليمة للمدا
      final response = await http.post(
        Uri.parse(lambdaApiUrl),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "type": "REQUEST_CHARGE", // تحديد نوع العملية
          "driverId": uid,
          "amount": amount,
        }),
      );

      Navigator.pop(context); // إغلاق مؤشر التحميل

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final String paymentUrl = data['paymentUrl']; // الرابط الوهمي حالياً

        // فتح المتصفح لإتمام عملية الدفع
        final Uri url = Uri.parse(paymentUrl);
        if (await canLaunchUrl(url)) {
          await launchUrl(url, mode: LaunchMode.externalApplication);
        } else {
          _showInfoSheet(context, "تنبيه", "لا يمكن فتح رابط الدفع حالياً.");
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("خطأ من السيرفر: ${response.statusCode}")),
        );
      }
    } catch (e) {
      Navigator.pop(context); // إغلاق التحميل في حالة الفشل
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("فشل الاتصال بخادم الدفع، تحقق من الإنترنت")),
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
        // مراقبة رصيد المندوب من مجموعة freeDrivers التي اتحدنا عليها
        stream: FirebaseFirestore.instance.collection('freeDrivers').doc(uid).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

          var userData = snapshot.data!.data() as Map<String, dynamic>?;
          double balance = (userData?['walletBalance'] ?? 0.0).toDouble();

          return Column(
            children: [
              _buildBalanceCard(balance),
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
      ),
    );
  }

  // سجل العمليات يقرأ من سجل المحفظة الذي تنشئه اللمدا (walletLogs)
  Widget _buildTransactionHistory(String? uid) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('walletLogs')
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
            Color color = amount < 0 ? Colors.redAccent : Colors.green;

            return _historyItem(
              "$type (طلب #${data['orderId']?.toString().substring(0, 4) ?? '...'})",
              "${amount.toStringAsFixed(2)} ج.م",
              color,
              data['timestamp'] as Timestamp?,
            );
          },
        );
      },
    );
  }

  // --- المكونات البصرية (UI Widgets) بقيت كما هي مع تحسينات طفيفة للمناسبة ---
  Widget _buildBalanceCard(double balance) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(20),
      padding: const EdgeInsets.all(30),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [Colors.orange[900]!, Colors.black87], begin: Alignment.topLeft),
        borderRadius: BorderRadius.circular(25),
        boxShadow: [BoxShadow(color: Colors.orange.withOpacity(0.3), blurRadius: 15, offset: const Offset(0, 10))],
      ),
      child: Column(
        children: [
          Text("رصيدك الحالي المسبق الدفع", style: TextStyle(color: Colors.white70, fontSize: 11.sp)),
          const SizedBox(height: 10),
          Text("${balance.toStringAsFixed(2)} ج.م",
            style: TextStyle(color: Colors.white, fontSize: 26.sp, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          if (balance <= 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(10)),
              child: Text("يرجى الشحن لتتمكن من العمل", style: TextStyle(color: Colors.white, fontSize: 9.sp)),
            )
        ],
      ),
    );
  }

  Widget _actionBtn(IconData icon, String label, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 15),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(15)),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 18.sp),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12.sp)),
          ],
        ),
      ),
    );
  }

  Widget _historyItem(String title, String amount, Color color, Timestamp? time) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(backgroundColor: Colors.grey[100], child: Icon(Icons.history, color: Colors.grey[600], size: 16.sp)),
      title: Text(title, style: TextStyle(fontSize: 11.sp, fontWeight: FontWeight.w600)),
      subtitle: Text(time != null ? "${time.toDate().hour}:${time.toDate().minute} - ${time.toDate().day}/${time.toDate().month}" : "", style: TextStyle(fontSize: 9.sp)),
      trailing: Text(amount, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12.sp)),
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
            Text("اختر مبلغ الشحن", style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [50, 100, 200].map((amt) => ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.orange[900]),
                onPressed: () {
                  Navigator.pop(context);
                  _processCharge(context, amt.toDouble());
                },
                child: Text("$amt ج.م"),
              )).toList(),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  void _showInfoSheet(BuildContext context, String title, String msg) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, size: 40.sp, color: Colors.green),
            const SizedBox(height: 15),
            Text(title, style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Text(msg, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}


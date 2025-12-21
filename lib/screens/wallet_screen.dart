import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:sizer/sizer.dart';

class WalletScreen extends StatelessWidget {
  const WalletScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      backgroundColor: Colors.white,
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('freeDrivers').doc(uid).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          
          var userData = snapshot.data!.data() as Map<String, dynamic>;
          // لو حقل walletBalance مش موجود بنفترض إنه 0.0
          double balance = (userData['walletBalance'] ?? 0.0).toDouble();

          return Column(
            children: [
              // كارت الرصيد
              _buildBalanceCard(balance),
              
              const SizedBox(height: 20),
              
              // أزرار التحكم
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Expanded(child: _actionBtn(Icons.add_circle, "شحن رصيد", Colors.green, () {
                      _showPaymentNotice(context);
                    })),
                    const SizedBox(width: 15),
                    Expanded(child: _actionBtn(Icons.outbox, "سحب أموال", Colors.blue, () {})),
                  ],
                ),
              ),

              const Divider(height: 40),
              
              // سجل العمليات (تجريبي حالياً)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Align(alignment: Alignment.centerRight, 
                  child: Text("آخر العمليات المباشرة", style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.bold))),
              ),
              
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    _historyItem("عمولة نظام - طلب #12", "- 15.00 ج.م", Colors.red),
                    _historyItem("شحن رصيد محفظة", "+ 100.00 ج.م", Colors.green),
                  ],
                ),
              )
            ],
          );
        },
      ),
    );
  }

  Widget _buildBalanceCard(double balance) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(20),
      padding: const EdgeInsets.all(30),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [Colors.blueGrey[900]!, Colors.black]),
        borderRadius: BorderRadius.circular(25),
        boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10, offset: const Offset(0, 5))],
      ),
      child: Column(
        children: [
          Text("الرصيد المتاح حالياً", style: TextStyle(color: Colors.white70, fontSize: 12.sp)),
          const SizedBox(height: 10),
          Text("${balance.toStringAsFixed(2)} ج.م", 
            style: TextStyle(color: Colors.white, fontSize: 24.sp, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _actionBtn(IconData icon, String label, Color color, VoidCallback onTap) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, color: Colors.white),
      label: Text(label, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      ),
    );
  }

  Widget _historyItem(String title, String amount, Color color) {
    return ListTile(
      leading: Icon(Icons.history, color: Colors.grey),
      title: Text(title, style: TextStyle(fontSize: 12.sp)),
      trailing: Text(amount, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12.sp)),
    );
  }

  void _showPaymentNotice(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (context) => Container(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.payment, size: 40.sp, color: Colors.orange),
            const SizedBox(height: 20),
            Text("بوابة الدفع الإلكتروني", style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            const Text("سيتم تفعيل شحن الرصيد آلياً عبر (فوري / فيزا / فودافون كاش) في التحديث القادم بعد ربط بوابة الدفع الرسمية.",
              textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

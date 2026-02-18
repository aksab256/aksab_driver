import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:sizer/sizer.dart';

class FinancialSettlementScreen extends StatefulWidget {
  final String repCode; 
  final String repName;

  const FinancialSettlementScreen({
    super.key,
    required this.repCode,
    required this.repName,
  });

  @override
  State<FinancialSettlementScreen> createState() => _FinancialSettlementScreenState();
}

class _FinancialSettlementScreenState extends State<FinancialSettlementScreen> {
  final TextEditingController _amountReceivedController = TextEditingController();
  bool _isProcessing = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text("تصفية حساب المندوب"),
        backgroundColor: Colors.green[700],
        centerTitle: true,
      ),
      body: StreamBuilder<QuerySnapshot>(
        // التعديل الجوهري: القراءة من waitingdelivery مع فلترة الحالة delivered
        stream: FirebaseFirestore.instance
            .collection('waitingdelivery') 
            .where('repCode', isEqualTo: widget.repCode)
            .where('deliveryTaskStatus', isEqualTo: 'delivered') // تم التسليم
            .where('isSettled', isEqualTo: false) // لم يورد الكاش بعد
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          
          var docs = snapshot.data?.docs ?? [];
          
          double totalCashInHand = 0;
          for (var d in docs) {
            totalCashInHand += (d['total'] ?? 0);
          }

          if (totalCashInHand == 0) {
            return _buildNoDataState();
          }

          return SingleChildScrollView(
            padding: EdgeInsets.all(15.sp),
            child: Column(
              children: [
                _buildSummaryCard(totalCashInHand, docs.length),
                SizedBox(height: 20.sp),
                _buildEntrySection(),
                SizedBox(height: 30.sp),
                _isProcessing 
                  ? const CircularProgressIndicator()
                  : _buildSubmitButton(docs, totalCashInHand),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSummaryCard(double total, int count) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Container(
        padding: EdgeInsets.all(20.sp),
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [Colors.green[800]!, Colors.green[600]!]),
          borderRadius: BorderRadius.circular(15),
        ),
        child: Column(
          children: [
            Text("المبالغ المحصلة (كاش مع المندوب)", style: TextStyle(color: Colors.white, fontSize: 11.sp)),
            SizedBox(height: 10.sp),
            Text("${total.toStringAsFixed(2)} ج.م", 
                 style: TextStyle(color: Colors.white, fontSize: 22.sp, fontWeight: FontWeight.bold)),
            const Divider(color: Colors.white24),
            Text("عدد الطلبات غير الموردة: $count", style: const TextStyle(color: Colors.white70)),
          ],
        ),
      ),
    );
  }

  Widget _buildEntrySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("تأكيد المبلغ المستلم من المندوب:", style: TextStyle(fontWeight: FontWeight.bold)),
        SizedBox(height: 10.sp),
        TextField(
          controller: _amountReceivedController,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold, color: Colors.blue[900]),
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.white,
            hintText: "أدخل المبلغ المستلم",
            prefixIcon: const Icon(Icons.money),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ],
    );
  }

  Widget _buildSubmitButton(List<QueryDocumentSnapshot> docs, double expected) {
    return SizedBox(
      width: double.infinity,
      height: 55,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.blue[800],
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
        ),
        onPressed: () => _processSettlement(docs, expected),
        child: const Text("تأكيد استلام الكاش وتصفية العهدة", 
          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Future<void> _processSettlement(List<QueryDocumentSnapshot> docs, double expected) async {
    if (_amountReceivedController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("يرجى إدخال المبلغ المستلم أولاً")));
      return;
    }

    setState(() => _isProcessing = true);
    try {
      WriteBatch batch = FirebaseFirestore.instance.batch();

      // 1. تحديث الطلبات داخل نفس المجموعة waitingdelivery
      for (var doc in docs) {
        batch.update(doc.reference, {
          'isSettled': true, // تم توريد الكاش للمشرف
          'settledAt': FieldValue.serverTimestamp(),
        });
      }

      // 2. تسجيل العملية في جدول التسويات الكلي (للأرشيف المالي)
      DocumentReference settlementRef = FirebaseFirestore.instance.collection('settlements').doc();
      batch.set(settlementRef, {
        'repCode': widget.repCode,
        'repName': widget.repName,
        'amountExpected': expected,
        'amountReceived': double.tryParse(_amountReceivedController.text) ?? 0,
        'settlementDate': FieldValue.serverTimestamp(),
        'ordersCount': docs.length,
        'orderIds': docs.map((d) => d.id).toList(),
      });

      await batch.commit();
      
      if (mounted) {
        _amountReceivedController.clear();
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("تم توريد المبلغ وتصفية حساب المندوب بنجاح ✅"),
          backgroundColor: Colors.green,
        ));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("حدث خطأ في النظام: $e")));
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Widget _buildNoDataState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.account_balance_wallet_outlined, size: 60.sp, color: Colors.grey[400]),
          SizedBox(height: 15.sp),
          const Text("رصيد المندوب صفر.. لا توجد مبالغ للتحصيل", 
            style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

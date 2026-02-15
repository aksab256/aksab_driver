import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:sizer/sizer.dart';
import 'package:intl/intl.dart';

class RepReportsScreen extends StatefulWidget {
  final String repCode;
  const RepReportsScreen({super.key, required this.repCode});

  @override
  State<RepReportsScreen> createState() => _RepReportsScreenState();
}

class _RepReportsScreenState extends State<RepReportsScreen> {
  DateTime _startDate = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _endDate = DateTime.now();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text("تقارير الأداء والتحصيل", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: const Color(0xFF2C3E50),
        centerTitle: true,
        elevation: 0,
      ),
      body: Column(
        children: [
          _buildFilterHeader(),
          Expanded(
            child: _buildReportContent(),
          ),
        ],
      ),
    );
  }

  // --- 1. هيدر الفلترة (يظهر الشهر الحالي افتراضياً) ---
  Widget _buildFilterHeader() {
    return Container(
      padding: EdgeInsets.all(12.sp),
      decoration: const BoxDecoration(
        color: Color(0xFF2C3E50),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(25)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _datePickerBox("من", _startDate, (date) => setState(() => _startDate = date)),
          Icon(Icons.arrow_forward, color: Colors.white54, size: 15.sp),
          _datePickerBox("إلى", _endDate, (date) => setState(() => _endDate = date)),
        ],
      ),
    );
  }

  Widget _datePickerBox(String label, DateTime date, Function(DateTime) onSelect) {
    return GestureDetector(
      onTap: () async {
        DateTime? picked = await showDatePicker(
          context: context,
          initialDate: date,
          firstDate: DateTime(2024),
          lastDate: DateTime.now(),
        );
        if (picked != null) onSelect(picked);
      },
      child: Column(
        children: [
          Text(label, style: TextStyle(color: Colors.white70, fontSize: 10.sp)),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 10.sp, vertical: 5.sp),
            decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(10)),
            child: Text(DateFormat('yyyy-MM-dd').format(date), 
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11.sp)),
          ),
        ],
      ),
    );
  }

  // --- 2. محتوى التقارير (StreamBuilder لربط البيانات) ---
  Widget _buildReportContent() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('deliveredorders')
          .where('handledByRepId', isEqualTo: widget.repCode)
          .where('timestamp', isGreaterThanOrEqualTo: _startDate)
          .where('timestamp', isLessThanOrEqualTo: _endDate.add(const Duration(days: 1)))
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        
        double totalCash = 0;
        int count = snapshot.data?.docs.length ?? 0;
        for (var doc in snapshot.data?.docs ?? []) {
          totalCash += (doc['total'] ?? 0).toDouble();
        }

        return SingleChildScrollView(
          padding: EdgeInsets.all(15.sp),
          child: Column(
            children: [
              _buildSummaryCards(totalCash, count),
              SizedBox(height: 20.sp),
              Align(
                alignment: Alignment.centerRight,
                child: Text(" تفاصيل العمليات:", style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.bold)),
              ),
              const Divider(),
              _buildOrdersList(snapshot.data?.docs ?? []),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSummaryCards(double cash, int count) {
    return Row(
      children: [
        _statCard("إجمالي التحصيل", "${cash.toStringAsFixed(0)} ج.م", Icons.account_balance_wallet, Colors.green),
        SizedBox(width: 10.sp),
        _statCard("طلبات ناجحة", "$count", Icons.done_all, Colors.blue),
      ],
    );
  }

  Widget _statCard(String title, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: EdgeInsets.all(15.sp),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: color.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 5))],
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 25.sp),
            SizedBox(height: 10.sp),
            Text(value, style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w900, color: color)),
            Text(title, style: TextStyle(fontSize: 10.sp, color: Colors.grey[600])),
          ],
        ),
      ),
    );
  }

  Widget _buildOrdersList(List<QueryDocumentSnapshot> docs) {
    if (docs.isEmpty) return Padding(padding: EdgeInsets.only(top: 20.h), child: const Text("لا توجد بيانات لهذه الفترة"));
    
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: docs.length,
      itemBuilder: (context, index) {
        var data = docs[index].data() as Map<String, dynamic>;
        return Card(
          margin: EdgeInsets.symmetric(vertical: 5.sp),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          child: ListTile(
            leading: CircleAvatar(backgroundColor: Colors.blue[50], child: const Icon(Icons.receipt, color: Colors.blue)),
            title: Text("طلب #${docs[index].id.substring(0,6)}", style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(DateFormat('dd/MM/yyyy hh:mm a').format((data['timestamp'] as Timestamp).toDate())),
            trailing: Text("${data['total']} ج.م", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
          ),
        );
      },
    );
  }
}

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
  // الفلترة الافتراضية: من أول يوم في الشهر الحالي حتى اللحظة
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
      ),
      body: Column(
        children: [
          _buildFilterHeader(),
          Expanded(child: _buildReportContent()),
        ],
      ),
    );
  }

  // هيدر اختيار التاريخ
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
          firstDate: DateTime(2025),
          lastDate: DateTime.now().add(const Duration(days: 1)),
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

  Widget _buildReportContent() {
    return StreamBuilder<QuerySnapshot>(
      // الاستعلام البسيط: نفلتر بكود المندوب فقط لتجنب الفهرس المركب
      stream: FirebaseFirestore.instance
          .collection('deliveredorders')
          .where('handledByRepId', isEqualTo: widget.repCode)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text("خطأ في البيانات: ${snapshot.error}"));
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        
        // فلترة البيانات يدوياً داخل الكود (Client-side Filtering)
        final allDocs = snapshot.data?.docs ?? [];
        final filteredDocs = allDocs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          if (data['timestamp'] == null) return false;
          DateTime orderDate = (data['timestamp'] as Timestamp).toDate();
          // مقارنة التاريخ (بدون الساعات لضمان الدقة)
          return orderDate.isAfter(_startDate.subtract(const Duration(seconds: 1))) && 
                 orderDate.isBefore(_endDate.add(const Duration(days: 1)));
        }).toList();

        // حساب الإجماليات من القائمة المفلترة
        double totalCash = 0;
        for (var doc in filteredDocs) {
          totalCash += (doc['total'] ?? 0).toDouble();
        }

        return SingleChildScrollView(
          padding: EdgeInsets.all(15.sp),
          child: Column(
            children: [
              _buildSummaryCards(totalCash, filteredDocs.length),
              SizedBox(height: 20.sp),
              const Align(alignment: Alignment.centerRight, child: Text(" سجل العمليات المفلترة:", style: TextStyle(fontWeight: FontWeight.bold))),
              const Divider(),
              _buildOrdersList(filteredDocs),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSummaryCards(double cash, int count) {
    return Row(
      children: [
        _statCard("إجمالي التحصيل", "${cash.toStringAsFixed(2)} ج.م", Icons.account_balance_wallet, Colors.green),
        SizedBox(width: 10.sp),
        _statCard("طلبات ناجحة", "$count", Icons.done_all, Colors.blue),
      ],
    );
  }

  Widget _statCard(String title, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: EdgeInsets.all(12.sp),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), 
          boxShadow: [BoxShadow(color: color.withOpacity(0.1), blurRadius: 10)]),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22.sp),
            Text(value, style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w900, color: color)),
            Text(title, style: TextStyle(fontSize: 9.sp, color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  Widget _buildOrdersList(List<QueryDocumentSnapshot> docs) {
    if (docs.isEmpty) return Padding(padding: EdgeInsets.only(top: 10.h), child: const Text("لا توجد بيانات للفترة المختارة"));
    
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: docs.length,
      itemBuilder: (context, index) {
        var data = docs[index].data() as Map<String, dynamic>;
        return ListTile(
          leading: const Icon(Icons.receipt_long, color: Colors.blueGrey),
          title: Text("طلب #${docs[index].id.substring(0,6)}"),
          subtitle: Text(DateFormat('dd/MM/yyyy').format((data['timestamp'] as Timestamp).toDate())),
          trailing: Text("${data['total']} ج.م", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
        );
      },
    );
  }
}

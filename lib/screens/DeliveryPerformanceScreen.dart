import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:sizer/sizer.dart';
import 'package:fl_chart/fl_chart.dart';

class DeliveryPerformanceScreen extends StatefulWidget {
  final String repId;    // الـ Document ID في Firebase
  final String repCode;  // كود المندوب المستخدم في الربط
  final String repName;  // اسم المندوب للعرض

  const DeliveryPerformanceScreen({
    super.key,
    required this.repId,
    required this.repCode,
    required this.repName,
  });

  @override
  State<DeliveryPerformanceScreen> createState() => _DeliveryPerformanceScreenState();
}

class _DeliveryPerformanceScreenState extends State<DeliveryPerformanceScreen> {
  DateTime startDate = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime endDate = DateTime.now();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FA),
      appBar: AppBar(
        title: Text("أداء المندوب: ${widget.repName}"),
        centerTitle: true,
        backgroundColor: const Color(0xFF007BFF),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(12.sp),
        child: Column(
          children: [
            _buildDateFilter(),
            SizedBox(height: 15.sp),
            _buildCurrentLiveStatus(), // حالة المهام المتبقية الآن
            SizedBox(height: 15.sp),
            _buildHistoricalPerformance(), // إحصائيات الفترة المختارة
          ],
        ),
      ),
    );
  }

  // فلتر اختيار الفترة الزمنية
  Widget _buildDateFilter() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 10.sp, horizontal: 15.sp),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _dateColumn("من", startDate, (date) => setState(() => startDate = date)),
            Container(width: 1, height: 30, color: Colors.grey[300]),
            _dateColumn("إلى", endDate, (date) => setState(() => endDate = date)),
            Icon(Icons.calendar_month, color: Colors.blue[800]),
          ],
        ),
      ),
    );
  }

  Widget _dateColumn(String label, DateTime date, Function(DateTime) onSelect) {
    return InkWell(
      onTap: () async {
        DateTime? picked = await showDatePicker(
          context: context,
          initialDate: date,
          firstDate: DateTime(2024),
          lastDate: DateTime.now().add(const Duration(days: 365)),
        );
        if (picked != null) onSelect(picked);
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 9.sp)),
          Text("${date.day}-${date.month}-${date.year}", 
               style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.sp)),
        ],
      ),
    );
  }

  // حالة المهام المتبقية حالياً (Real-time من waitingdelivery)
  Widget _buildCurrentLiveStatus() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('waitingdelivery')
          .where('deliveryRepId', isEqualTo: widget.repCode)
          .snapshots(),
      builder: (context, snapshot) {
        int remaining = snapshot.hasData ? snapshot.data!.docs.length : 0;
        bool isDone = remaining == 0;
        return Container(
          padding: EdgeInsets.all(12.sp),
          decoration: BoxDecoration(
            color: isDone ? Colors.green[50] : Colors.orange[50],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isDone ? Colors.green : Colors.orange),
          ),
          child: Row(
            children: [
              Icon(isDone ? Icons.check_circle : Icons.pending_actions, 
                   color: isDone ? Colors.green : Colors.orange[800]),
              SizedBox(width: 10.sp),
              Expanded(
                child: Text(
                  isDone ? "أنهى جميع المهام المسندة ✅" : "لا تزال هناك $remaining مهام قيد التنفيذ",
                  style: TextStyle(fontWeight: FontWeight.bold, color: isDone ? Colors.green[800] : Colors.orange[900]),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // إحصائيات الأداء للفترة المختارة
  Widget _buildHistoricalPerformance() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('orders')
          .where('deliveryRepCode', isEqualTo: widget.repCode)
          .where('orderDate', isGreaterThanOrEqualTo: startDate)
          .where('orderDate', isLessThanOrEqualTo: endDate.add(const Duration(days: 1)))
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const CircularProgressIndicator();
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(child: Padding(
            padding: EdgeInsets.only(top: 20.sp),
            child: const Text("لا توجد بيانات لهذه الفترة"),
          ));
        }

        var docs = snapshot.data!.docs;
        int delivered = docs.where((d) => d['status'] == 'delivered').length;
        int failed = docs.where((d) => d['status'] == 'failed').length;
        double totalCash = 0;
        for (var d in docs.where((d) => d['status'] == 'delivered')) {
          totalCash += (d['total'] ?? 0);
        }

        return Column(
          children: [
            Row(
              children: [
                _kpiCard("تسليم ناجح", "$delivered", Icons.done_all, Colors.green),
                _kpiCard("تسليم فاشل", "$failed", Icons.close, Colors.red),
              ],
            ),
            SizedBox(height: 10.sp),
            _wideKpiCard("إجمالي المبالغ المحصلة", "${totalCash.toStringAsFixed(2)} ج.م", Icons.payments, Colors.blue[900]!),
            SizedBox(height: 20.sp),
            Text("تحليل نسبة النجاح", style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.bold)),
            SizedBox(height: 10.sp),
            _buildPieChart(delivered, failed),
          ],
        );
      },
    );
  }

  Widget _kpiCard(String title, String value, IconData icon, Color color) {
    return Expanded(
      child: Card(
        elevation: 3,
        child: Padding(
          padding: EdgeInsets.all(12.sp),
          child: Column(
            children: [
              Icon(icon, color: color, size: 22.sp),
              SizedBox(height: 8.sp),
              Text(title, style: TextStyle(color: Colors.grey[600], fontSize: 10.sp)),
              Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.sp, color: color)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _wideKpiCard(String title, String value, IconData icon, Color color) {
    return SizedBox(
      width: double.infinity,
      child: Card(
        color: color,
        elevation: 4,
        child: Padding(
          padding: EdgeInsets.all(15.sp),
          child: Column(
            children: [
              Icon(icon, color: Colors.white, size: 25.sp),
              SizedBox(height: 5.sp),
              Text(title, style: const TextStyle(color: Colors.white70)),
              Text(value, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18.sp)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPieChart(int success, int failed) {
    int total = success + failed;
    if (total == 0) return const SizedBox();
    return Container(
      height: 200,
      child: PieChart(
        PieChartData(
          sectionsSpace: 2,
          centerSpaceRadius: 40,
          sections: [
            PieChartSectionData(
              value: success.toDouble(),
              title: '${((success/total)*100).toStringAsFixed(0)}%',
              color: Colors.green,
              radius: 50,
              titleStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            PieChartSectionData(
              value: failed.toDouble(),
              title: '${((failed/total)*100).toStringAsFixed(0)}%',
              color: Colors.red,
              radius: 50,
              titleStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}


import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:sizer/sizer.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class RepReportsScreen extends StatefulWidget {
  final String repCode;
  const RepReportsScreen({super.key, required this.repCode});

  @override
  State<RepReportsScreen> createState() => _RepReportsScreenState();
}

class _RepReportsScreenState extends State<RepReportsScreen> {
  DateTime _startDate = DateTime.now().subtract(const Duration(days: 2));
  DateTime _endDate = DateTime.now();

  List<QueryDocumentSnapshot> _currentFilteredDocs = [];
  double _totalCashInPeriod = 0; 
  double _unsettledCash = 0;     
  int _success = 0;
  int _failed = 0;
  int _pending = 0; // عداد جديد للطلبات اللي لسه في الطريق

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F6),
      appBar: AppBar(
        title: Text("تقارير العهدة والتحصيل", 
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18.sp, color: Colors.white)),
        backgroundColor: const Color(0xFF1B5E20),
        centerTitle: true,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: Icon(Icons.picture_as_pdf, color: Colors.white, size: 22.sp),
            onPressed: () => _generateReportPDF(),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildFilterHeader(),
          Expanded(child: _buildReportContent()),
        ],
      ),
    );
  }

  Widget _buildFilterHeader() {
    return Container(
      padding: EdgeInsets.symmetric(vertical: 15.sp, horizontal: 10.sp),
      decoration: const BoxDecoration(
        color: Color(0xFF1B5E20),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(25)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _datePickerBox("من تاريخ", _startDate, (date) => setState(() => _startDate = date)),
          Icon(Icons.compare_arrows, color: Colors.white54, size: 24.sp),
          _datePickerBox("إلى تاريخ", _endDate, (date) => setState(() => _endDate = date)),
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
          lastDate: DateTime.now(),
        );
        if (picked != null) onSelect(picked);
      },
      child: Column(
        children: [
          Text(label, style: TextStyle(color: Colors.white70, fontSize: 12.sp)),
          SizedBox(height: 6.sp),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 14.sp, vertical: 8.sp),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white30),
            ),
            child: Text(DateFormat('yyyy/MM/dd').format(date),
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13.sp)),
          ),
        ],
      ),
    );
  }

  Widget _buildReportContent() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('waitingdelivery')
          .where('repCode', isEqualTo: widget.repCode)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: Color(0xFF1B5E20)));

        final allDocs = snapshot.data?.docs ?? [];
        
        _currentFilteredDocs = allDocs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          // لو الطلب لسه جديد بنشوف تاريخ التكليف assignedAt، لو خلص بنشوف completedAt
          Timestamp? ts = data['completedAt'] as Timestamp? ?? data['assignedAt'] as Timestamp?;
          if (ts == null) return false;
          DateTime orderDate = ts.toDate();
          return orderDate.isAfter(_startDate.subtract(const Duration(days: 1))) && 
                 orderDate.isBefore(_endDate.add(const Duration(days: 1)));
        }).toList();

        _totalCashInPeriod = 0;
        _unsettledCash = 0;
        _success = 0;
        _failed = 0;
        _pending = 0;

        for (var doc in _currentFilteredDocs) {
          final data = doc.data() as Map<String, dynamic>;
          double amount = (data['netTotal'] ?? data['total'] ?? 0.0).toDouble();
          bool isSettled = data['isSettled'] ?? false;
          String status = data['deliveryTaskStatus'] ?? 'pending';

          if (status == 'delivered') {
            _totalCashInPeriod += amount;
            _success++;
            if (!isSettled) _unsettledCash += amount; 
          } else if (status == 'failed') {
            _failed++;
          } else {
            _pending++; // عداد المهام اللي لسه في الطريق
          }
        }

        return ListView(
          padding: EdgeInsets.all(15.sp),
          children: [
            _buildSummaryDashboard(),
            SizedBox(height: 20.sp),
            _buildSectionTitle(),
            const Divider(thickness: 1.5),
            _buildOrdersList(),
          ],
        );
      },
    );
  }

  Widget _buildSummaryDashboard() {
    return Column(
      children: [
        _statCard("عهدة كاش (غير موردة)", "${_unsettledCash.toStringAsFixed(1)}", " ج.م", Icons.warning_amber_rounded, Colors.orange[800]!, true),
        SizedBox(height: 12.sp),
        Row(
          children: [
            _statCard("تم تسليمه", "$_success", " طلب", Icons.check_circle, Colors.green[700]!, false),
            SizedBox(width: 12.sp),
            _statCard("قيد التوصيل", "$_pending", " طلب", Icons.directions_bike, Colors.blue[700]!, false),
          ],
        ),
      ],
    );
  }

  Widget _statCard(String title, String value, String unit, IconData icon, Color color, bool isFullWidth) {
    return Expanded(
      flex: isFullWidth ? 0 : 1,
      child: Container(
        width: isFullWidth ? double.infinity : null,
        padding: EdgeInsets.all(16.sp),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: color.withOpacity(0.1), blurRadius: 15, offset: const Offset(0, 8))],
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22.sp,
              backgroundColor: color.withOpacity(0.1), 
              child: Icon(icon, color: color, size: 24.sp)
            ),
            SizedBox(width: 15.sp),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: 11.sp, color: Colors.grey[600], fontWeight: FontWeight.bold)),
                  SizedBox(height: 4.sp),
                  RichText(text: TextSpan(children: [
                    TextSpan(text: value, style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w900, color: Colors.black)),
                    TextSpan(text: " $unit", style: TextStyle(fontSize: 11.sp, color: Colors.black54, fontWeight: FontWeight.bold)),
                  ])),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text("سجل العمليات", style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold, color: Colors.blueGrey[900])),
        Container(
          padding: EdgeInsets.symmetric(horizontal: 12.sp, vertical: 4.sp),
          decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(20)),
          child: Text("${_currentFilteredDocs.length} حركة", style: TextStyle(color: Colors.black87, fontSize: 11.sp, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  Widget _buildOrdersList() {
    if (_currentFilteredDocs.isEmpty) {
      return Center(child: Padding(padding: EdgeInsets.only(top: 50.sp), child: Text("لا توجد بيانات")));
    }
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _currentFilteredDocs.length,
      itemBuilder: (context, index) {
        var data = _currentFilteredDocs[index].data() as Map<String, dynamic>;
        String status = data['deliveryTaskStatus'] ?? 'pending';
        bool isDelivered = status == 'delivered';
        bool isFailed = status == 'failed';
        bool isSettled = data['isSettled'] ?? false;
        
        Timestamp? ts = data['completedAt'] as Timestamp? ?? data['assignedAt'] as Timestamp?;
        DateTime date = ts?.toDate() ?? DateTime.now();

        // تحديد اللون والأيقونة بناءً على الحالة الحقيقية
        Color statusColor = isDelivered ? Colors.green : (isFailed ? Colors.red : Colors.blue);
        IconData statusIcon = isDelivered ? (isSettled ? Icons.verified : Icons.payments) : (isFailed ? Icons.assignment_return : Icons.hourglass_top);
        String statusText = isSettled ? "تم التوريد" : (isDelivered ? "عهدة معك" : (isFailed ? "مرتجع" : "قيد التوصيل"));

        return Container(
          margin: EdgeInsets.symmetric(vertical: 8.sp),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10)],
            border: Border.all(color: statusColor.withOpacity(0.1)),
          ),
          child: ListTile(
            contentPadding: EdgeInsets.symmetric(horizontal: 15.sp, vertical: 8.sp),
            leading: CircleAvatar(
              backgroundColor: statusColor.withOpacity(0.1),
              radius: 20.sp,
              child: Icon(statusIcon, color: statusColor, size: 20.sp),
            ),
            title: Text("طلب #${_currentFilteredDocs[index].id.substring(0, 6).toUpperCase()}", 
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.sp)),
            subtitle: Text(DateFormat('yyyy/MM/dd - hh:mm a').format(date), style: TextStyle(fontSize: 11.sp, color: Colors.grey[600])),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text("${(data['netTotal'] ?? data['total'] ?? 0).toStringAsFixed(1)} ج.م", 
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15.sp, color: isFailed ? Colors.red : Colors.black)),
                SizedBox(height: 5.sp),
                Text(statusText,
                  style: TextStyle(fontSize: 10.sp, fontWeight: FontWeight.bold, color: statusColor)),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _generateReportPDF() async {
    // ... نفس كود الـ PDF السابق مع إضافة عمود الحالة "قيد التوصيل" ...
  }
}

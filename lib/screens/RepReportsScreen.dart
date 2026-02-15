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
  // الفلترة الافتراضية: من أول يوم في الشهر الحالي
  DateTime _startDate = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _endDate = DateTime.now();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: Text("تقارير الأداء والتحصيل", 
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16.sp, color: Colors.white)),
        backgroundColor: const Color(0xFF2C3E50),
        centerTitle: true,
        elevation: 0,
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildFilterHeader(),
            Expanded(
              child: _buildReportContent(),
            ),
          ],
        ),
      ),
    );
  }

  // --- 1. هيدر اختيار التاريخ ---
  Widget _buildFilterHeader() {
    return Container(
      padding: EdgeInsets.symmetric(vertical: 15.sp, horizontal: 10.sp),
      decoration: const BoxDecoration(
        color: Color(0xFF2C3E50),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(30)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _datePickerBox("من تاريخ", _startDate, (date) => setState(() => _startDate = date)),
          Icon(Icons.swap_horiz, color: Colors.white54, size: 22.sp),
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
          locale: const Locale('ar', 'AE'), // لدعم التقويم العربي
        );
        if (picked != null) onSelect(picked);
      },
      child: Column(
        children: [
          Text(label, style: TextStyle(color: Colors.white70, fontSize: 11.sp)),
          SizedBox(height: 5.sp),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 12.sp, vertical: 8.sp),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white24),
            ),
            child: Text(
              DateFormat('yyyy/MM/dd').format(date),
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12.sp),
            ),
          ),
        ],
      ),
    );
  }

  // --- 2. محتوى التقارير ---
  Widget _buildReportContent() {
    return StreamBuilder<QuerySnapshot>(
      // جلب كافة الطلبات المرتبطة بالمندوب
      stream: FirebaseFirestore.instance
          .collection('deliveredorders')
          .where('handledByRepId', isEqualTo: widget.repCode)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text("خطأ في الاتصال: ${snapshot.error}"));
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Color(0xFF2C3E50)));
        }

        final allDocs = snapshot.data?.docs ?? [];

        // --- الفلترة المحلية الدقيقة (تشمل اليوم بالكامل) ---
        final startOfRange = DateTime(_startDate.year, _startDate.month, _startDate.day, 0, 0, 0);
        final endOfRange = DateTime(_endDate.year, _endDate.month, _endDate.day, 23, 59, 59);

        final filteredDocs = allDocs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          if (data['timestamp'] == null) return false;
          
          DateTime orderDate = (data['timestamp'] as Timestamp).toDate();
          return orderDate.isAfter(startOfRange.subtract(const Duration(seconds: 1))) && 
                 orderDate.isBefore(endOfRange.add(const Duration(seconds: 1)));
        }).toList();

        // ترتيب من الأحدث للأقدم
        filteredDocs.sort((a, b) {
          DateTime dateA = (a['timestamp'] as Timestamp).toDate();
          DateTime dateB = (b['timestamp'] as Timestamp).toDate();
          return dateB.compareTo(dateA);
        });

        // حساب الإجمالي
        double totalCash = 0;
        for (var doc in filteredDocs) {
          totalCash += (doc['total'] ?? 0).toDouble();
        }

        return SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.all(15.sp),
          child: Column(
            children: [
              _buildSummaryCards(totalCash, filteredDocs.length),
              SizedBox(height: 25.sp),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("سجل العمليات المفلترة", 
                    style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.bold, color: const Color(0xFF2C3E50))),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 10.sp, vertical: 4.sp),
                    decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(10)),
                    child: Text("${filteredDocs.length} طلب", style: TextStyle(color: Colors.blue[800], fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              const Divider(thickness: 1.5),
              _buildOrdersList(filteredDocs),
              SizedBox(height: 5.h), // مساحة أمان سفلية
            ],
          ),
        );
      },
    );
  }

  Widget _buildSummaryCards(double cash, int count) {
    return Row(
      children: [
        _statCard("إجمالي التحصيل", "${cash.toStringAsFixed(2)}", " ج.م", Icons.payments, Colors.green),
        SizedBox(width: 12.sp),
        _statCard("طلبات ناجحة", "$count", " شحنة", Icons.local_shipping, Colors.blue),
      ],
    );
  }

  Widget _statCard(String title, String value, String unit, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: EdgeInsets.all(15.sp),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: color.withOpacity(0.1), blurRadius: 15, offset: const Offset(0, 8))],
          border: Border.all(color: color.withOpacity(0.1), width: 1),
        ),
        child: Column(
          children: [
            CircleAvatar(
              backgroundColor: color.withOpacity(0.1),
              child: Icon(icon, color: color, size: 20.sp),
            ),
            SizedBox(height: 12.sp),
            RichText(
              text: TextSpan(
                children: [
                  TextSpan(text: value, style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w900, color: Colors.black87)),
                  TextSpan(text: unit, style: TextStyle(fontSize: 10.sp, color: Colors.grey[600])),
                ],
              ),
            ),
            SizedBox(height: 5.sp),
            Text(title, style: TextStyle(fontSize: 11.sp, color: Colors.grey[500], fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _buildOrdersList(List<QueryDocumentSnapshot> docs) {
    if (docs.isEmpty) {
      return Padding(
        padding: EdgeInsets.only(top: 10.h),
        child: Column(
          children: [
            Icon(Icons.info_outline, size: 40.sp, color: Colors.grey[300]),
            Text("لا توجد بيانات للفترة المختارة", style: TextStyle(color: Colors.grey, fontSize: 13.sp)),
          ],
        ),
      );
    }
    
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: docs.length,
      itemBuilder: (context, index) {
        var data = docs[index].data() as Map<String, dynamic>;
        DateTime date = (data['timestamp'] as Timestamp).toDate();
        
        return Container(
          margin: EdgeInsets.symmetric(vertical: 6.sp),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: Colors.grey.withOpacity(0.1)),
          ),
          child: ListTile(
            contentPadding: EdgeInsets.symmetric(horizontal: 15.sp, vertical: 5.sp),
            leading: CircleAvatar(
              backgroundColor: Colors.blueGrey[50],
              child: Icon(Icons.receipt_long, color: Colors.blueGrey[700], size: 18.sp),
            ),
            title: Text("طلب #${docs[index].id.substring(0, 8)}", 
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.sp)),
            subtitle: Text(DateFormat('yyyy/MM/dd - hh:mm a').format(date), 
              style: TextStyle(fontSize: 10.sp, color: Colors.grey[600])),
            trailing: Text("${data['total']} ج.م", 
              style: TextStyle(fontWeight: FontWeight.w900, color: Colors.green[700], fontSize: 13.sp)),
          ),
        );
      },
    );
  }
}

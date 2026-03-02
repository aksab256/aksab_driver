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
  DateTime _startDate = DateTime.now().subtract(const Duration(hours: 48));
  DateTime _endDate = DateTime.now();

  List<QueryDocumentSnapshot> _currentFilteredDocs = [];
  double _totalCashInPeriod = 0; 
  double _unsettledCash = 0;     
  int _success = 0;
  int _failed = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F6),
      appBar: AppBar(
        title: Text("تقارير العهدة والتحصيل", 
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16.sp, color: Colors.white)),
        backgroundColor: const Color(0xFF1B5E20),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: Icon(Icons.picture_as_pdf, color: Colors.white, size: 20.sp),
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
      padding: EdgeInsets.symmetric(vertical: 12.sp, horizontal: 10.sp),
      decoration: const BoxDecoration(
        color: Color(0xFF1B5E20),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(25)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _datePickerBox("من تاريخ", _startDate, (date) => setState(() => _startDate = date)),
          Icon(Icons.arrow_forward_ios, color: Colors.white54, size: 15.sp),
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
          Text(label, style: TextStyle(color: Colors.white70, fontSize: 10.sp)),
          SizedBox(height: 5.sp),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 12.sp, vertical: 6.sp),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white24),
            ),
            child: Text(DateFormat('yyyy/MM/dd').format(date),
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11.sp)),
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
          .orderBy('completedAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError) return Center(child: Text("خطأ في تحميل البيانات"));

        final allDocs = snapshot.data?.docs ?? [];
        
        _currentFilteredDocs = allDocs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          if (data['completedAt'] == null) return false;
          DateTime orderDate = (data['completedAt'] as Timestamp).toDate();
          return orderDate.isAfter(_startDate.subtract(const Duration(seconds: 1))) && 
                 orderDate.isBefore(_endDate.add(const Duration(days: 1)));
        }).toList();

        _totalCashInPeriod = 0;
        _unsettledCash = 0;
        _success = 0;
        _failed = 0;

        for (var doc in _currentFilteredDocs) {
          final data = doc.data() as Map<String, dynamic>;
          double amount = (data['netTotal'] ?? data['total'] ?? 0.0).toDouble();
          bool isSettled = data['isSettled'] ?? false;

          if (data['deliveryTaskStatus'] == 'delivered') {
            _totalCashInPeriod += amount;
            _success++;
            if (!isSettled) _unsettledCash += amount; 
          } else if (data['deliveryTaskStatus'] == 'failed') {
            _failed++;
          }
        }

        return ListView(
          padding: EdgeInsets.all(12.sp),
          children: [
            _buildSummaryDashboard(),
            SizedBox(height: 15.sp),
            _buildSectionTitle(),
            const Divider(),
            _buildOrdersList(),
          ],
        );
      },
    );
  }

  Widget _buildSummaryDashboard() {
    return Column(
      children: [
        _statCard("عهدة كاش حالية (غير موردة)", "${_unsettledCash.toStringAsFixed(1)}", " ج.م", Icons.warning_amber_rounded, Colors.orange[800]!, true),
        SizedBox(height: 10.sp),
        Row(
          children: [
            _statCard("إجمالي تحصيل", "${_totalCashInPeriod.toStringAsFixed(1)}", " ج.م", Icons.account_balance_wallet, Colors.green[700]!, false),
            SizedBox(width: 8.sp),
            _statCard("مرتجع", "$_failed", " طلب", Icons.assignment_return, Colors.red[700]!, false),
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
        padding: EdgeInsets.all(14.sp),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
          boxShadow: [BoxShadow(color: color.withOpacity(0.05), blurRadius: 10)],
          border: Border.all(color: color.withOpacity(0.1)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20.sp),
            SizedBox(width: 10.sp),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: 9.sp, color: Colors.grey[600])),
                  RichText(text: TextSpan(children: [
                    TextSpan(text: value, style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w900, color: Colors.black)),
                    TextSpan(text: " $unit", style: TextStyle(fontSize: 9.sp, color: Colors.black54)),
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
        Text("سجل عمليات العهدة", style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.bold)),
        Container(
          padding: EdgeInsets.symmetric(horizontal: 10.sp, vertical: 2.sp),
          decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(15)),
          child: Text("${_currentFilteredDocs.length} حركة", style: TextStyle(fontSize: 9.sp, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  Widget _buildOrdersList() {
    if (_currentFilteredDocs.isEmpty) {
      return Center(child: Padding(
        padding: EdgeInsets.only(top: 20.sp),
        child: Text("لا توجد بيانات للفترة المحددة"),
      ));
    }
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _currentFilteredDocs.length,
      itemBuilder: (context, index) {
        var data = _currentFilteredDocs[index].data() as Map<String, dynamic>;
        bool isDelivered = data['deliveryTaskStatus'] == 'delivered';
        bool isSettled = data['isSettled'] ?? false;
        DateTime date = (data['completedAt'] as Timestamp).toDate();

        return Card(
          elevation: 0,
          margin: EdgeInsets.symmetric(vertical: 5.sp),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade100)),
          child: ListTile(
            leading: Icon(isDelivered ? Icons.circle : Icons.error_outline, 
                    color: isDelivered ? (isSettled ? Colors.blue : Colors.orange) : Colors.red, size: 12.sp),
            title: Text("طلب #${_currentFilteredDocs[index].id.substring(0, 6)}", 
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.sp)),
            subtitle: Text(DateFormat('dd/MM hh:mm a').format(date), style: TextStyle(fontSize: 8.sp)),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text("${(data['netTotal'] ?? 0).toStringAsFixed(1)} ج.م", 
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.sp)),
                Text(isSettled ? "تم التوريد" : (isDelivered ? "عهدة معك" : "مرتجع"),
                  style: TextStyle(fontSize: 8.sp, color: isSettled ? Colors.blue : Colors.orange[800])),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _generateReportPDF() async {
    if (_currentFilteredDocs.isEmpty) return;
    
    final pdf = pw.Document();
    final font = await PdfGoogleFonts.cairoRegular();
    final boldFont = await PdfGoogleFonts.cairoBold();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Header(level: 0, child: pw.Center(child: pw.Text("تقرير تحصيل عهدة - نظام أكسب", style: pw.TextStyle(font: boldFont, fontSize: 22)))),
                pw.SizedBox(height: 10),
                pw.Text("كود المندوب: ${widget.repCode}", style: pw.TextStyle(font: font, fontSize: 14)),
                pw.Text("الفترة: ${DateFormat('yyyy/MM/dd').format(_startDate)} - ${DateFormat('yyyy/MM/dd').format(_endDate)}", style: pw.TextStyle(font: font, fontSize: 12)),
                pw.Divider(),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text("إجمالي التحصيل: ${_totalCashInPeriod.toStringAsFixed(2)} ج.م", style: pw.TextStyle(font: boldFont, fontSize: 16)),
                    pw.Text("عهدة غير موردة: ${_unsettledCash.toStringAsFixed(2)} ج.م", style: pw.TextStyle(font: boldFont, fontSize: 16, color: PdfColors.orange900)),
                  ],
                ),
                pw.SizedBox(height: 20),
                pw.TableHelper.fromTextArray(
                  headers: ['رقم الطلب', 'التاريخ', 'الحالة', 'التوريد', 'المبلغ'],
                  data: _currentFilteredDocs.map((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    return [
                      doc.id.substring(0, 8),
                      DateFormat('yyyy/MM/dd').format((data['completedAt'] as Timestamp).toDate()),
                      data['deliveryTaskStatus'] == 'delivered' ? 'تم التسليم' : 'مرتجع',
                      data['isSettled'] == true ? 'تم التوريد' : 'عهدة طرفه',
                      "${data['netTotal'] ?? data['total'] ?? 0} ج.م"
                    ];
                  }).toList(),
                  headerStyle: pw.TextStyle(font: boldFont, color: PdfColors.white),
                  headerDecoration: const pw.BoxDecoration(color: PdfColors.green900),
                  cellStyle: pw.TextStyle(font: font),
                  cellAlignment: pw.Alignment.center,
                ),
                pw.SizedBox(height: 30),
                pw.Text("إقرار: أقر أنا المندوب المذكور أعلاه بصحة البيانات وأن المبالغ (غير الموردة) هي في عهدتي الشخصية.", style: pw.TextStyle(font: font, fontSize: 10)),
                pw.SizedBox(height: 20),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                  children: [
                    pw.Text("توقيع المندوب: ....................", style: pw.TextStyle(font: font, fontSize: 12)),
                    pw.Text("توقيع المحاسب: ....................", style: pw.TextStyle(font: font, fontSize: 12)),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
    await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => pdf.save());
  }
}

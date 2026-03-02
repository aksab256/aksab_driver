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
  double _totalCash = 0;
  int _success = 0;
  int _failed = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F6),
      appBar: AppBar(
        title: Text("تقارير العهدة والتحصيل", 
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18.sp, color: Colors.white)),
        backgroundColor: const Color(0xFF1B5E20),
        centerTitle: true,
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
          .orderBy('completedAt', descending: true)
          .limit(100)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text("خطأ: ${snapshot.error}"));
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: Color(0xFF1B5E20)));

        final allDocs = snapshot.data?.docs ?? [];
        
        _currentFilteredDocs = allDocs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          if (data['completedAt'] == null) return false;
          DateTime orderDate = (data['completedAt'] as Timestamp).toDate();
          return orderDate.isAfter(_startDate.subtract(const Duration(seconds: 1))) && 
                 orderDate.isBefore(_endDate.add(const Duration(days: 1)));
        }).toList();

        _totalCash = 0;
        _success = 0;
        _failed = 0;

        for (var doc in _currentFilteredDocs) {
          final data = doc.data() as Map<String, dynamic>;
          if (data['deliveryTaskStatus'] == 'delivered') {
            _totalCash += (data['netTotal'] ?? data['total'] ?? 0.0).toDouble();
            _success++;
          } else if (data['deliveryTaskStatus'] == 'failed') {
            _failed++;
          }
        }

        return ListView(
          padding: EdgeInsets.all(15.sp),
          children: [
            _buildSummaryDashboard(),
            SizedBox(height: 20.sp),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("سجل العمليات", style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold, color: Colors.blueGrey[900])),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 12.sp, vertical: 4.sp),
                  decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(20)),
                  child: Text("${_currentFilteredDocs.length} عملية", style: TextStyle(color: Colors.black87, fontSize: 11.sp, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
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
        _statCard("إجمالي الكاش (العهدة الحالية)", "${_totalCash.toStringAsFixed(2)}", " ج.م", Icons.payments, Colors.green, true),
        SizedBox(height: 12.sp),
        Row(
          children: [
            _statCard("تم تسليمه", "$_success", " طلب", Icons.check_circle, Colors.blue, false),
            SizedBox(width: 12.sp),
            _statCard("المرتجعات", "$_failed", " طلب", Icons.assignment_return, Colors.orange, false),
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

  Widget _buildOrdersList() {
    if (_currentFilteredDocs.isEmpty) return Center(child: Padding(
      padding: EdgeInsets.only(top: 10.h),
      child: Text("لا توجد بيانات للفترة المحددة", style: TextStyle(fontSize: 14.sp, color: Colors.grey)),
    ));

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _currentFilteredDocs.length,
      itemBuilder: (context, index) {
        var data = _currentFilteredDocs[index].data() as Map<String, dynamic>;
        bool isDelivered = data['deliveryTaskStatus'] == 'delivered';
        bool isSettled = data['isSettled'] ?? false;
        DateTime date = (data['completedAt'] as Timestamp).toDate();

        return Container(
          margin: EdgeInsets.symmetric(vertical: 8.sp),
          padding: EdgeInsets.all(4.sp),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10)],
            border: Border.all(color: isDelivered ? Colors.transparent : Colors.red.withOpacity(0.3), width: 1.5),
          ),
          child: ListTile(
            contentPadding: EdgeInsets.symmetric(horizontal: 15.sp, vertical: 8.sp),
            leading: CircleAvatar(
              backgroundColor: isDelivered ? Colors.green[50] : Colors.orange[50],
              radius: 20.sp,
              child: Icon(isDelivered ? Icons.receipt_long : Icons.assignment_return, 
                color: isDelivered ? Colors.green[700] : Colors.orange[800], size: 20.sp),
            ),
            title: Text("طلب #${_currentFilteredDocs[index].id.substring(0, 6).toUpperCase()}", 
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.sp)),
            subtitle: Padding(
              padding: EdgeInsets.only(top: 5.sp),
              child: Text(DateFormat('yyyy/MM/dd - hh:mm a').format(date), style: TextStyle(fontSize: 11.sp, color: Colors.grey[600])),
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text("${(data['netTotal'] ?? data['total'] ?? 0).toStringAsFixed(1)} ج.م", 
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15.sp, color: isDelivered ? Colors.black : Colors.red)),
                SizedBox(height: 5.sp),
                isSettled 
                  ? Container(
                      padding: EdgeInsets.symmetric(horizontal: 8.sp, vertical: 2.sp),
                      decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(8)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text("مورد ", style: TextStyle(color: Colors.blue[700], fontSize: 9.sp, fontWeight: FontWeight.bold)),
                        Icon(Icons.verified, color: Colors.blue, size: 12.sp),
                      ]),
                    )
                  : Container(
                      padding: EdgeInsets.symmetric(horizontal: 8.sp, vertical: 2.sp),
                      decoration: BoxDecoration(color: Colors.orange[50], borderRadius: BorderRadius.circular(8)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text("عهدة ", style: TextStyle(color: Colors.orange[900], fontSize: 9.sp, fontWeight: FontWeight.bold)),
                        Icon(Icons.pending_actions, color: Colors.orange[800], size: 12.sp),
                      ]),
                    ),
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
                pw.Text("تاريخ التقرير: ${DateFormat('yyyy/MM/dd hh:mm a').format(DateTime.now())}", style: pw.TextStyle(font: font, fontSize: 12)),
                pw.Divider(),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text("إجمالي العهدة: ${_totalCash.toStringAsFixed(2)} ج.م", style: pw.TextStyle(font: boldFont, fontSize: 16, color: PdfColors.green900)),
                    pw.Text("ناجح: $_success", style: pw.TextStyle(font: font, fontSize: 14)),
                    pw.Text("مرتجع: $_failed", style: pw.TextStyle(font: font, fontSize: 14)),
                  ],
                ),
                pw.SizedBox(height: 20),
                pw.TableHelper.fromTextArray(
                  headers: ['رقم الطلب', 'التاريخ', 'الحالة', 'المبلغ'],
                  data: _currentFilteredDocs.map((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    return [
                      doc.id.substring(0, 8),
                      DateFormat('yyyy/MM/dd').format((data['completedAt'] as Timestamp).toDate()),
                      data['deliveryTaskStatus'] == 'delivered' ? 'تم التسليم' : 'مرتجع',
                      "${data['netTotal'] ?? data['total'] ?? 0} ج.م"
                    ];
                  }).toList(),
                  headerStyle: pw.TextStyle(font: boldFont, color: PdfColors.white),
                  headerDecoration: const pw.BoxDecoration(color: PdfColors.green900),
                  cellStyle: pw.TextStyle(font: font),
                  cellAlignment: pw.Alignment.center,
                ),
                pw.SizedBox(height: 30),
                pw.Text("توقيع المندوب: ....................", style: pw.TextStyle(font: font, fontSize: 12)),
              ],
            ),
          );
        },
      ),
    );
    await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => pdf.save());
  }
}

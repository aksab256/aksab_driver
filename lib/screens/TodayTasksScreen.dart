import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:sizer/sizer.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class TodayTasksScreen extends StatefulWidget {
  final String repCode;

  const TodayTasksScreen({super.key, required this.repCode});

  @override
  State<TodayTasksScreen> createState() => _TodayTasksScreenState();
}

class _TodayTasksScreenState extends State<TodayTasksScreen> {
  bool _isProcessing = false;

  // --- 1. التوجيه الخارجي (بدون طلب أذونات داخل التطبيق) ---
  Future<void> _navigateToCustomer(Map<String, dynamic>? location) async {
    if (location == null || location['lat'] == null || location['lng'] == null) {
      _showSnackBar("موقع العميل غير متوفر");
      return;
    }
    final double lat = (location['lat'] as num).toDouble();
    final double lng = (location['lng'] as num).toDouble();
    
    // روابط الخرائط الخارجية
    final Uri googleUri = Uri.parse("google.navigation:q=$lat,$lng");
    final Uri appleUri = Uri.parse("https://maps.apple.com/?q=$lat,$lng");

    try {
      if (Platform.isAndroid) {
        // نفتح جوجل ماب مباشرة، هو اللي هيتعامل مع اللوكيشن
        await launchUrl(googleUri, mode: LaunchMode.externalNonBrowserApplication);
      } else {
        await launchUrl(appleUri);
      }
    } catch (e) {
      _showSnackBar("تعذر فتح تطبيق الخرائط");
    }
  }

  // --- 2. طباعة الفاتورة PDF ---
  Future<void> _printInvoice(Map<String, dynamic> order) async {
    final pdf = pw.Document();
    final buyer = order['buyer'] ?? {};
    final items = order['items'] as List? ?? [];

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Padding(
              padding: const pw.EdgeInsets.all(20),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Center(child: pw.Text("فاتورة طلب: ${order['orderId'] ?? '---'}", style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold))),
                  pw.Divider(),
                  pw.Text("المشتري: ${buyer['name'] ?? '-'}"),
                  pw.Text("العنوان: ${buyer['address'] ?? '-'}"),
                  pw.SizedBox(height: 20),
                  pw.TableHelper.fromTextArray(
                    headers: ['المنتج', 'الكمية', 'السعر'],
                    data: items.map((i) => [i['name'], i['quantity'], "${i['price']} ج.م"]).toList(),
                  ),
                  pw.SizedBox(height: 20),
                  pw.Divider(),
                  pw.Align(alignment: pw.Alignment.centerLeft, child: pw.Text("الإجمالي: ${order['total']} ج.م", style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold))),
                ],
              ),
            ),
          );
        },
      ),
    );
    await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => pdf.save());
  }

  // --- 3. نافذة تفاصيل الفاتورة (BottomSheet) ---
  void _showOrderDetails(Map<String, dynamic> order) {
    final items = order['items'] as List? ?? [];
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
        padding: EdgeInsets.fromLTRB(15.sp, 10.sp, 15.sp, 20.sp),
        height: 75.h,
        child: Column(
          children: [
            Container(width: 40, height: 5, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10))),
            SizedBox(height: 15.sp),
            Text("تفاصيل الطلب", style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold, color: Colors.blue[900])),
            const Divider(),
            Expanded(
              child: ListView.builder(
                itemCount: items.length,
                itemBuilder: (context, i) => Card(
                  elevation: 0,
                  color: Colors.grey[50],
                  margin: EdgeInsets.symmetric(vertical: 5.sp),
                  child: ListTile(
                    title: Text(items[i]['name'] ?? "-", style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600)),
                    subtitle: Text("البائع: ${items[i]['sellerName'] ?? '-'}", style: TextStyle(fontSize: 10.sp)),
                    trailing: Text("x${items[i]['quantity']}", style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.bold, color: Colors.blue)),
                  ),
                ),
              ),
            ),
            SizedBox(height: 10.sp),
            SizedBox(
              width: double.infinity,
              height: 45.sp,
              child: ElevatedButton.icon(
                onPressed: () => _printInvoice(order),
                icon: const Icon(Icons.print),
                label: Text("طباعة الفاتورة", style: TextStyle(fontSize: 13.sp)),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
              ),
            )
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FA),
      appBar: AppBar(
        title: const Text("مهام اليوم التوصيل", style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: const Color(0xFF007BFF),
        elevation: 0,
      ),
      body: SafeArea(
        child: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('waitingdelivery')
              .where('repCode', isEqualTo: widget.repCode)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return _buildEmptyState();
            
            return ListView.builder(
              padding: EdgeInsets.all(10.sp),
              itemCount: snapshot.data!.docs.length,
              itemBuilder: (context, index) {
                var doc = snapshot.data!.docs[index];
                return _buildTaskCard(doc.id, doc.data() as Map<String, dynamic>);
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildTaskCard(String docId, Map<String, dynamic> order) {
    final buyer = order['buyer'] ?? {};
    final total = (order['total'] ?? 0.0).toDouble();

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      margin: EdgeInsets.only(bottom: 12.sp),
      elevation: 3,
      child: Column(
        children: [
          Container(
            padding: EdgeInsets.all(12.sp),
            decoration: BoxDecoration(color: Colors.blue[600], borderRadius: const BorderRadius.vertical(top: Radius.circular(20))),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("رقم الطلب: #${docId.substring(0, 6)}", style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.bold, color: Colors.white)),
                IconButton(
                  icon: const Icon(Icons.directions, color: Colors.white, size: 28),
                  onPressed: () => _navigateToCustomer(buyer['location']),
                )
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.all(15.sp),
            child: Column(
              children: [
                _rowInfo("اسم العميل:", buyer['name'] ?? "-", fontSize: 13.sp),
                _rowInfo("العنوان:", buyer['address'] ?? "غير محدد", fontSize: 12.sp),
                _rowInfo("المبلغ المطلوب:", "${total.toStringAsFixed(2)} ج.م", isTotal: true, fontSize: 16.sp),
                const Divider(height: 30),
                Row(
                  children: [
                    _smallActionBtn("اتصال بالعميل", Colors.green, Icons.phone, () => launchUrl(Uri.parse("tel:${buyer['phone']}"))),
                    SizedBox(width: 10.sp),
                    _smallActionBtn("عرض الفاتورة", Colors.orange, Icons.receipt_long, () => _showOrderDetails(order)),
                  ],
                ),
                SizedBox(height: 15.sp),
                _isProcessing 
                ? const LinearProgressIndicator()
                : Row(
                  children: [
                    _mainActionBtn("تـم التـسليم", Colors.green, Icons.check_circle, () => _updateStatus(docId, order, 'delivered')),
                    SizedBox(width: 10.sp),
                    _mainActionBtn("فشل الشحن", Colors.red, Icons.cancel, () => _updateStatus(docId, order, 'failed')),
                  ],
                )
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _rowInfo(String label, String value, {bool isTotal = false, double fontSize = 12}) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4.sp),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey[700], fontSize: fontSize)),
          Expanded(child: Text(value, textAlign: TextAlign.end, style: TextStyle(fontWeight: isTotal ? FontWeight.bold : FontWeight.normal, color: isTotal ? Colors.blue[900] : Colors.black, fontSize: fontSize))),
        ],
      ),
    );
  }

  Widget _smallActionBtn(String label, Color color, IconData icon, VoidCallback onTap) {
    return Expanded(
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 16.sp, color: color),
        label: Text(label, style: TextStyle(color: color, fontSize: 10.sp, fontWeight: FontWeight.bold)),
        style: OutlinedButton.styleFrom(side: BorderSide(color: color), padding: EdgeInsets.symmetric(vertical: 10.sp), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
      ),
    );
  }

  Widget _mainActionBtn(String label, Color color, IconData icon, VoidCallback onTap) {
    return Expanded(
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 18.sp),
        label: Text(label, style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.bold)),
        style: ElevatedButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white, padding: EdgeInsets.symmetric(vertical: 14.sp), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
      ),
    );
  }

  void _showSnackBar(String msg) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg, style: const TextStyle(fontWeight: FontWeight.bold)), behavior: SnackBarBehavior.floating, backgroundColor: Colors.blueGrey[800]));
  }

  Widget _buildEmptyState() {
    return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.inbox_outlined, size: 60.sp, color: Colors.grey[400]), SizedBox(height: 15.sp), Text("قائمة المهام فارغة", style: TextStyle(color: Colors.grey, fontSize: 14.sp))]));
  }

  Future<void> _updateStatus(String docId, Map<String, dynamic> orderData, String status) async {
    setState(() => _isProcessing = true);
    try {
      String targetCollection = (status == 'delivered') ? "deliveredorders" : "falseorder";
      WriteBatch batch = FirebaseFirestore.instance.batch();
      DocumentReference oldRef = FirebaseFirestore.instance.collection('waitingdelivery').doc(docId);
      DocumentReference newRef = FirebaseFirestore.instance.collection(targetCollection).doc(docId);
      Map<String, dynamic> finalData = Map.from(orderData);
      finalData['status'] = status;
      finalData['timestamp'] = FieldValue.serverTimestamp();
      finalData['handledByRepId'] = widget.repCode;
      finalData['isSettled'] = false; 
      batch.set(newRef, finalData);
      batch.delete(oldRef);
      await batch.commit();
      _showSnackBar(status == 'delivered' ? "تم التسليم بنجاح ✅" : "تم تسجيل فشل الطلب ❌");
    } catch (e) {
      _showSnackBar("خطأ في التحديث: $e");
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }
}

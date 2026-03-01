import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:sizer/sizer.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:flutter/services.dart';

class TodayTasksScreen extends StatefulWidget {
  final String repCode;
  const TodayTasksScreen({super.key, required this.repCode});

  @override
  State<TodayTasksScreen> createState() => _TodayTasksScreenState();
}

class _TodayTasksScreenState extends State<TodayTasksScreen> {
  bool _isProcessing = false;

  // --- التوجيه للخرائط ---
  Future<void> _navigateToCustomer(Map<String, dynamic>? location) async {
    if (location == null || location['lat'] == null || location['lng'] == null) {
      _showSnackBar("موقع العميل غير متوفر");
      return;
    }
    final double lat = (location['lat'] as num).toDouble();
    final double lng = (location['lng'] as num).toDouble();
    final Uri googleUri = Uri.parse("google.navigation:q=$lat,$lng");
    final Uri appleUri = Uri.parse("https://maps.apple.com/?q=$lat,$lng");

    try {
      if (Platform.isAndroid) {
        await launchUrl(googleUri, mode: LaunchMode.externalNonBrowserApplication);
      } else {
        await launchUrl(appleUri);
      }
    } catch (e) {
      _showSnackBar("تعذر فتح تطبيق الخرائط");
    }
  }

  // --- طباعة الفاتورة (بدون استدعاء ملف خط خارجي) ---
  Future<void> _printInvoice(Map<String, dynamic> order) async {
    try {
      final pdf = pw.Document();
      // ملحوظة: العربي ممكن يظهر مقطع هنا لعدم وجود ملف الخط، 
      // بس المهم دلوقتي إن الـ Build ينجح والـ PDF يفتح.
      
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
                    pw.Center(child: pw.Text("Order Invoice: ${order['orderId'] ?? '---'}", 
                      style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold))),
                    pw.Divider(),
                    pw.Text("Customer: ${buyer['name'] ?? '-'}"),
                    pw.Text("Address: ${buyer['address'] ?? '-'}"),
                    pw.SizedBox(height: 20),
                    pw.TableHelper.fromTextArray(
                      headers: ['Product', 'Qty', 'Price'],
                      data: items.map((i) => [i['name'] ?? '-', i['quantity'] ?? '0', "${i['price'] ?? 0}"]).toList(),
                    ),
                    pw.SizedBox(height: 20),
                    pw.Divider(),
                    pw.Align(alignment: pw.Alignment.centerLeft, 
                      child: pw.Text("Total: ${order['total']} EGP", 
                      style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold))),
                  ],
                ),
              ),
            );
          },
        ),
      );
      await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => pdf.save());
    } catch (e) {
      _showSnackBar("Error in printing: $e");
    }
  }

  // --- تحديث الحالة ---
  Future<void> _updateStatus(String docId, String status) async {
    setState(() => _isProcessing = true);
    try {
      await FirebaseFirestore.instance
          .collection('waitingdelivery')
          .doc(docId)
          .update({
        'deliveryTaskStatus': status,
        'completedAt': FieldValue.serverTimestamp(),
        'isSettled': false,
      });
      _showSnackBar(status == 'delivered' ? "تم التسليم بنجاح ✅" : "تم تسجيل فشل الطلب ❌");
    } catch (e) {
      _showSnackBar("خطأ في التحديث: $e");
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FA),
      appBar: AppBar(
        title: const Text("مهام اليوم التوصيل", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        centerTitle: true,
        backgroundColor: const Color(0xFF007BFF),
        elevation: 0,
      ),
      body: SafeArea(
        child: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('waitingdelivery')
              .where('repCode', isEqualTo: widget.repCode)
              .where('deliveryTaskStatus', isEqualTo: 'pending')
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
                    _smallActionBtn("اتصال", Colors.green, Icons.phone, () => launchUrl(Uri.parse("tel:${buyer['phone']}"))),
                    SizedBox(width: 5.sp),
                    _smallActionBtn("الفاتورة", Colors.orange, Icons.receipt_long, () => _showOrderDetails(order)),
                  ],
                ),
                SizedBox(height: 15.sp),
                _isProcessing 
                ? const LinearProgressIndicator()
                : Row(
                  children: [
                    _mainActionBtn("تـم التـسليم", Colors.green, Icons.check_circle, () => _updateStatus(docId, 'delivered')),
                    SizedBox(width: 10.sp),
                    _mainActionBtn("فشل", Colors.red, Icons.cancel, () => _updateStatus(docId, 'failed')),
                  ],
                )
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showOrderDetails(Map<String, dynamic> order) {
    final items = order['items'] as List? ?? [];
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
        padding: EdgeInsets.symmetric(horizontal: 15.sp),
        height: 60.h,
        child: Column(
          children: [
            SizedBox(height: 12.sp),
            Container(width: 40, height: 5, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10))),
            SizedBox(height: 15.sp),
            Text("تفاصيل الطلب", style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.bold)),
            const Divider(),
            Expanded(
              child: ListView.builder(
                itemCount: items.length,
                itemBuilder: (context, i) => ListTile(
                  title: Text(items[i]['name'] ?? "-", style: TextStyle(fontSize: 12.sp)),
                  trailing: Text("x${items[i]['quantity']}", style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: EdgeInsets.only(bottom: 20.sp, top: 10.sp),
                child: SizedBox(
                  width: 80.w,
                  height: 45.sp,
                  child: ElevatedButton.icon(
                    onPressed: () { Navigator.pop(context); _printInvoice(order); }, 
                    icon: const Icon(Icons.print, color: Colors.white), 
                    label: const Text("طباعة الفاتورة", style: TextStyle(color: Colors.white)),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
                  ),
                ),
              ),
            )
          ],
        ),
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
        icon: Icon(icon, size: 14.sp, color: color),
        label: Text(label, style: TextStyle(color: color, fontSize: 10.sp, fontWeight: FontWeight.bold)),
        style: OutlinedButton.styleFrom(side: BorderSide(color: color), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
      ),
    );
  }

  Widget _mainActionBtn(String label, Color color, IconData icon, VoidCallback onTap) {
    return Expanded(
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 16.sp),
        label: Text(label, style: TextStyle(fontSize: 11.sp, fontWeight: FontWeight.bold)),
        style: ElevatedButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white, padding: EdgeInsets.symmetric(vertical: 12.sp), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
      ),
    );
  }

  void _showSnackBar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));
  }

  Widget _buildEmptyState() {
    return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.done_all, size: 60.sp, color: Colors.green[200]), SizedBox(height: 15.sp), Text("لا توجد مهام معلقة حالياً", style: TextStyle(color: Colors.grey, fontSize: 14.sp))]));
  }
}


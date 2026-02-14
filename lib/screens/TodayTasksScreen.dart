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

  // --- 1. دالة التوجيه (فتح خرائط جوجل أو أبل) ---
  Future<void> _navigateToCustomer(Map<String, dynamic>? location) async {
    if (location == null || location['lat'] == null || location['lng'] == null) {
      _showSnackBar("موقع العميل غير متوفر");
      return;
    }
    final double lat = (location['lat'] as num).toDouble();
    final double lng = (location['lng'] as num).toDouble();
    
    final Uri googleUri = Uri.parse("https://www.google.com/maps/search/?api=1&query=$lat,$lng");
    final Uri appleUri = Uri.parse("https://maps.apple.com/?q=$lat,$lng");

    try {
      if (Platform.isAndroid) {
        await launchUrl(googleUri, mode: LaunchMode.externalApplication);
      } else if (Platform.isIOS) {
        await launchUrl(appleUri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      _showSnackBar("تعذر فتح تطبيق الخرائط");
    }
  }

  // --- 2. دالة طباعة الفاتورة PDF ---
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
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text("فاتورة طلب رقم: ${order['orderId'] ?? 'بدون رقم'}", style: pw.TextStyle(fontSize: 20)),
                pw.Divider(),
                pw.Text("العميل: ${buyer['name'] ?? '-'}"),
                pw.Text("العنوان: ${buyer['address'] ?? '-'}"),
                pw.SizedBox(height: 20),
                pw.Text("المنتجات:"),
                pw.TableHelper.fromTextArray(
                  data: [
                    ['المنتج', 'الكمية', 'السعر'],
                    ...items.map((i) => [i['name'], i['quantity'], i['price']])
                  ],
                ),
                pw.Divider(),
                pw.Text("الإجمالي: ${order['total']} ج.م"),
              ],
            ),
          );
        },
      ),
    );
    await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => pdf.save());
  }

  // --- 3. نافذة تفاصيل الفاتورة ومحتويات الشحنة ---
  void _showOrderDetails(Map<String, dynamic> order) {
    final items = order['items'] as List? ?? [];
    final buyer = order['buyer'] ?? {};

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Container(
        padding: EdgeInsets.all(15.sp),
        height: 75.h,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10)))),
            SizedBox(height: 15.sp),
            Text("محتويات الشحنة", style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.bold)),
            const Divider(),
            Expanded(
              child: ListView.builder(
                itemCount: items.length,
                itemBuilder: (context, i) {
                  var item = items[i];
                  return ListTile(
                    leading: CircleAvatar(child: Text("${i + 1}"), backgroundColor: Colors.blue[50]),
                    title: Text(item['name'] ?? "منتج"),
                    subtitle: Text("البائع: ${item['sellerName'] ?? 'غير محدد'}"),
                    trailing: Text("x${item['quantity']}", style: const TextStyle(fontWeight: FontWeight.bold)),
                  );
                },
              ),
            ),
            const Divider(),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _printInvoice(order),
                    icon: const Icon(Icons.print),
                    label: const Text("طباعة الفاتورة"),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey, foregroundColor: Colors.white),
                  ),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: AppBar(
        title: const Text("مهام اليوم"),
        centerTitle: true,
        backgroundColor: const Color(0xFF007BFF),
        elevation: 0,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('waitingdelivery')
            .where('repCode', isEqualTo: widget.repCode)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return _buildEmptyState();
          }
          return ListView.builder(
            padding: EdgeInsets.all(10.sp),
            itemCount: snapshot.data!.docs.length,
            itemBuilder: (context, index) {
              var doc = snapshot.data!.docs[index];
              var order = doc.data() as Map<String, dynamic>;
              return _buildTaskCard(doc.id, order);
            },
          );
        },
      ),
    );
  }

  Widget _buildTaskCard(String docId, Map<String, dynamic> order) {
    final buyer = order['buyer'] ?? {};
    final total = (order['total'] ?? 0.0).toDouble();

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      margin: EdgeInsets.only(bottom: 12.sp),
      elevation: 4,
      child: Column(
        children: [
          // شريط علوي للكارت
          Container(
            padding: EdgeInsets.symmetric(horizontal: 12.sp, vertical: 8.sp),
            decoration: const BoxDecoration(
              color: Color(0xFFF8F9FA),
              borderRadius: BorderRadius.vertical(top: Radius.circular(15)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("طلب #${docId.substring(0, 6)}", 
                  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue[900])),
                IconButton(
                  icon: const Icon(Icons.map_outlined, color: Colors.blue),
                  onPressed: () => _navigateToCustomer(buyer['location']),
                )
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.all(12.sp),
            child: Column(
              children: [
                _rowInfo("العميل:", buyer['name'] ?? "-"),
                _rowInfo("العنوان:", buyer['address'] ?? "غير محدد"),
                _rowInfo("الإجمالي:", "${total.toStringAsFixed(2)} ج.م", isTotal: true),
                const Divider(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    TextButton.icon(
                      onPressed: () => launchUrl(Uri.parse("tel:${buyer['phone']}")),
                      icon: const Icon(Icons.phone, size: 18, color: Colors.green),
                      label: const Text("اتصال", style: TextStyle(color: Colors.green)),
                    ),
                    TextButton.icon(
                      onPressed: () => _showOrderDetails(order),
                      icon: const Icon(Icons.receipt_long, size: 18, color: Colors.orange),
                      label: const Text("الفاتورة", style: TextStyle(color: Colors.orange)),
                    ),
                  ],
                ),
                SizedBox(height: 10.sp),
                _isProcessing 
                ? const LinearProgressIndicator()
                : Row(
                  children: [
                    _actionBtn("تم التسليم", Colors.green, Icons.check_circle, 
                       () => _updateStatus(docId, order, 'delivered')),
                    SizedBox(width: 8.sp),
                    _actionBtn("فشل", Colors.red, Icons.cancel, 
                       () => _updateStatus(docId, order, 'failed')),
                  ],
                )
              ],
            ),
          ),
        ],
      ),
    );
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
      _showSnackBar("خطأ: $e");
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Widget _rowInfo(String label, String value, {bool isTotal = false}) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4.sp),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey[700])),
          Expanded(child: Text(value, textAlign: TextAlign.end, 
            style: TextStyle(
              fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
              color: isTotal ? Colors.blue[800] : Colors.black,
              fontSize: isTotal ? 12.sp : 10.sp
            ))),
        ],
      ),
    );
  }

  Widget _actionBtn(String label, Color color, IconData icon, VoidCallback onPressed) {
    return Expanded(
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white, padding: EdgeInsets.symmetric(vertical: 8.sp)),
        onPressed: onPressed,
        icon: Icon(icon, size: 14.sp),
        label: Text(label, style: TextStyle(fontSize: 9.sp)),
      ),
    );
  }

  void _showSnackBar(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.assignment_turned_in_outlined, size: 50.sp, color: Colors.grey),
          SizedBox(height: 10.sp),
          const Text("لا توجد مهام حالياً", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

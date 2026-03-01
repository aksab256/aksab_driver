import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';

class InvoiceScreen extends StatefulWidget {
  final Map<String, dynamic> order; 
  const InvoiceScreen({super.key, required this.order});

  @override
  State<InvoiceScreen> createState() => _InvoiceScreenState();
}

class _InvoiceScreenState extends State<InvoiceScreen> {
  Map<String, dynamic>? _sellerDetails;
  bool _isLoadingSeller = true;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _fetchSellerDetails();
  }

  Future<void> _fetchSellerDetails() async {
    try {
      final sellerId = widget.order['sellerId'];
      // ✅ جلب بيانات المورد من مجموعة sellers
      final doc = await FirebaseFirestore.instance.collection('sellers').doc(sellerId).get();
      
      if (mounted) {
        setState(() {
          if (doc.exists) {
            _sellerDetails = doc.data();
          } else {
            _errorMessage = 'بيانات التاجر غير موجودة في سجلات الموردين';
          }
          _isLoadingSeller = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'عذراً، فشل جلب بيانات التاجر من السحابة';
          _isLoadingSeller = false;
        });
      }
    }
  }

  // دالة تحويل الـ Timestamp لنص منسق
  String _formatFirebaseDate(dynamic dateField) {
    if (dateField != null && dateField is Timestamp) {
      return DateFormat('yyyy/MM/dd HH:mm').format(dateField.toDate());
    }
    return "غير محدد";
  }

  Future<Uint8List> _buildA4Invoice(PdfPageFormat format) async {
    final pdf = pw.Document();
    final font = await PdfGoogleFonts.cairoRegular();
    final boldFont = await PdfGoogleFonts.cairoBold();
    
    // ✅ استخدام MerchantName كما طلبت من مجموعة sellers
    final String merchantName = _sellerDetails?['MerchantName'] ?? "تاجر منصة أكسب";
    final String storePhone = _sellerDetails?['phone'] ?? "-";
    
    final items = widget.order['items'] as List? ?? [];
    final Map<String, dynamic> buyer = widget.order['buyer'] is Map ? widget.order['buyer'] : {};

    // ✅ التفرقة بين تاريخ الطلب وتاريخ الإسناد
    final String orderCreationDate = _formatFirebaseDate(widget.order['createdAt']);
    final String assignmentDate = _formatFirebaseDate(widget.order['assignedAt']);
    
    // بيانات المندوب المسؤول عن العهدة
    final String repName = widget.order['repName'] ?? "غير محدد";

    pdf.addPage(
      pw.Page(
        pageFormat: format,
        build: (pw.Context context) {
          return pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Padding(
              padding: const pw.EdgeInsets.all(25),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  // الهيدر: اسم التاجر التجاري ورقم الطلب
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(merchantName, style: pw.TextStyle(font: boldFont, fontSize: 18, color: PdfColors.green900)),
                          pw.Text('هاتف التاجر: $storePhone', style: pw.TextStyle(font: font, fontSize: 10)),
                        ],
                      ),
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.end,
                        children: [
                          pw.Text('إيصال تأمين عهدة (مورد)', style: pw.TextStyle(font: boldFont, fontSize: 14, color: PdfColors.green900)),
                          pw.Text('رقم العملية: #${widget.order['orderId']}', style: pw.TextStyle(font: boldFont, fontSize: 9)),
                        ],
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 10),
                  pw.Divider(thickness: 1, color: PdfColors.green800),
                  
                  // بيانات التوقيت اللوجستي
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text('تاريخ طلب البضاعة:', style: pw.TextStyle(font: boldFont, fontSize: 9)),
                          pw.Text(orderCreationDate, style: pw.TextStyle(font: font, fontSize: 9)),
                        ],
                      ),
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.end,
                        children: [
                          pw.Text('تاريخ إسناد العهدة للمندوب:', style: pw.TextStyle(font: boldFont, fontSize: 9)),
                          pw.Text(assignmentDate, style: pw.TextStyle(font: font, fontSize: 9)),
                        ],
                      ),
                    ],
                  ),

                  pw.SizedBox(height: 15),
                  // بيانات المندوب والعميل
                  pw.Row(
                    children: [
                      pw.Expanded(
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text('المندوب المسؤول:', style: pw.TextStyle(font: boldFont, fontSize: 10)),
                            pw.Text(repName, style: pw.TextStyle(font: font, fontSize: 10, color: PdfColors.blue900)),
                          ],
                        ),
                      ),
                      pw.Expanded(
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text('العميل المستلم:', style: pw.TextStyle(font: boldFont, fontSize: 10)),
                            pw.Text(buyer['name'] ?? '-', style: pw.TextStyle(font: font, fontSize: 10)),
                          ],
                        ),
                      ),
                    ],
                  ),

                  pw.SizedBox(height: 20),
                  // جدول محتويات الشحنة
                  pw.TableHelper.fromTextArray(
                    headers: ['بيان الصنف', 'الكمية', 'السعر', 'الإجمالي'],
                    data: items.map((item) => [
                          item['sellerName'] ?? 'بضاعة عامة',
                          '${item['quantity']}',
                          '${(item['price'] ?? 0).toStringAsFixed(2)}',
                          '${((item['quantity'] ?? 0) * (item['price'] ?? 0)).toStringAsFixed(2)}'
                        ]).toList(),
                    headerStyle: pw.TextStyle(font: boldFont, color: PdfColors.white, fontSize: 10),
                    headerDecoration: const pw.BoxDecoration(color: PdfColors.green800),
                    cellStyle: pw.TextStyle(font: font, fontSize: 10),
                    cellAlignment: pw.Alignment.centerRight,
                  ),

                  pw.SizedBox(height: 25),
                  // التذييل المالي والـ QR
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.SizedBox(
                        height: 60, 
                        width: 60, 
                        child: pw.BarcodeWidget(
                          barcode: pw.Barcode.qrCode(), 
                          data: 'Merchant:$merchantName\nOrder:${widget.order['orderId']}\nTotal:${widget.order['total']}'
                        )
                      ),
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.end,
                        children: [
                          pw.Text('إجمالي القيمة المطلوب تحصيلها:', style: pw.TextStyle(font: font, fontSize: 11)),
                          pw.Container(
                            padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: const pw.BoxDecoration(color: PdfColors.green50),
                            child: pw.Text('${widget.order['total']} ج.م', 
                                    style: pw.TextStyle(font: boldFont, fontSize: 20, color: PdfColors.green900)),
                          ),
                          if (widget.order['cashbackApplied'] != null && widget.order['cashbackApplied'] > 0)
                             pw.Text('تم استخدام نقاط أمان بقيمة: ${widget.order['cashbackApplied']}', 
                                     style: pw.TextStyle(font: font, fontSize: 9, color: PdfColors.red700)),
                        ],
                      ),
                    ],
                  ),
                  pw.Spacer(),
                  pw.Divider(thickness: 0.5, color: PdfColors.grey400),
                  pw.Center(
                    child: pw.Text('نظام أكسب اللوجستي - تأمين عهدة وبضائع الموردين', 
                            style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey700))
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    return pdf.save();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('معاينة إيصال العهدة', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1E7E34),
        centerTitle: true,
      ),
      body: _isLoadingSeller
          ? const Center(child: CircularProgressIndicator(color: Colors.green))
          : _errorMessage.isNotEmpty
              ? Center(child: Text(_errorMessage, style: const TextStyle(fontFamily: 'Cairo', color: Colors.red)))
              : PdfPreview(
                  build: (format) => _buildA4Invoice(format),
                  canChangePageFormat: false,
                  pdfFileName: "Invoice_${widget.order['orderId']}.pdf",
                  loadingWidget: const Center(child: CircularProgressIndicator()),
                ),
    );
  }
}

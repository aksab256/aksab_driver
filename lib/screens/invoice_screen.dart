import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';

class InvoiceScreen extends StatefulWidget {
  final Map<String, dynamic> order; // استلام البيانات كـ Map
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
      final doc = await FirebaseFirestore.instance.collection('users').doc(sellerId).get();
      
      if (mounted) {
        setState(() {
          if (doc.exists) {
            _sellerDetails = doc.data();
          } else {
            _errorMessage = 'بيانات المتجر غير موجودة';
          }
          _isLoadingSeller = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'خطأ في جلب بيانات المورد';
          _isLoadingSeller = false;
        });
      }
    }
  }

  Future<Uint8List> _buildA4Invoice(PdfPageFormat format) async {
    final pdf = pw.Document();
    // السحر هنا: تحميل الخط من جوجل مباشرة للـ PDF
    final font = await PdfGoogleFonts.cairoRegular();
    final boldFont = await PdfGoogleFonts.cairoBold();
    
    final String storeName = _sellerDetails?['storeName'] ?? "متجر اكسب";
    final String storePhone = _sellerDetails?['phone'] ?? "غير مسجل";
    final String storeAddress = _sellerDetails?['address'] ?? "غير محدد";
    final items = widget.order['items'] as List? ?? [];
    final buyer = widget.order['buyer'] ?? {};

    pdf.addPage(
      pw.Page(
        pageFormat: format,
        build: (pw.Context context) {
          return pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Container(
              padding: const pw.EdgeInsets.all(25),
              decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey400, width: 1)),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(storeName, style: pw.TextStyle(font: boldFont, fontSize: 20, color: PdfColors.green900)),
                          pw.Text('هاتف: $storePhone', style: pw.TextStyle(font: font, fontSize: 10)),
                        ],
                      ),
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.end,
                        children: [
                          pw.Text('فاتورة توريد طلب', style: pw.TextStyle(font: boldFont, fontSize: 14, color: PdfColors.green900)),
                          pw.Text('رقم: #${widget.order['orderId']?.toString().substring(0, 8).toUpperCase()}', style: pw.TextStyle(font: boldFont, fontSize: 10)),
                        ],
                      ),
                    ],
                  ),
                  pw.Divider(thickness: 2, color: PdfColors.green800),
                  pw.SizedBox(height: 15),
                  pw.Text('بيانات العميل:', style: pw.TextStyle(font: boldFont, fontSize: 12)),
                  pw.Container(
                    width: double.infinity,
                    padding: const pw.EdgeInsets.all(10),
                    decoration: pw.BoxDecoration(color: PdfColors.grey50, border: pw.Border.all(color: PdfColors.grey200)),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('الاسم: ${buyer['name'] ?? '-'}', style: pw.TextStyle(font: boldFont, fontSize: 11)),
                        pw.Text('العنوان: ${buyer['address'] ?? '-'}', style: pw.TextStyle(font: font, fontSize: 10)),
                      ],
                    ),
                  ),
                  pw.SizedBox(height: 20),
                  pw.TableHelper.fromTextArray(
                    headers: ['الصنف', 'الكمية', 'السعر', 'الإجمالي'],
                    data: items.map((item) => [
                          item['name'] ?? '-',
                          '${item['quantity']}',
                          '${item['price']}',
                          '${(item['quantity'] * item['price']).toStringAsFixed(2)}'
                        ]).toList(),
                    headerStyle: pw.TextStyle(font: boldFont, color: PdfColors.white, fontSize: 10),
                    headerDecoration: const pw.BoxDecoration(color: PdfColors.green800),
                    cellStyle: pw.TextStyle(font: font, fontSize: 10),
                    cellAlignment: pw.Alignment.centerRight,
                  ),
                  pw.SizedBox(height: 20),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.SizedBox(height: 60, width: 60, child: pw.BarcodeWidget(barcode: pw.Barcode.qrCode(), data: 'Order: ${widget.order['orderId']}')),
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.end,
                        children: [
                          pw.Text('المبلغ المطلوب تحصيله:', style: pw.TextStyle(font: font, fontSize: 11)),
                          pw.Text('${widget.order['total']} ج.م', style: pw.TextStyle(font: boldFont, fontSize: 16, color: PdfColors.green900)),
                        ],
                      ),
                    ],
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
        title: const Text('معاينة الفاتورة', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF28A745),
      ),
      body: _isLoadingSeller
          ? const Center(child: CircularProgressIndicator())
          : PdfPreview(
              build: (format) => _buildA4Invoice(format),
              canChangePageFormat: false,
              pdfFileName: "Order_${widget.order['orderId']}.pdf",
            ),
    );
  }
}


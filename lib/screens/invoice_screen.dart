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
      final doc = await FirebaseFirestore.instance.collection('sellers').doc(sellerId).get();
      if (mounted) {
        setState(() {
          if (doc.exists) {
            _sellerDetails = doc.data();
          } else {
            _errorMessage = 'بيانات المورد غير موجودة';
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

  String _formatFirebaseDate(dynamic dateField) {
    if (dateField != null && dateField is Timestamp) {
      return DateFormat('yyyy/MM/dd HH:mm').format(dateField.toDate());
    }
    return "غير محدد";
  }

  Future<Uint8List> _buildSmartInvoice(PdfPageFormat format) async {
    final pdf = pw.Document();
    final font = await PdfGoogleFonts.cairoRegular();
    final boldFont = await PdfGoogleFonts.cairoBold();

    final bool isThermal = format.width < 10 * PdfPageFormat.cm;

    final String merchantName = _sellerDetails?['MerchantName'] ?? "مورد أكسب";
    final items = widget.order['items'] as List? ?? [];
    final Map<String, dynamic> buyer = widget.order['buyer'] is Map ? widget.order['buyer'] : {};

    final double grossTotal = (widget.order['total'] ?? 0.0).toDouble();
    final double discount = (widget.order['cashbackApplied'] ?? 0.0).toDouble();
    final double netAmount = (widget.order['netTotal'] ?? (grossTotal - discount)).toDouble();

    pdf.addPage(
      pw.Page(
        pageFormat: format,
        build: (pw.Context context) {
          return pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Padding(
              padding: pw.EdgeInsets.all(isThermal ? 8 : 20),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Center(
                    child: pw.Text(merchantName, 
                        style: pw.TextStyle(font: boldFont, fontSize: isThermal ? 16 : 22, color: PdfColors.green900)),
                  ),
                  if (!isThermal) pw.Divider(thickness: 1.5, color: PdfColors.green800),
                  
                  pw.SizedBox(height: 8),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('رقم العملية: #${widget.order['orderId']?.toString().substring(0, 8).toUpperCase()}', 
                          style: pw.TextStyle(font: boldFont, fontSize: isThermal ? 10 : 12)),
                      if (!isThermal) pw.Text(_formatFirebaseDate(widget.order['createdAt']), 
                          style: pw.TextStyle(font: font, fontSize: 11)),
                    ],
                  ),

                  pw.SizedBox(height: 12),
                  pw.Container(
                    width: double.infinity,
                    padding: const pw.EdgeInsets.all(8),
                    decoration: const pw.BoxDecoration(color: PdfColors.grey100),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('العميل المستلم: ${buyer['name'] ?? '-'}', 
                            style: pw.TextStyle(font: boldFont, fontSize: isThermal ? 12 : 14)),
                        pw.Text('العنوان: ${buyer['address'] ?? '-'}', 
                            style: pw.TextStyle(font: font, fontSize: isThermal ? 10 : 12)),
                      ],
                    ),
                  ),

                  pw.SizedBox(height: 12),
                  pw.TableHelper.fromTextArray(
                    headers: ['صنف', 'كمية', 'سعر', 'إجمالي'],
                    data: items.map((item) {
                      final p = (item['price'] ?? 0).toDouble();
                      final q = (item['quantity'] ?? 0).toInt();
                      return [
                        item['name'] ?? 'بضاعة',
                        '$q',
                        '${p.toStringAsFixed(1)}',
                        '${(p * q).toStringAsFixed(1)}'
                      ];
                    }).toList(),
                    headerStyle: pw.TextStyle(font: boldFont, color: PdfColors.white, fontSize: isThermal ? 10 : 12),
                    headerDecoration: const pw.BoxDecoration(color: PdfColors.green800),
                    cellStyle: pw.TextStyle(font: font, fontSize: isThermal ? 10 : 12),
                    cellAlignment: pw.Alignment.centerRight,
                  ),

                  pw.SizedBox(height: 15),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      if (discount > 0)
                        pw.Text('نقاط أمان (خصم): ${discount.toStringAsFixed(2)} -', 
                            style: pw.TextStyle(font: font, fontSize: isThermal ? 10 : 12, color: PdfColors.red700)),
                      pw.Container(
                        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                        decoration: const pw.BoxDecoration(color: PdfColors.green50),
                        child: pw.Row(
                          mainAxisSize: pw.MainAxisSize.min, // ✅ تصحيح MainAxisSize
                          mainAxisAlignment: pw.MainAxisAlignment.end,
                          children: [
                            pw.Text('${netAmount.toStringAsFixed(2)} ج.م', 
                                style: pw.TextStyle(font: boldFont, fontSize: isThermal ? 18 : 24, color: PdfColors.green900)),
                            pw.SizedBox(width: 12),
                            pw.Text('الصافي للتحصيل:', style: pw.TextStyle(font: boldFont, fontSize: isThermal ? 11 : 14)),
                          ],
                        ),
                      ),
                    ],
                  ),

                  pw.SizedBox(height: 15),
                  pw.Center(
                    child: pw.Column(
                      children: [
                        pw.SizedBox(
                          height: isThermal ? 50 : 80, width: isThermal ? 50 : 80,
                          child: pw.BarcodeWidget(
                            barcode: pw.Barcode.qrCode(), 
                            data: 'Order:${widget.order['orderId']}\nNet:$netAmount'
                          )
                        ),
                        pw.SizedBox(height: 10),
                        pw.Text('نظام أكسب اللوجستي - Aksab', 
                            style: pw.TextStyle(font: font, fontSize: 9, color: PdfColors.grey700)),
                      ],
                    ),
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
        title: const Text('معاينة الإيصال الذكي', 
          style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: const Color(0xFF1B5E20),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SafeArea(
        child: _isLoadingSeller
            ? const Center(child: CircularProgressIndicator(color: Colors.green))
            : _errorMessage.isNotEmpty
                ? Center(child: Text(_errorMessage, style: const TextStyle(fontFamily: 'Cairo', color: Colors.red, fontSize: 16)))
                : PdfPreview(
                    build: (format) => _buildSmartInvoice(format),
                    canChangePageFormat: true,
                    initialPageFormat: PdfPageFormat.a4, 
                    pdfFileName: "Aksab_${widget.order['orderId']}.pdf",
                    loadingWidget: const Center(child: CircularProgressIndicator()),
                  ),
      ),
    );
  }
}

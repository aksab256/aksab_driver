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
          _errorMessage = 'فشل في الاتصال بالسحابة لجلب بيانات المورد';
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

  Future<Uint8List> _buildA4Invoice(PdfPageFormat format) async {
    final pdf = pw.Document();
    final font = await PdfGoogleFonts.cairoRegular();
    final boldFont = await PdfGoogleFonts.cairoBold();
    
    final String merchantName = _sellerDetails?['MerchantName'] ?? "مورد منصة أكسب";
    final String storePhone = _sellerDetails?['phone'] ?? "-";
    
    final items = widget.order['items'] as List? ?? [];
    final Map<String, dynamic> buyer = widget.order['buyer'] is Map ? widget.order['buyer'] : {};

    // التوقيتات
    final String orderDate = _formatFirebaseDate(widget.order['createdAt'] ?? widget.order['orderDate']);
    final String assignmentDate = _formatFirebaseDate(widget.order['assignedAt']);
    
    // المبالغ المالية بدقة
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
              padding: const pw.EdgeInsets.all(20),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  // الرأس (Header)
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(merchantName, style: pw.TextStyle(font: boldFont, fontSize: 16, color: PdfColors.green900)),
                          pw.Text('هاتف المورد: $storePhone', style: pw.TextStyle(font: font, fontSize: 9)),
                        ],
                      ),
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.end,
                        children: [
                          pw.Text('إيصال تسليم بضاعة (أمانة)', style: pw.TextStyle(font: boldFont, fontSize: 14, color: PdfColors.green900)),
                          pw.Text('رقم الطلب: #${widget.order['orderId'] ?? 'ID'}', style: pw.TextStyle(font: boldFont, fontSize: 9)),
                        ],
                      ),
                    ],
                  ),
                  pw.Divider(thickness: 1.5, color: PdfColors.green800),
                  
                  // بيانات الأطراف والتوقيت
                  pw.SizedBox(height: 10),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text('تاريخ الطلب: $orderDate', style: pw.TextStyle(font: font, fontSize: 8)),
                          pw.Text('تاريخ الإسناد: $assignmentDate', style: pw.TextStyle(font: font, fontSize: 8)),
                        ],
                      ),
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.end,
                        children: [
                          pw.Text('المندوب: ${widget.order['repName'] ?? 'غير محدد'}', style: pw.TextStyle(font: boldFont, fontSize: 9)),
                        ],
                      ),
                    ],
                  ),

                  pw.SizedBox(height: 15),
                  // بيانات العميل (المشتري)
                  pw.Container(
                    padding: const pw.EdgeInsets.all(8),
                    decoration: const pw.BoxDecoration(color: PdfColors.grey100),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('بيانات المستلم (العميل):', style: pw.TextStyle(font: boldFont, fontSize: 10)),
                        pw.Row(
                          children: [
                            pw.Expanded(child: pw.Text('الاسم: ${buyer['name'] ?? '-'}', style: pw.TextStyle(font: font, fontSize: 9))),
                            pw.Expanded(child: pw.Text('الهاتف: ${buyer['phone'] ?? '-'}', style: pw.TextStyle(font: font, fontSize: 9))),
                          ],
                        ),
                        pw.Text('العنوان: ${buyer['address'] ?? '-'}', style: pw.TextStyle(font: font, fontSize: 8)),
                      ],
                    ),
                  ),

                  pw.SizedBox(height: 15),
                  // جدول الأصناف
                  pw.TableHelper.fromTextArray(
                    headers: ['اسم الصنف', 'الكمية', 'سعر الوحدة', 'الإجمالي'],
                    data: items.map((item) {
                      final double p = (item['price'] ?? 0).toDouble();
                      final int q = (item['quantity'] ?? 0).toInt();
                      return [
                        item['name'] ?? item['productName'] ?? 'صنف غير مسمى',
                        '$q',
                        '${p.toStringAsFixed(2)}',
                        '${(p * q).toStringAsFixed(2)}'
                      ];
                    }).toList(),
                    headerStyle: pw.TextStyle(font: boldFont, color: PdfColors.white, fontSize: 9),
                    headerDecoration: const pw.BoxDecoration(color: PdfColors.green800),
                    cellStyle: pw.TextStyle(font: font, fontSize: 9),
                    cellAlignment: pw.Alignment.centerRight,
                  ),

                  pw.SizedBox(height: 20),
                  // الملخص المالي
                  pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      // QR Code
                      pw.Container(
                        height: 70, width: 70,
                        child: pw.BarcodeWidget(
                          barcode: pw.Barcode.qrCode(), 
                          data: 'Order:${widget.order['orderId']}\nNet:$netAmount\nBuyer:${buyer['name']}'
                        )
                      ),
                      pw.Spacer(),
                      // مبالغ الفاتورة
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.end,
                        children: [
                          _priceRow('إجمالي البضاعة:', grossTotal, font),
                          if (discount > 0)
                            _priceRow('نقاط أمان (خصم):', -discount, font, color: PdfColors.red700),
                          pw.Divider(width: 150, thickness: 1),
                          pw.Container(
                            padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: const pw.BoxDecoration(color: PdfColors.green50),
                            child: pw.Row(
                              mainAxisSize: pw.MainAxisSize.min,
                              children: [
                                pw.Text('ج.م ', style: pw.TextStyle(font: boldFont, fontSize: 12, color: PdfColors.green900)),
                                pw.Text('${netAmount.toStringAsFixed(2)}', 
                                    style: pw.TextStyle(font: boldFont, fontSize: 18, color: PdfColors.green900)),
                                pw.SizedBox(width: 10),
                                pw.Text('الصافي المطلوب تحصيله:', style: pw.TextStyle(font: boldFont, fontSize: 11)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),

                  pw.Spacer(),
                  // تذييل الفاتورة
                  pw.Divider(thickness: 0.5, color: PdfColors.grey400),
                  pw.Center(
                    child: pw.Text('هذا المستند يعتبر إقرار باستلام العهدة المذكورة وتعهد بتوريد قيمتها الصافية للمورد', 
                            style: pw.TextStyle(font: font, fontSize: 7, color: PdfColors.grey700))
                  ),
                  pw.Center(
                    child: pw.Text('منصة أكسب اللوجستية - Aksab Logistics System', 
                            style: pw.TextStyle(font: boldFont, fontSize: 7, color: PdfColors.green900))
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

  pw.Widget _priceRow(String label, double value, pw.Font font, {PdfColor color = PdfColors.black}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          pw.Text('${value.toStringAsFixed(2)} ج.م', style: pw.TextStyle(font: font, fontSize: 10, color: color)),
          pw.SizedBox(width: 10),
          pw.Text(label, style: pw.TextStyle(font: font, fontSize: 10)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('معاينة فاتورة العميل', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white)),
        backgroundColor: const Color(0xFF1E7E34),
        centerTitle: true,
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => Navigator.pop(context)),
      ),
      body: _isLoadingSeller
          ? const Center(child: CircularProgressIndicator(color: Colors.green))
          : _errorMessage.isNotEmpty
              ? Center(child: Text(_errorMessage, style: const TextStyle(fontFamily: 'Cairo', color: Colors.red)))
              : PdfPreview(
                  build: (format) => _buildA4Invoice(format),
                  canChangePageFormat: false,
                  pdfFileName: "Aksab_Invoice_${widget.order['orderId']}.pdf",
                  loadingWidget: const Center(child: CircularProgressIndicator()),
                  pdfPreviewPageDecoration: const BoxDecoration(color: Colors.white),
                ),
    );
  }
}

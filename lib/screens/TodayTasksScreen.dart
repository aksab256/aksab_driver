import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:sizer/sizer.dart';
import 'package:url_launcher/url_launcher.dart';
// استدعاء الشاشة الجديدة
import 'package:aksab_driver/screens/invoice_screen.dart'; 

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
    
    try {
      if (await canLaunchUrl(googleUri)) {
        await launchUrl(googleUri, mode: LaunchMode.externalNonBrowserApplication);
      } else {
        _showSnackBar("تعذر فتح تطبيق الخرائط");
      }
    } catch (e) {
      _showSnackBar("خطأ في فتح الخرائط");
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
        title: Text("مهام التوصيل اليومية", 
          style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold, color: Colors.white)),
        centerTitle: true,
        backgroundColor: const Color(0xFF1B5E20), // أخضر براند اكسب
        elevation: 0,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('waitingdelivery')
            .where('repCode', isEqualTo: widget.repCode)
            .where('deliveryTaskStatus', isEqualTo: 'pending')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return _buildEmptyState();
          
          return ListView.builder(
            padding: EdgeInsets.all(12.sp),
            itemCount: snapshot.data!.docs.length,
            itemBuilder: (context, index) {
              var doc = snapshot.data!.docs[index];
              return _buildTaskCard(doc.id, doc.data() as Map<String, dynamic>);
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      margin: EdgeInsets.only(bottom: 15.sp),
      elevation: 4,
      child: Column(
        children: [
          Container(
            padding: EdgeInsets.symmetric(horizontal: 12.sp, vertical: 8.sp),
            decoration: const BoxDecoration(
              color: Color(0xFF2E7D32),
              borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("طلب رقم: #${docId.substring(0, 6).toUpperCase()}", 
                  style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.bold, color: Colors.white)),
                IconButton(
                  icon: const Icon(Icons.map_outlined, color: Colors.white),
                  onPressed: () => _navigateToCustomer(buyer['location']),
                )
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.all(15.sp),
            child: Column(
              children: [
                _rowInfo("العميل:", buyer['name'] ?? "-", isBold: true),
                _rowInfo("العنوان:", buyer['address'] ?? "غير محدد"),
                const Divider(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("المبلغ للتحصيل:", style: TextStyle(fontSize: 12.sp, color: Colors.grey[700])),
                    Text("${total.toStringAsFixed(2)} ج.م", 
                      style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w900, color: Colors.green[900])),
                  ],
                ),
                SizedBox(height: 15.sp),
                Row(
                  children: [
                    // زرار الاتصال
                    _actionBtn("اتصال", Colors.blue, Icons.phone, 
                      () => launchUrl(Uri.parse("tel:${buyer['phone']}"))),
                    SizedBox(width: 8.sp),
                    
                    // ✨ زرار الفاتورة الاحترافي - يفتح صفحة المعاينة والطباعة
                    _actionBtn("الفاتورة", Colors.orange[800]!, Icons.receipt_long, () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => InvoiceScreen(order: order)),
                      );
                    }),
                  ],
                ),
                SizedBox(height: 12.sp),
                _isProcessing 
                ? const LinearProgressIndicator()
                : Row(
                  children: [
                    _mainConfirmBtn("تم التسليم ✅", Colors.green[700]!, 
                      () => _updateStatus(docId, 'delivered')),
                    SizedBox(width: 10.sp),
                    _mainConfirmBtn("فشل التوصيل ❌", Colors.red[700]!, 
                      () => _updateStatus(docId, 'failed')),
                  ],
                )
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _rowInfo(String label, String value, {bool isBold = false}) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 3.sp),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey[600], fontSize: 11.sp)),
          SizedBox(width: 5.sp),
          Expanded(child: Text(value, style: TextStyle(fontWeight: isBold ? FontWeight.bold : FontWeight.normal, fontSize: 12.sp))),
        ],
      ),
    );
  }

  Widget _actionBtn(String label, Color color, IconData icon, VoidCallback onTap) {
    return Expanded(
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 14.sp, color: color),
        label: Text(label, style: TextStyle(color: color, fontSize: 11.sp, fontWeight: FontWeight.bold)),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: color, width: 1.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          padding: EdgeInsets.symmetric(vertical: 8.sp)
        ),
      ),
    );
  }

  Widget _mainConfirmBtn(String label, Color color, VoidCallback onTap) {
    return Expanded(
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          padding: EdgeInsets.symmetric(vertical: 10.sp),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        child: Text(label, style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.bold)),
      ),
    );
  }

  void _showSnackBar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));
  }

  Widget _buildEmptyState() {
    return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.check_circle_outline, size: 60.sp, color: Colors.green[200]),
      SizedBox(height: 10.sp),
      Text("لا توجد مهام توصيل حالياً", style: TextStyle(color: Colors.grey, fontSize: 14.sp))
    ]));
  }
}


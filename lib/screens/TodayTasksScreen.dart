import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:sizer/sizer.dart';
import 'package:url_launcher/url_launcher.dart';
// تأكد من صحة مسار الملف في مشروعك
import 'invoice_screen.dart'; 

class TodayTasksScreen extends StatefulWidget {
  final String repCode;
  const TodayTasksScreen({super.key, required this.repCode});

  @override
  State<TodayTasksScreen> createState() => _TodayTasksScreenState();
}

class _TodayTasksScreenState extends State<TodayTasksScreen> {
  bool _isProcessing = false;

  // دالة لفتح خرائط جوجل لموقع العميل
  Future<void> _navigateToCustomer(Map<String, dynamic>? buyerData) async {
    if (buyerData == null || buyerData['lat'] == null || buyerData['lng'] == null) {
      _showSnackBar("موقع العميل غير متوفر");
      return;
    }
    final double lat = (buyerData['lat'] as num).toDouble();
    final double lng = (buyerData['lng'] as num).toDouble();
    final String googleUrl = "https://www.google.com/maps/search/?api=1&query=$lat,$lng";
    
    try {
      if (await canLaunchUrl(Uri.parse(googleUrl))) {
        await launchUrl(Uri.parse(googleUrl), mode: LaunchMode.externalApplication);
      } else {
        _showSnackBar("تعذر فتح الخرائط");
      }
    } catch (e) {
      _showSnackBar("خطأ في فتح الخرائط");
    }
  }

  // الدالة المطورة لتحديث الحالة وإضافة علامات التوريد المالي
  Future<void> _updateStatus(String docId, String status) async {
    setState(() => _isProcessing = true);
    try {
      Map<String, dynamic> updateData = {
        'deliveryTaskStatus': status,
        'completedAt': FieldValue.serverTimestamp(),
      };

      // 🚩 إذا تم التسليم بنجاح (المندوب استلم الكاش)
      if (status == 'delivered') {
        updateData['cashCollected'] = true; // علامة استلام المبلغ من العميل
        updateData['isSettled'] = false;    // لم يتم توريد المبلغ للخزينة بعد
      }

      await FirebaseFirestore.instance
          .collection('waitingdelivery')
          .doc(docId)
          .update(updateData);

      _showSnackBar(status == 'delivered' ? "تم تأكيد استلام العهدة بنجاح ✅" : "تم تسجيل فشل المهمة ❌");
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
          style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold, color: Colors.white)),
        centerTitle: true,
        backgroundColor: const Color(0xFF1B5E20),
        elevation: 2,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SafeArea(
        child: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('waitingdelivery')
              .where('repCode', isEqualTo: widget.repCode)
              .where('deliveryTaskStatus', isEqualTo: 'pending')
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator(color: Color(0xFF1B5E20)));
            }
            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return _buildEmptyState();
            
            return ListView.builder(
              padding: EdgeInsets.fromLTRB(12.sp, 12.sp, 12.sp, 80.sp),
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
    final buyer = order['buyer'] as Map<String, dynamic>? ?? {};
    final double amountToCollect = (order['netTotal'] ?? order['total'] ?? 0.0).toDouble();

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      margin: EdgeInsets.only(bottom: 18.sp),
      elevation: 6,
      child: Column(
        children: [
          Container(
            padding: EdgeInsets.symmetric(horizontal: 14.sp, vertical: 10.sp),
            decoration: const BoxDecoration(
              color: Color(0xFF2E7D32),
              borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("طلب: #${docId.substring(0, 8).toUpperCase()}", 
                  style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.bold, color: Colors.white)),
                IconButton(
                  icon: const Icon(Icons.directions_outlined, color: Colors.white, size: 28),
                  onPressed: () => _navigateToCustomer(buyer),
                )
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.all(16.sp),
            child: Column(
              children: [
                _rowInfo("المشتري:", buyer['name'] ?? "غير معروف", isBold: true),
                _rowInfo("العنوان:", buyer['address'] ?? "غير محدد"),
                const Divider(height: 25, thickness: 1),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("المطلوب تحصيله:", style: TextStyle(fontSize: 13.sp, color: Colors.grey[800])),
                    Text("${amountToCollect.toStringAsFixed(2)} ج.م", 
                      style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w900, color: const Color(0xFF1B5E20))),
                  ],
                ),
                SizedBox(height: 20.sp),
                Row(
                  children: [
                    _actionBtn("اتصال", Colors.blue[800]!, Icons.phone_forwarded, () async {
                      final phone = buyer['phone']?.toString() ?? "";
                      if (phone.isNotEmpty) await launchUrl(Uri.parse("tel:$phone"));
                    }),
                    SizedBox(width: 10.sp),
                    _actionBtn("الفاتورة", Colors.orange[900]!, Icons.receipt_long, () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => InvoiceScreen(order: order)),
                      );
                    }),
                  ],
                ),
                SizedBox(height: 15.sp),
                _isProcessing 
                ? const LinearProgressIndicator(color: Colors.green)
                : Row(
                  children: [
                    _mainConfirmBtn("تأكيد الاستلام ✅", Colors.green[700]!, 
                      () => _updateStatus(docId, 'delivered')),
                    SizedBox(width: 10.sp),
                    _mainConfirmBtn("فشل ❌", Colors.red[800]!, 
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
      padding: EdgeInsets.symmetric(vertical: 5.sp),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey[700], fontSize: 12.sp)),
          SizedBox(width: 8.sp),
          Expanded(child: Text(value, style: TextStyle(fontWeight: isBold ? FontWeight.bold : FontWeight.normal, fontSize: 13.sp))),
        ],
      ),
    );
  }

  Widget _actionBtn(String label, Color color, IconData icon, VoidCallback onTap) {
    return Expanded(
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 16.sp, color: color),
        label: Text(label, style: TextStyle(color: color, fontSize: 12.sp, fontWeight: FontWeight.bold)),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: color, width: 1.8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: EdgeInsets.symmetric(vertical: 10.sp)
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
          padding: EdgeInsets.symmetric(vertical: 14.sp),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: Text(label, style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.bold)),
      ),
    );
  }

  void _showSnackBar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: TextStyle(fontSize: 12.sp, fontFamily: 'Cairo')), 
      behavior: SnackBarBehavior.floating,
      backgroundColor: Colors.black87,
    ));
  }

  Widget _buildEmptyState() {
    return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.assignment_turned_in_outlined, size: 80.sp, color: Colors.green[100]),
      SizedBox(height: 15.sp),
      Text("لا توجد مهام حالياً", style: TextStyle(color: Colors.grey, fontSize: 16.sp, fontWeight: FontWeight.bold))
    ]));
  }
}

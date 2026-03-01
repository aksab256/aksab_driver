import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:sizer/sizer.dart';
import 'package:url_launcher/url_launcher.dart';
// تأكد من استيراد صفحة الفاتورة بشكل صحيح حسب مسار مشروعك
// import 'package:aksab_driver/screens/invoice_screen.dart'; 

class TodayTasksScreen extends StatefulWidget {
  final String repCode;
  const TodayTasksScreen({super.key, required this.repCode});

  @override
  State<TodayTasksScreen> createState() => _TodayTasksScreenState();
}

class _TodayTasksScreenState extends State<TodayTasksScreen> {
  bool _isProcessing = false;

  // --- 🎯 التوجيه للخرائط: معدل لقراءة Lat/Lng من مستوى الـ Buyer مباشرة ---
  Future<void> _navigateToCustomer(Map<String, dynamic>? buyerData) async {
    if (buyerData == null || buyerData['lat'] == null || buyerData['lng'] == null) {
      _showSnackBar("موقع العميل غير متوفر في بيانات الطلب");
      return;
    }

    final double lat = (buyerData['lat'] as num).toDouble();
    final double lng = (buyerData['lng'] as num).toDouble();
    
    // استخدام الرابط المباشر لضمان التوافق مع خرائط جوجل
    final String googleUrl = "https://www.google.com/maps/search/?api=1&query=$lat,$lng";
    final Uri uri = Uri.parse(googleUrl);
    
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        _showSnackBar("تعذر فتح تطبيق الخرائط على هذا الجهاز");
      }
    } catch (e) {
      _showSnackBar("خطأ تقني في تشغيل الخرائط");
    }
  }

  // --- تحديث حالة المهمة في Firebase ---
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
      _showSnackBar(status == 'delivered' ? "تم تأكيد العهدة واستلام الأمانات ✅" : "تم تسجيل فشل التوصيل ❌");
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
        backgroundColor: const Color(0xFF1B5E20), // أخضر براند "اكسب"
        elevation: 2,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('waitingdelivery')
            .where('repCode', isEqualTo: widget.repCode)
            .where('deliveryTaskStatus', isEqualTo: 'pending')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: Color(0xFF1B5E20)));
          if (snapshot.hasError) return Center(child: Text("خطأ في جلب المهام"));
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
    final buyer = order['buyer'] as Map<String, dynamic>? ?? {};
    
    // 💰 المنطق المالي الاحترافي: المندوب يطالب بالصافي (netTotal) لو موجود، وإلا الإجمالي (total)
    final double amountToCollect = (order['netTotal'] ?? order['total'] ?? 0.0).toDouble();

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      margin: EdgeInsets.only(bottom: 15.sp),
      elevation: 5,
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
                Text("طلب رقم: #${docId.substring(0, 8).toUpperCase()}", 
                  style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.bold, color: Colors.white)),
                IconButton(
                  icon: const Icon(Icons.directions_outlined, color: Colors.white, size: 22),
                  onPressed: () => _navigateToCustomer(buyer),
                )
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.all(15.sp),
            child: Column(
              children: [
                _rowInfo("المشتري:", buyer['name'] ?? "غير معروف", isBold: true),
                _rowInfo("العنوان:", buyer['address'] ?? "العنوان غير محدد بدقة"),
                const Divider(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("المبلغ المطلوب تحصيله:", 
                        style: TextStyle(fontSize: 12.sp, color: Colors.grey[700], fontWeight: FontWeight.w500)),
                    Text("${amountToCollect.toStringAsFixed(2)} ج.م", 
                      style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w900, color: const Color(0xFF1B5E20))),
                  ],
                ),
                if (order['netTotal'] != null && order['netTotal'] != order['total'])
                  Padding(
                    padding: EdgeInsets.only(top: 4.sp),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text("تم تطبيق خصم نقاط أمان ✅", 
                        style: TextStyle(fontSize: 9.sp, color: Colors.orange[900], fontWeight: FontWeight.bold)),
                    ),
                  ),
                SizedBox(height: 15.sp),
                Row(
                  children: [
                    // زر الاتصال المباشر
                    _actionBtn("اتصال", Colors.blue[800]!, Icons.phone_forwarded, 
                      () async {
                        final phone = buyer['phone']?.toString() ?? "";
                        if (phone.isNotEmpty) {
                          await launchUrl(Uri.parse("tel:$phone"));
                        } else {
                          _showSnackBar("لا يوجد رقم هاتف مسجل لهذا العميل");
                        }
                      }),
                    SizedBox(width: 8.sp),
                    
                    // زر الفاتورة
                    _actionBtn("الفاتورة", Colors.orange[800]!, Icons.receipt_long, () {
                      // Navigator.push(
                      //   context,
                      //   MaterialPageRoute(builder: (context) => InvoiceScreen(order: order)),
                      // );
                    }),
                  ],
                ),
                SizedBox(height: 12.sp),
                _isProcessing 
                ? const LinearProgressIndicator(color: Colors.green)
                : Row(
                  children: [
                    _mainConfirmBtn("تأكيد الاستلام ✅", Colors.green[700]!, 
                      () => _updateStatus(docId, 'delivered')),
                    SizedBox(width: 10.sp),
                    _mainConfirmBtn("فشل المهمة ❌", Colors.red[800]!, 
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
      padding: EdgeInsets.symmetric(vertical: 4.sp),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey[600], fontSize: 11.sp)),
          SizedBox(width: 8.sp),
          Expanded(child: Text(value, 
              style: TextStyle(fontWeight: isBold ? FontWeight.bold : FontWeight.normal, 
              fontSize: 12.sp, color: Colors.black87))),
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: EdgeInsets.symmetric(vertical: 9.sp)
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
          padding: EdgeInsets.symmetric(vertical: 12.sp),
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: Text(label, style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.bold)),
      ),
    );
  }

  void _showSnackBar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: TextStyle(fontFamily: 'Cairo', fontSize: 11.sp)),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        backgroundColor: const Color(0xFF2C3E50),
      )
    );
  }

  Widget _buildEmptyState() {
    return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.assignment_turned_in_outlined, size: 70.sp, color: Colors.green[100]),
      SizedBox(height: 15.sp),
      Text("كافة المهام مكتملة!", style: TextStyle(color: Colors.green[800], fontSize: 16.sp, fontWeight: FontWeight.bold)),
      Text("لا توجد طلبات في انتظار التوصيل حالياً", style: TextStyle(color: Colors.grey, fontSize: 12.sp)),
    ]));
  }
}

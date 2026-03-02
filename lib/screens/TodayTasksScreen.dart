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
      _showCustomSnackBar("موقع العميل غير متوفر 📍", isError: true);
      return;
    }
    final double lat = (buyerData['lat'] as num).toDouble();
    final double lng = (buyerData['lng'] as num).toDouble();
    final String googleUrl = "https://www.google.com/maps/search/?api=1&query=$lat,$lng";
    
    try {
      if (await canLaunchUrl(Uri.parse(googleUrl))) {
        await launchUrl(Uri.parse(googleUrl), mode: LaunchMode.externalApplication);
      } else {
        _showCustomSnackBar("تعذر فتح الخرائط 🗺️", isError: true);
      }
    } catch (e) {
      _showCustomSnackBar("خطأ في فتح الخرائط ⚠️", isError: true);
    }
  }

  // نافذة التأكيد لمنع الضغط بالخطأ
  void _showConfirmDialog(String docId, String status) {
    String title = status == 'delivered' ? "تأكيد العهدة ✅" : "تسجيل فشل المهمة ❌";
    String message = status == 'delivered' 
        ? "بإدخال كود التاجر، أنت تؤكد استلام الشحنة في عهدتك. سيتم تخصيص (نقاط أمان) من حسابك تعادل قيمة الشحنة لضمان النقل الآمن. لا يمكن التراجع بعد تأكيد العهدة."
        : "هل أنت متأكد من تسجيل هذه الشحنة كفشل توصيل؟ ستظل في عهدتك كمرتجع لحين التصفية.";

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(title, textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16.sp)),
        content: Text(message, textAlign: TextAlign.center, style: TextStyle(fontSize: 13.sp, color: Colors.black87)),
        actionsAlignment: MainAxisAlignment.spaceEvenly,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("تراجع", style: TextStyle(color: Colors.grey[700], fontSize: 13.sp, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: status == 'delivered' ? Colors.green[800] : Colors.red[800],
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: EdgeInsets.symmetric(horizontal: 20.sp, vertical: 8.sp)
            ),
            onPressed: () {
              Navigator.pop(context);
              _updateStatus(docId, status);
            },
            child: Text("تأكيد", style: TextStyle(color: Colors.white, fontSize: 13.sp, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // الدالة المطورة لتحديث الحالة وإضافة علامات التوريد المالي
  Future<void> _updateStatus(String docId, String status) async {
    if (!mounted) return;
    setState(() => _isProcessing = true);
    try {
      Map<String, dynamic> updateData = {
        'deliveryTaskStatus': status,
        'completedAt': FieldValue.serverTimestamp(),
      };

      if (status == 'delivered') {
        updateData['cashCollected'] = true; 
        updateData['isSettled'] = false;    
      }

      await FirebaseFirestore.instance
          .collection('waitingdelivery')
          .doc(docId)
          .update(updateData);

      _showCustomSnackBar(status == 'delivered' ? "تمت المهمة وتأكيد العهدة بنجاح 📦" : "تم تسجيل الشحنة كمرتجع 🔄");
    } catch (e) {
      _showCustomSnackBar("عذراً، حدث خطأ في التحديث ⚠️", isError: true);
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // سناك بار شيك يظهر في منتصف الشاشة
  void _showCustomSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 3),
        backgroundColor: Colors.transparent,
        elevation: 0,
        content: Center(
          child: Container(
            padding: EdgeInsets.symmetric(vertical: 15.sp, horizontal: 20.sp),
            decoration: BoxDecoration(
              color: isError ? Colors.red[900]!.withOpacity(0.9) : Colors.black.withOpacity(0.85),
              borderRadius: BorderRadius.circular(30),
              boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10, offset: const Offset(0, 5))],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(isError ? Icons.error_outline : Icons.check_circle_outline, color: Colors.white, size: 20.sp),
                SizedBox(width: 10.sp),
                Flexible(
                  child: Text(
                    message,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13.sp),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
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
                      () => _showConfirmDialog(docId, 'delivered')),
                    SizedBox(width: 10.sp),
                    _mainConfirmBtn("فشل ❌", Colors.red[800]!, 
                      () => _showConfirmDialog(docId, 'failed')),
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

  Widget _buildEmptyState() {
    return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.assignment_turned_in_outlined, size: 80.sp, color: Colors.green[100]),
      SizedBox(height: 15.sp),
      Text("لا توجد مهام حالياً", style: TextStyle(color: Colors.grey, fontSize: 16.sp, fontWeight: FontWeight.bold))
    ]));
  }
}

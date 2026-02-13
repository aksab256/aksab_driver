import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:sizer/sizer.dart';

class OrdersHistoryScreen extends StatelessWidget {
  const OrdersHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final String uid = FirebaseAuth.instance.currentUser?.uid ?? "";

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC), // لون خلفية هادئ ومريح
      appBar: AppBar(
        title: const Text("سجل الرحلات المكتملة", 
          style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 18)),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0.5,
        foregroundColor: Colors.black,
      ),
      body: SafeArea( // ✅ تأمين المنطقة العلوية والسفلية
        child: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('specialRequests')
              .where('driverId', isEqualTo: uid)
              .where('status', isEqualTo: 'delivered')
              .orderBy('completedAt', descending: true)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
              return _buildEmptyState();
            }

            return ListView.builder(
              padding: EdgeInsets.fromLTRB(12.sp, 12.sp, 12.sp, 80.sp), // ✅ Padding سفلي إضافي عشان الـ Nav Bar
              itemCount: snapshot.data!.docs.length,
              itemBuilder: (context, index) {
                var order = snapshot.data!.docs[index].data() as Map<String, dynamic>;
                return _buildOrderCard(order);
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildOrderCard(Map<String, dynamic> order) {
    DateTime? date = (order['completedAt'] as Timestamp?)?.toDate();
    String formattedDate = date != null ? DateFormat('dd/MM/yyyy | hh:mm a').format(date) : "تاريخ غير معروف";
    
    // حسابات المالية
    double totalPrice = double.tryParse(order['price']?.toString() ?? '0') ?? 0.0;
    double commission = double.tryParse(order['commissionAmount']?.toString() ?? '0') ?? 0.0;
    double netEarnings = totalPrice - commission;

    return Container(
      margin: EdgeInsets.only(bottom: 15.sp),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 15, offset: const Offset(0, 5))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Column(
          children: [
            // الهيدر الملون للكارت
            Container(
              padding: EdgeInsets.symmetric(horizontal: 15.sp, vertical: 8.sp),
              color: Colors.blueGrey[50],
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(formattedDate, style: TextStyle(color: Colors.blueGrey[600], fontSize: 8.5.sp, fontWeight: FontWeight.bold)),
                  Text("#${order['orderId']?.toString().substring(0, 5) ?? 'طلب'}", 
                    style: TextStyle(color: Colors.blueGrey[400], fontSize: 8.sp)),
                ],
              ),
            ),
            
            Padding(
              padding: EdgeInsets.all(15.sp),
              child: Column(
                children: [
                  // تفاصيل المسار
                  _buildLocationRow(Icons.radio_button_checked, Colors.orange[900]!, "من:", order['pickupAddress'] ?? "نقطة الاستلام"),
                  SizedBox(height: 1.5.h),
                  _buildLocationRow(Icons.location_on, Colors.blue[900]!, "إلى:", order['dropoffAddress'] ?? "نقطة التسليم"),
                  
                  const Divider(height: 30),

                  // تفاصيل الحساب المنسقة
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildFinanceStat("إجمالي الرحلة", "${totalPrice.toStringAsFixed(1)}", Colors.black87),
                      _buildFinanceStat("العمولة", "-${commission.toStringAsFixed(1)}", Colors.red[700]!),
                      _buildFinanceStat("صافي ربحك", "${netEarnings.toStringAsFixed(1)}", Colors.green[700]!),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationRow(IconData icon, Color color, String label, String address) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 16.sp),
        SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(color: Colors.grey, fontSize: 8.sp, fontFamily: 'Cairo')),
              Text(address, 
                style: TextStyle(fontSize: 10.5.sp, fontWeight: FontWeight.w600, fontFamily: 'Cairo', height: 1.2),
                maxLines: 2, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFinanceStat(String label, String value, Color valueColor) {
    return Column(
      children: [
        Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 8.sp, fontFamily: 'Cairo')),
        SizedBox(height: 4),
        Text("$value ج.م", 
          style: TextStyle(color: valueColor, fontSize: 12.sp, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: EdgeInsets.all(20.sp),
            decoration: BoxDecoration(color: Colors.orange[50], shape: BoxShape.circle),
            child: Icon(Icons.history_rounded, size: 50.sp, color: Colors.orange[900]),
          ),
          SizedBox(height: 2.h),
          Text("سجل الطلبات فارغ", style: TextStyle(fontFamily: 'Cairo', fontSize: 15.sp, fontWeight: FontWeight.bold)),
          Text("ابدأ بقبول الطلبات من الرادار لتظهر هنا", style: TextStyle(fontFamily: 'Cairo', fontSize: 10.sp, color: Colors.grey)),
        ],
      ),
    );
  }
}

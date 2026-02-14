// lib/screens/orders_history_screen.dart
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
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text("سجل الرحلات المكتملة", 
          style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 18)),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0.5,
        foregroundColor: Colors.black,
      ),
      body: SafeArea(
        child: StreamBuilder<QuerySnapshot>(
          // ✅ نصيحة: إذا استمر السجل فارغاً، جرب حذف سطر الـ orderBy مؤقتاً
          // إذا اشتغل، فالمشكلة هي Index 100% وتحتاج لضغط الرابط في الكونسول
          stream: FirebaseFirestore.instance
              .collection('specialRequests')
              .where('driverId', isEqualTo: uid)
              .where('status', isEqualTo: 'delivered')
              .orderBy('completedAt', descending: true)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(child: Text("يجب تفعيل الفهرسة (Index) من لوحة تحكم فايربيز", style: TextStyle(fontFamily: 'Cairo')));
            }
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator(color: Colors.orange));
            }
            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
              return _buildEmptyState();
            }

            return ListView.builder(
              padding: EdgeInsets.fromLTRB(12.sp, 12.sp, 12.sp, 80.sp),
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
    // ✅ التأكد من جلب التاريخ بشكل صحيح
    DateTime? date;
    if (order['completedAt'] is Timestamp) {
      date = (order['completedAt'] as Timestamp).toDate();
    }
    
    String formattedDate = date != null ? DateFormat('dd/MM/yyyy | hh:mm a').format(date) : "تاريخ غير معروف";
    
    // حسابات المالية - التأكد من أسماء الحقول كما في "أكسب"
    double totalPrice = double.tryParse(order['price']?.toString() ?? '0') ?? 0.0;
    // في تطبيقك استخدمنا driverNet للربح الصافي
    double netEarnings = double.tryParse(order['driverNet']?.toString() ?? '0') ?? 0.0;
    double commission = totalPrice - netEarnings;

    return Container(
      margin: EdgeInsets.only(bottom: 15.sp),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 15, offset: const Offset(0, 5))],
      ),
      child: Column(
        children: [
          Container(
            padding: EdgeInsets.symmetric(horizontal: 15.sp, vertical: 8.sp),
            color: Colors.orange[50], // تغيير اللون ليتماشى مع هوية المندوب
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(formattedDate, style: TextStyle(color: Colors.orange[900], fontSize: 8.5.sp, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
                Text("#${order['orderId']?.toString().substring(0, 5) ?? 'رحلة'}", 
                  style: TextStyle(color: Colors.grey[600], fontSize: 8.sp)),
              ],
            ),
          ),
          
          Padding(
            padding: EdgeInsets.all(15.sp),
            child: Column(
              children: [
                _buildLocationRow(Icons.radio_button_checked, Colors.green, "من:", order['pickupAddress'] ?? "موقع الاستلام"),
                SizedBox(height: 1.h),
                _buildLocationRow(Icons.location_on, Colors.redAccent, "إلى:", order['dropoffAddress'] ?? "موقع التسليم"),
                
                const Divider(height: 30),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildFinanceStat("إجمالي", "${totalPrice.toStringAsFixed(0)}", Colors.black87),
                    _buildFinanceStat("العمولة", "${commission.toStringAsFixed(0)}", Colors.red),
                    _buildFinanceStat("ربحك", "${netEarnings.toStringAsFixed(0)}", Colors.green[700]!),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationRow(IconData icon, Color color, String label, String address) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 14.sp),
        const SizedBox(width: 8),
        Expanded(
          child: Text(address, 
            style: TextStyle(fontSize: 10.sp, fontWeight: FontWeight.w500, fontFamily: 'Cairo'),
            maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }

  Widget _buildFinanceStat(String label, String value, Color valueColor) {
    return Column(
      children: [
        Text(label, style: TextStyle(color: Colors.grey, fontSize: 8.sp, fontFamily: 'Cairo')),
        Text("$value ج.م", 
          style: TextStyle(color: valueColor, fontSize: 11.sp, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history_rounded, size: 60.sp, color: Colors.grey[300]),
          SizedBox(height: 2.h),
          Text("لا توجد رحلات مكتملة بعد", style: TextStyle(fontFamily: 'Cairo', fontSize: 13.sp, color: Colors.grey[600])),
        ],
      ),
    );
  }
}

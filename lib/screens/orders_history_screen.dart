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
          style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 20)), // تكبير عنوان الـ AppBar
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0.5,
        foregroundColor: Colors.black,
      ),
      body: SafeArea(
        child: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('specialRequests')
              .where('driverId', isEqualTo: uid)
              .where('status', isEqualTo: 'delivered')
              .orderBy('completedAt', descending: true)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(child: Text("خطأ في تحميل البيانات", style: TextStyle(fontFamily: 'Cairo', fontSize: 14.sp)));
            }
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator(color: Colors.orange));
            }
            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
              return _buildEmptyState();
            }

            return ListView.builder(
              // ✅ زيادة المسافة السفلية لـ 100sp لضمان عدم نزول الكروت تحت أزرار القائمة
              padding: EdgeInsets.fromLTRB(12.sp, 15.sp, 12.sp, 100.sp), 
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
    DateTime? date;
    if (order['completedAt'] is Timestamp) {
      date = (order['completedAt'] as Timestamp).toDate();
    }
    String formattedDate = date != null ? DateFormat('dd/MM/yyyy | hh:mm a').format(date) : "تاريخ غير معروف";
    
    double total = double.tryParse(order['totalPrice']?.toString() ?? '0') ?? 0.0;
    double net = double.tryParse(order['driverNet']?.toString() ?? '0') ?? 0.0;
    double commission = (total > 0) ? (total - net) : 0.0;

    return Container(
      margin: EdgeInsets.only(bottom: 18.sp), // زيادة المسافة بين الكروت
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(25), // زيادة تدوير الحواف
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, 8))],
      ),
      child: Column(
        children: [
          Container(
            padding: EdgeInsets.symmetric(horizontal: 15.sp, vertical: 10.sp),
            decoration: BoxDecoration(
              color: Colors.orange[50],
              borderRadius: const BorderRadius.vertical(top: Radius.circular(25)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(formattedDate, 
                  style: TextStyle(color: Colors.orange[900], fontSize: 10.sp, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
                Text("#${order['orderId']?.toString().toUpperCase().substring(0, 5) ?? 'رحلة'}", 
                  style: TextStyle(color: Colors.grey[600], fontSize: 10.sp, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          
          Padding(
            padding: EdgeInsets.all(18.sp), // زيادة البادينج الداخلي
            child: Column(
              children: [
                _buildLocationRow(Icons.radio_button_checked, Colors.green, "من:", order['pickupAddress'] ?? "موقع الاستلام"),
                SizedBox(height: 2.h), // زيادة المسافة بين الموقعين
                _buildLocationRow(Icons.location_on, Colors.redAccent, "إلى:", order['dropoffAddress'] ?? "موقع التسليم"),
                
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 15),
                  child: Divider(height: 1, thickness: 0.8),
                ),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildFinanceStat("إجمالي", total.toStringAsFixed(1), Colors.black87),
                    _buildFinanceStat("العمولة", commission.abs().toStringAsFixed(1), Colors.red),
                    _buildFinanceStat("ربحك", net.toStringAsFixed(1), Colors.green[700]!),
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
        Icon(icon, color: color, size: 16.sp), // تكبير الأيقونات
        const SizedBox(width: 10),
        Expanded(
          child: Text(address, 
            style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.bold, fontFamily: 'Cairo', height: 1.3), // تكبير خط العنوان
            maxLines: 2, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }

  Widget _buildFinanceStat(String label, String value, Color valueColor) {
    return Column(
      children: [
        Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 10.sp, fontFamily: 'Cairo', fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Text("$value ج.م", 
          style: TextStyle(color: valueColor, fontSize: 13.sp, fontWeight: FontWeight.w900, fontFamily: 'Cairo')), // تكبير خط المبالغ المالية
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history_rounded, size: 70.sp, color: Colors.grey[200]),
          SizedBox(height: 3.h),
          Text("لا توجد رحلات مكتملة حالياً", 
            style: TextStyle(fontFamily: 'Cairo', fontSize: 15.sp, color: Colors.grey[500], fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

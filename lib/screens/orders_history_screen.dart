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
      backgroundColor: const Color(0xFFF1F5F9), // لون خلفية هادئ واحترافي
      appBar: AppBar(
        title: const Text(
          "سجل الرحلات المكتملة",
          style: TextStyle(
            fontFamily: 'Cairo',
            fontWeight: FontWeight.w900,
            fontSize: 22,
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black,
        toolbarHeight: 70, // زيادة ارتفاع الأبار لراحة العين
      ),
      body: SafeArea(
        // استخدام SafeArea لضمان عدم تداخل المحتوى مع النوتش أو الحواف
        bottom: false, 
        child: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('specialRequests')
              .where('driverId', isEqualTo: uid)
              .where('status', isEqualTo: 'delivered')
              .orderBy('completedAt', descending: true)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                child: Text(
                  "خطأ في تحميل سجل البيانات",
                  style: TextStyle(fontFamily: 'Cairo', fontSize: 14.sp, color: Colors.red),
                ),
              );
            }

            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(
                  color: Color(0xFFE65100), // برتقالي أكسب المميز
                  strokeWidth: 5,
                ),
              );
            }

            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
              return _buildEmptyState();
            }

            return ListView.builder(
              // بادينج احترافي: مسافة سفلية كبيرة (120) لضمان عدم الاختفاء خلف الـ BottomNav
              padding: EdgeInsets.fromLTRB(15.sp, 20.sp, 15.sp, 120.sp),
              itemCount: snapshot.data!.docs.length,
              physics: const BouncingScrollPhysics(), // حركة سلسة عند التمرير
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
    String formattedDate = date != null 
        ? DateFormat('dd MMMM yyyy | hh:mm a', 'ar').format(date) 
        : "تاريخ غير موثق";

    // حسابات مالية دقيقة (التعامل مع النقاط كقيم مالية)
    double total = double.tryParse(order['totalPrice']?.toString() ?? '0') ?? 0.0;
    double net = double.tryParse(order['driverNet']?.toString() ?? '0') ?? 0.0;
    double commission = (total - net).abs();

    return Container(
      margin: EdgeInsets.only(bottom: 20.sp),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28), // حواف دائرية عصرية
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 24,
            offset: const Offset(0, 12),
          )
        ],
      ),
      child: Column(
        children: [
          // رأس الكارت - تفاصيل الوقت والمعرف
          Container(
            padding: EdgeInsets.symmetric(horizontal: 18.sp, vertical: 12.sp),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF3E0), // برتقالي فاتح جداً
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.access_time_filled_rounded, size: 14.sp, color: Colors.orange[900]),
                    const SizedBox(width: 6),
                    Text(
                      formattedDate,
                      style: TextStyle(
                        color: Colors.orange[900],
                        fontSize: 10.5.sp,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Cairo',
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    "ID: ${order['orderId']?.toString().substring(0, 6) ?? 'N/A'}",
                    style: TextStyle(
                      color: Colors.grey[700],
                      fontSize: 9.sp,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // محتوى الكارت - المسار اللوجستي
          Padding(
            padding: EdgeInsets.all(20.sp),
            child: Column(
              children: [
                _buildRouteNode(
                  Icons.circle, 
                  Colors.green, 
                  "نقطة استلام العهدة", 
                  order['pickupAddress'] ?? "موقع غير محدد"
                ),
                // خط فاصل عمودي بين النقطتين
                Align(
                  alignment: Alignment.centerRight,
                  child: Container(
                    margin: EdgeInsets.only(right: 7.sp),
                    height: 20,
                    width: 2,
                    color: Colors.grey[200],
                  ),
                ),
                _buildRouteNode(
                  Icons.location_on_rounded, 
                  Colors.redAccent, 
                  "نقطة تسليم الأمانات", 
                  order['dropoffAddress'] ?? "موقع غير محدد"
                ),
                
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Divider(height: 1, thickness: 1, color: Color(0xFFF1F5F9)),
                ),

                // قسم البيانات المالية (أهم جزء للمندوب)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildFinanceWidget("قيمة الشحنة", total.toStringAsFixed(0), Colors.black87),
                    _buildFinanceWidget("تأمين المنصة", commission.toStringAsFixed(0), Colors.red[600]!),
                    _buildFinanceWidget("صافي ربحك", net.toStringAsFixed(0), const Color(0xFF2E7D32)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRouteNode(IconData icon, Color color, String label, String address) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 16.sp),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(color: Colors.grey, fontSize: 9.sp, fontFamily: 'Cairo'),
              ),
              Text(
                address,
                style: TextStyle(
                  fontSize: 12.sp,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'Cairo',
                  height: 1.4,
                  color: Colors.blueGrey[900],
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFinanceWidget(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(color: Colors.grey[500], fontSize: 9.5.sp, fontFamily: 'Cairo', fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: color.withOpacity(0.05),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            "$value ج.م",
            style: TextStyle(
              color: color,
              fontSize: 14.sp,
              fontWeight: FontWeight.w900,
              fontFamily: 'Cairo',
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(40),
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 20)],
            ),
            child: Icon(Icons.inventory_2_outlined, size: 80.sp, color: Colors.grey[300]),
          ),
          SizedBox(height: 4.h),
          Text(
            "سجل العهدة فارغ حالياً",
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 16.sp,
              color: Colors.blueGrey[800],
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            "ابدأ في قبول الطلبات لتظهر هنا",
            style: TextStyle(fontFamily: 'Cairo', fontSize: 11.sp, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}


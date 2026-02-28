import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:sizer/sizer.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

// اسم الملف المقترح: field_monitor_screen.dart

class FieldMonitorScreen extends StatefulWidget {
  const FieldMonitorScreen({super.key});

  @override
  State<FieldMonitorScreen> createState() => _FieldMonitorScreenState();
}

class _FieldMonitorScreenState extends State<FieldMonitorScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: AppBar(
        title: Text("المتابعة الميدانية للعهدة", 
          style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 16.sp)),
        centerTitle: true,
        backgroundColor: Colors.blueGrey[900],
        bottom: TabBar(
          controller: _tabController,
          labelStyle: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
          tabs: const [
            Tab(text: "كل الرحلات النشطة"),
            Tab(text: "تنبيهات المرتجع 🚨"),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildOrdersList(isOnlyReturns: false),
          _buildOrdersList(isOnlyReturns: true),
        ],
      ),
    );
  }

  Widget _buildOrdersList({required bool isOnlyReturns}) {
    // تحديد الحالات المطلوبة
    List<String> statuses = isOnlyReturns 
        ? ['returning_to_seller'] 
        : ['pending', 'accepted', 'picked_up', 'returning_to_seller'];

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('specialRequests')
          .where('status', whereIn: statuses)
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(child: Text(isOnlyReturns ? "لا توجد مرتجعات حالياً" : "لا توجد رحلات نشطة", 
            style: TextStyle(fontFamily: 'Cairo', fontSize: 13.sp)));
        }

        return ListView.builder(
          padding: EdgeInsets.all(10.sp),
          itemCount: snapshot.data!.docs.length,
          itemBuilder: (context, index) {
            var order = snapshot.data!.docs[index].data() as Map<String, dynamic>;
            return _buildOrderCard(order);
          },
        );
      },
    );
  }

  Widget _buildOrderCard(Map<String, dynamic> data) {
    bool isRetailer = data['requestSource'] == 'retailer';
    String status = data['status'];
    bool isMoneyLocked = data['moneyLocked'] ?? false;

    return Card(
      margin: EdgeInsets.only(bottom: 12.sp),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      elevation: 3,
      child: Column(
        children: [
          // شريط الحالة العلوي
          Container(
            padding: EdgeInsets.symmetric(horizontal: 12.sp, vertical: 6.sp),
            decoration: BoxDecoration(
              color: status == 'returning_to_seller' ? Colors.red[900] : (isRetailer ? Colors.blue[900] : Colors.orange[900]),
              borderRadius: const BorderRadius.only(topLeft: Radius.circular(15), topRight: Radius.circular(15)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(isRetailer ? "🏪 طلب تاجر" : "👤 طلب مستهلك", 
                  style: TextStyle(fontFamily: 'Cairo', color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10.sp)),
                Text(_translateStatus(status), 
                  style: TextStyle(fontFamily: 'Cairo', color: Colors.white, fontSize: 10.sp)),
              ],
            ),
          ),

          Padding(
            padding: EdgeInsets.all(12.sp),
            child: Column(
              children: [
                Row(
                  children: [
                    CircleAvatar(backgroundColor: Colors.blueGrey[50], child: Icon(Icons.person, color: Colors.blueGrey[800])),
                    SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(data['driverName'] ?? "في انتظار مندوب", 
                            style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 13.sp)),
                          Text("العهدة: ${data['insurance_points'] ?? 0} نقطة أمان", 
                            style: TextStyle(fontFamily: 'Cairo', color: Colors.blue[800], fontSize: 11.sp, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                    // زر اتصال سريع بالمندوب (إذا كان موجوداً) أو صاحب الطلب
                    IconButton(
                      icon: const Icon(Icons.phone_forwarded, color: Colors.green),
                      onPressed: () => launchUrl(Uri.parse("tel:${data['userPhone']}")),
                    ),
                  ],
                ),
                const Divider(),
                _locationLine(Icons.store, "موقع الاستلام: ${data['pickupAddress']}"),
                SizedBox(height: 5),
                _locationLine(Icons.location_on, "موقع التسليم: ${data['dropoffAddress']}"),
                const Divider(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(isMoneyLocked ? Icons.shield : Icons.error_outline, 
                          color: isMoneyLocked ? Colors.green : Colors.red, size: 14.sp),
                        SizedBox(width: 5),
                        Text(isMoneyLocked ? "عهدة مؤمنة ✅" : "عهدة غير مؤمنة ❌", 
                          style: TextStyle(fontFamily: 'Cairo', fontSize: 10.sp, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    Text(
                      "بدأ: ${data['createdAt'] != null ? DateFormat('hh:mm a').format((data['createdAt'] as Timestamp).toDate()) : ''}",
                      style: TextStyle(fontFamily: 'Cairo', color: Colors.grey[600], fontSize: 9.sp),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _locationLine(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 11.sp, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: TextStyle(fontFamily: 'Cairo', fontSize: 10.sp, color: Colors.black87), overflow: TextOverflow.ellipsis)),
      ],
    );
  }

  String _translateStatus(String status) {
    switch (status) {
      case 'pending': return "انتظار";
      case 'accepted': return "جاري التحرك للاستلام";
      case 'picked_up': return "العهدة في الطريق";
      case 'returning_to_seller': return "مرتجع نشط ⚠️";
      default: return status;
    }
  }
}



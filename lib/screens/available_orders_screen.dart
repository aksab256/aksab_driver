import 'dart:async'; // نحتاجه للعداد
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sizer/sizer.dart';
import 'active_order_screen.dart';

class AvailableOrdersScreen extends StatefulWidget {
  final String vehicleType;
  const AvailableOrdersScreen({super.key, required this.vehicleType});

  @override
  State<AvailableOrdersScreen> createState() => _AvailableOrdersScreenState();
}

class _AvailableOrdersScreenState extends State<AvailableOrdersScreen> {
  Position? _myCurrentLocation;
  bool _isGettingLocation = true;
  final String? _uid = FirebaseAuth.instance.currentUser?.uid;
  Timer? _uiTimer; // لتحديث الشاشة كل ثانية للعدادات

  @override
  void initState() {
    super.initState();
    _handleLocation();
    // تحديث الواجهة كل ثانية لتشغيل العدادات التنازلية
    _uiTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _uiTimer?.cancel();
    super.dispose();
  }

  // --- دوال اللوكيشن والإشعارات (تبقى كما هي في كودك الأصلي) ---
  Future<void> _handleLocation() async { /* ... */ }
  Future<void> _notifyUserOrderAccepted(String targetUserId, String orderId) async { /* ... */ }

  String _distToPickup(Map<String, dynamic> data) {
    GeoPoint? pickup = data['pickupLocation'];
    if (pickup == null || _myCurrentLocation == null) return "??";
    double dist = Geolocator.distanceBetween(
        _myCurrentLocation!.latitude, _myCurrentLocation!.longitude,
        pickup.latitude, pickup.longitude);
    return (dist / 1000).toStringAsFixed(1);
  }

  @override
  Widget build(BuildContext context) {
    if (_isGettingLocation) {
      return const Scaffold(body: Center(child: CircularProgressIndicator(color: Colors.orange)));
    }

    String cleanType = widget.vehicleType.replaceAll('Config', '');

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        toolbarHeight: 12.h,
        title: _buildAppBarTitle(),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0.5,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('specialRequests')
            .where('status', isEqualTo: 'pending')
            .where('vehicleType', isEqualTo: cleanType)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

          // فلترة الطلبات حسب المسافة (15 كم)
          final nearbyOrders = snapshot.data!.docs.where((doc) {
            var data = doc.data() as Map<String, dynamic>;
            GeoPoint? pickup = data['pickupLocation'];
            if (pickup == null || _myCurrentLocation == null) return true;
            double dist = Geolocator.distanceBetween(
                _myCurrentLocation!.latitude, _myCurrentLocation!.longitude,
                pickup.latitude, pickup.longitude);
            return dist <= 15000;
          }).toList();

          if (nearbyOrders.isEmpty) {
            return _buildEmptyState(cleanType);
          }

          return StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance.collection('freeDrivers').doc(_uid).snapshots(),
            builder: (context, driverSnap) {
              double displayBalance = 0;
              if (driverSnap.hasData && driverSnap.data!.exists) {
                 var dData = driverSnap.data!.data() as Map<String, dynamic>;
                 displayBalance = (dData['walletBalance'] ?? 0).toDouble() + (dData['creditLimit'] ?? 50.0).toDouble();
              }

              return ListView.builder(
                padding: const EdgeInsets.all(15),
                itemCount: nearbyOrders.length,
                itemBuilder: (context, index) => _buildOrderCard(nearbyOrders[index], displayBalance),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildOrderCard(DocumentSnapshot doc, double driverBalance) {
    var data = doc.data() as Map<String, dynamic>;
    
    // --- 💎 تنظيف الحسبة: القراءة مباشرة من الفايربيز 💎 ---
    double totalPrice = (data['totalPrice'] ?? 0.0).toDouble();
    double driverNet = (data['driverNet'] ?? 0.0).toDouble();
    double commission = (data['commissionAmount'] ?? 0.0).toDouble();
    
    // حساب الوقت المتبقي (15 دقيقة من createdAt)
    Timestamp? createdAt = data['createdAt'] as Timestamp?;
    String timeLeft = "00:00";
    bool isExpired = false;

    if (createdAt != null) {
      DateTime expiryTime = createdAt.toDate().add(const Duration(minutes: 15));
      Duration diff = expiryTime.difference(DateTime.now());
      if (diff.isNegative) {
        isExpired = true;
      } else {
        timeLeft = "${diff.inMinutes}:${(diff.inSeconds % 60).toString().padLeft(2, '0')}";
      }
    }

    bool canAccept = driverBalance >= commission;

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(25),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
      ),
      child: Column(
        children: [
          // رأس الكارت مع العداد
          Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: canAccept ? Colors.blueGrey[900] : Colors.grey[700],
              borderRadius: const BorderRadius.vertical(top: Radius.circular(25)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("صافي ربحك", style: TextStyle(color: Colors.white70, fontSize: 10.sp)),
                    Text("${driverNet.toStringAsFixed(2)} ج.م", 
                      style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 18.sp)),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(color: Colors.red.withOpacity(0.2), borderRadius: BorderRadius.circular(10)),
                  child: Row(
                    children: [
                      Icon(Icons.timer, color: Colors.redAccent, size: 14.sp),
                      const SizedBox(width: 5),
                      Text(timeLeft, style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 12.sp)),
                    ],
                  ),
                )
              ],
            ),
          ),
          
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                _infoRow(Icons.location_on, "من: ${data['pickupAddress']}", Colors.green),
                const SizedBox(height: 10),
                _infoRow(Icons.flag, "إلى: ${data['dropoffAddress']}", Colors.red),
                const Divider(height: 30),
                
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("المبلغ المطلوب من العميل:", style: TextStyle(fontSize: 11.sp)),
                    Text("${totalPrice.toStringAsFixed(2)} ج.م", style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 5),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("عمولة المنصة:", style: TextStyle(fontSize: 11.sp, color: Colors.orange[900])),
                    Text("- ${commission.toStringAsFixed(2)} ج.م", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange[900])),
                  ],
                ),
                
                const SizedBox(height: 20),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: canAccept ? Colors.green[700] : Colors.red[300],
                    minimumSize: Size(100.w, 7.h),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  ),
                  onPressed: canAccept ? () => _acceptOrder(doc.id, commission, data['userId']) : null,
                  child: Text(canAccept ? "قبول الطلب" : "رصيدك غير كافٍ للعمولة",
                      style: TextStyle(fontSize: 14.sp, color: Colors.white, fontWeight: FontWeight.bold)),
                )
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- دوال بناء الواجهة الفرعية ---
  Widget _buildAppBarTitle() { /* نفس كودك لعرض الرصيد */ return Container(); }
  Widget _buildEmptyState(String type) { /* رسالة لا توجد طلبات */ return Container(); }
  Widget _infoRow(IconData icon, String text, Color color) { /* ... */ return Container(); }

  // دالة القبول المحدثة
  Future<void> _acceptOrder(String orderId, double commission, String? customerId) async {
    // ... منطق الـ Transaction اللي كتبناه سابقاً ...
  }
}

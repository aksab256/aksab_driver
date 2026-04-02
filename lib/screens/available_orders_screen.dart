import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sizer/sizer.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'active_order_screen.dart';
import 'orders_heatmap_screen.dart'; // تأكد من استيراد الملف الجديد هنا

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
  Timer? _uiTimer;

  @override
  void initState() {
    super.initState();
    _updateDriverStatus('browsing_radar');
    _updateLocationSnapshot();
    // مؤقت لتحديث الوقت المتبقي في الكروت كل ثانية
    _uiTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _updateDriverStatus('online');
    _uiTimer?.cancel();
    super.dispose();
  }

  Future<void> _updateDriverStatus(String status) async {
    if (_uid != null) {
      try {
        await FirebaseFirestore.instance.collection('freeDrivers').doc(_uid).update({
          'currentStatus': status,
          'lastSeen': FieldValue.serverTimestamp(),
        });
      } catch (e) {
        debugPrint("❌ Error updating status: $e");
      }
    }
  }

  Future<void> _updateLocationSnapshot() async {
    try {
      Position pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 5),
        ),
      );

      if (mounted) {
        setState(() {
          _myCurrentLocation = pos;
          _isGettingLocation = false;
        });

        if (_uid != null) {
          await FirebaseFirestore.instance.collection('freeDrivers').doc(_uid).update({
            'lat': pos.latitude,
            'lng': pos.longitude,
            'lastLocationUpdate': FieldValue.serverTimestamp(),
          });
        }
      }
    } catch (e) {
      debugPrint("⚠️ Radar Location Error: $e");
      if (mounted) setState(() => _isGettingLocation = false);
    }
  }

  double _calculateFullTripDistance(GeoPoint pickup, GeoPoint dropoff) {
    if (_myCurrentLocation == null) return 0.0;
    double distanceToPickup = Geolocator.distanceBetween(
      _myCurrentLocation!.latitude,
      _myCurrentLocation!.longitude,
      pickup.latitude,
      pickup.longitude,
    );
    double pickupToDropoff = Geolocator.distanceBetween(
      pickup.latitude,
      pickup.longitude,
      dropoff.latitude,
      dropoff.longitude,
    );
    return (distanceToPickup + pickupToDropoff) / 1000;
  }

  String _getTimerText(Timestamp? createdAt) {
    if (createdAt == null) return "00:00";
    DateTime expiryTime = createdAt.toDate().add(const Duration(minutes: 15));
    Duration remaining = expiryTime.difference(DateTime.now());
    if (remaining.isNegative) return "منتهي";
    String minutes = remaining.inMinutes.toString().padLeft(2, '0');
    String seconds = (remaining.inSeconds % 60).toString().padLeft(2, '0');
    return "$minutes:$seconds";
  }

  Future<void> _acceptOrder(String orderId) async {
    try {
      showDialog(
          context: context,
          barrierDismissible: false,
          builder: (c) => const Center(child: CircularProgressIndicator(color: Colors.orange)));
      
      DocumentSnapshot driverProfile = await FirebaseFirestore.instance.collection('freeDrivers').doc(_uid).get();
      String driverName = driverProfile.exists ? (driverProfile.get('fullname') ?? "مندوب") : "مندوب";
      
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        DocumentReference orderRef = FirebaseFirestore.instance.collection('specialRequests').doc(orderId);
        DocumentReference driverRef = FirebaseFirestore.instance.collection('freeDrivers').doc(_uid);
        DocumentSnapshot orderSnap = await transaction.get(orderRef);

        if (orderSnap.exists && orderSnap.get('status') == 'pending') {
          transaction.update(orderRef, {
            'status': 'accepted',
            'driverId': _uid,
            'driverName': driverName,
            'acceptedAt': FieldValue.serverTimestamp(),
            'moneyLocked': false,
            'serverNote': "تأكيد العهدة: جاري معالجة الطلب ماليًا...",
          });
          transaction.update(driverRef, {
            'currentStatus': 'busy',
            'activeOrderId': orderId,
            'lastSeen': FieldValue.serverTimestamp(),
          });
        } else {
          throw Exception("عذراً، الطلب لم يعد متاحاً (تم قبوله من زميل آخر)");
        }
      });

      if (mounted) {
        Navigator.pop(context);
        Navigator.pushAndRemoveUntil(
            context, MaterialPageRoute(builder: (context) => ActiveOrderScreen(orderId: orderId)), (route) => false);
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e.toString().replaceAll("Exception: ", ""), style: const TextStyle(fontFamily: 'Cairo')),
            backgroundColor: Colors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isGettingLocation)
      return const Scaffold(body: Center(child: CircularProgressIndicator(color: Colors.orange)));
    
    String cleanType = widget.vehicleType.replaceAll('Config', '');

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text("رادار الطلبات القريبة",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16.sp, fontFamily: 'Cairo', color: Colors.black)),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0.5,
        actions: [
          // ✅ الزر الجديد للانتقال لخريطة الكثافة (الرادار الحراري)
          IconButton(
            icon: Icon(Icons.map_rounded, color: Colors.orange, size: 22.sp),
            tooltip: 'خريطة الكثافة',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => OrdersHeatmapScreen(vehicleType: widget.vehicleType),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.black),
            onPressed: () {
              setState(() => _isGettingLocation = true);
              _updateLocationSnapshot();
            },
          )
        ],
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('freeDrivers').doc(_uid).snapshots(),
        builder: (context, driverSnap) {
          double walletBalance = 0.0;
          if (driverSnap.hasData && driverSnap.data!.exists) {
            var dData = driverSnap.data!.data() as Map<String, dynamic>;
            walletBalance = double.tryParse(dData['walletBalance']?.toString() ?? '0') ?? 0.0;
          }

          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('specialRequests')
                .where('status', isEqualTo: 'pending')
                .where('vehicleType', isEqualTo: cleanType)
                .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: Colors.orange));

              final nearbyOrders = snapshot.data!.docs.where((doc) {
                var data = doc.data() as Map<String, dynamic>;
                GeoPoint? pickup = data['pickupLocation'];
                if (pickup == null || _myCurrentLocation == null) return false;
                double dist = Geolocator.distanceBetween(
                    _myCurrentLocation!.latitude, _myCurrentLocation!.longitude, pickup.latitude, pickup.longitude);
                return dist <= 15000; // شرط الـ 15 كيلومتر للظهور والقبول
              }).toList();

              if (nearbyOrders.isEmpty) {
                return Center(
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.radar, size: 60.sp, color: Colors.grey[300]),
                  Text("لا توجد طلبات متاحة حالياً",
                      style: TextStyle(fontFamily: 'Cairo', fontSize: 14.sp, color: Colors.grey))
                ]));
              }

              return ListView.builder(
                padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 2.h),
                itemCount: nearbyOrders.length,
                itemBuilder: (context, index) => _buildOrderCard(nearbyOrders[index], walletBalance),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildOrderCard(DocumentSnapshot doc, double walletBalance) {
    var data = doc.data() as Map<String, dynamic>;
    GeoPoint? pickupLoc = data['pickupLocation'];
    GeoPoint? dropoffLoc = data['dropoffLocation'];
    double fullDistance = 0.0;
    if (pickupLoc != null && dropoffLoc != null) {
      fullDistance = _calculateFullTripDistance(pickupLoc, dropoffLoc);
    }
    
    double driverNet = double.tryParse(data['driverNet']?.toString() ?? '0') ?? 0.0;
    double orderFinalAmount = double.tryParse(data['orderFinalAmount']?.toString() ?? '0') ?? 0.0;
    double totalPrice = double.tryParse(data['totalPrice']?.toString() ?? '0') ?? 0.0;
    
    // حساب العهدة المطلوبة (نقاط التأمين)
    double insuranceRequired = (orderFinalAmount > 0) ? (orderFinalAmount - driverNet) : 0.0;
    if (insuranceRequired < 0) insuranceRequired = 0;
    
    bool canAccept = (walletBalance >= insuranceRequired);
    bool isMerchant = data['requestSource'] == 'retailer';
    String timeLeft = _getTimerText(data['createdAt'] as Timestamp?);

    return Container(
      margin: EdgeInsets.only(bottom: 2.5.h),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: isMerchant ? Colors.orange.withOpacity(0.15) : Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4))
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 1.5.h),
            decoration: BoxDecoration(
              gradient: isMerchant
                  ? const LinearGradient(colors: [Color(0xFFFFD700), Color(0xFFFFA000)])
                  : LinearGradient(colors: [Colors.blueGrey[800]!, Colors.blueGrey[900]!]),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(isMerchant ? FontAwesomeIcons.solidStar : Icons.delivery_dining,
                        color: isMerchant ? const Color(0xFF5D4037) : Colors.white, size: 18.sp),
                    SizedBox(width: 3.w),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("ربحك الصافي",
                            style: TextStyle(
                                color: isMerchant ? const Color(0xFF5D4037).withOpacity(0.7) : Colors.white70,
                                fontSize: 10.sp,
                                fontFamily: 'Cairo')),
                        Text("$driverNet ج.م",
                            style: TextStyle(
                                color: isMerchant ? const Color(0xFF5D4037) : Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 18.sp,
                                fontFamily: 'Cairo')),
                      ],
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration:
                      BoxDecoration(color: Colors.black.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                  child: Row(
                    children: [
                      Icon(Icons.timer_outlined,
                          size: 12.sp, color: isMerchant ? const Color(0xFF5D4037) : Colors.orangeAccent),
                      const SizedBox(width: 5),
                      Text(timeLeft,
                          style: TextStyle(
                              color: isMerchant ? const Color(0xFF5D4037) : Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 11.sp)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.all(4.w),
            child: Column(
              children: [
                Row(
                  children: [
                    _buildTag(Icons.map_outlined, "${fullDistance.toStringAsFixed(1)} كم", Colors.blue[700]!),
                    SizedBox(width: 2.w),
                    _buildTag(Icons.security, "${insuranceRequired.toStringAsFixed(0)} عهدة", Colors.red[700]!),
                    const Spacer(),
                    Text("إجمالي: $totalPrice ج.م",
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.sp, color: Colors.black87)),
                  ],
                ),
                const Divider(height: 30),
                _buildRouteItem(Icons.radio_button_checked, "من: ${data['userName'] ?? 'الموقع'}",
                    data['pickupAddress'] ?? "...", Colors.orange[800]!),
                SizedBox(height: 1.5.h),
                _buildRouteItem(Icons.location_on, "إلى: ${data['customerName'] ?? 'العميل'}",
                    data['dropoffAddress'] ?? "...", Colors.red[800]!),
                SizedBox(height: 3.h),
                SizedBox(
                  width: double.infinity,
                  height: 7.h,
                  child: ElevatedButton(
                    onPressed: canAccept ? () => _acceptOrder(doc.id) : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: canAccept
                          ? (isMerchant ? const Color(0xFF5D4037) : const Color(0xFF2D9E68))
                          : Colors.grey[400],
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                      elevation: 0,
                    ),
                    child: Text(
                      canAccept ? "تأكيد العهدة وقبول الطلب" : "رصيد الكاش غير كافٍ",
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14.sp, fontFamily: 'Cairo'),
                    ),
                  ),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildTag(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
      child: Row(
        children: [
          Icon(icon, size: 18.sp, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(color: color, fontSize: 11.sp, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
        ],
      ),
    );
  }

  Widget _buildRouteItem(IconData icon, String title, String sub, Color color) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 16.sp),
        SizedBox(width: 3.w),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: TextStyle(
                      fontSize: 10.sp, fontWeight: FontWeight.bold, color: Colors.black87, fontFamily: 'Cairo')),
              Text(sub,
                  style: TextStyle(fontSize: 12.5.sp, color: Colors.grey[600], fontFamily: 'Cairo'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ],
    );
  }
}


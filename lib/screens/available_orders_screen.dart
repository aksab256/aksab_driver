import 'dart:async';
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
  Timer? _uiTimer;

  @override
  void initState() {
    super.initState();
    _initSequence();
    _uiTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _uiTimer?.cancel();
    super.dispose();
  }

  double _calculateFullTripDistance(GeoPoint pickup, GeoPoint dropoff) {
    if (_myCurrentLocation == null) return 0.0;
    double toPickup = Geolocator.distanceBetween(
      _myCurrentLocation!.latitude, _myCurrentLocation!.longitude,
      pickup.latitude, pickup.longitude,
    );
    double toCustomer = Geolocator.distanceBetween(
      pickup.latitude, pickup.longitude,
      dropoff.latitude, dropoff.longitude,
    );
    return (toPickup + toCustomer) / 1000;
  }

  Future<bool> _showLocationDisclosure() async {
    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
          title: Row(
            children: [
              const Icon(Icons.radar, color: Colors.orange, size: 30),
              SizedBox(width: 3.w),
              const Text("رادار الطلبات القريبة", style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
            ],
          ),
          content: Text(
            "لكي نتمكن من عرض الطلبات القريبة منك وتنبيهك بها، يحتاج 'أكسب' للوصول إلى موقعك الجغرافي.\n\n"
            "سيتم استخدام الموقع أيضاً لتحديث مكانك للعميل أثناء التوصيل حتى لو كان التطبيق مغلقاً أو في الخلفية.",
            style: TextStyle(fontFamily: 'Cairo', fontSize: 11.sp, height: 1.6),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("ليس الآن", style: TextStyle(fontFamily: 'Cairo', color: Colors.grey))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              onPressed: () => Navigator.pop(context, true),
              child: const Text("موافق ومتابعة", style: TextStyle(fontFamily: 'Cairo', color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    ) ?? false;
  }

  Future<void> _initSequence() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) setState(() => _isGettingLocation = false);
      return;
    }
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      bool userAccepted = await _showLocationDisclosure();
      if (!userAccepted) {
        if (mounted) setState(() => _isGettingLocation = false);
        return;
      }
      permission = await Geolocator.requestPermission();
    }
    
    try {
      Position pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      if (mounted) setState(() { _myCurrentLocation = pos; _isGettingLocation = false; });
    } catch (e) {
      if (mounted) setState(() => _isGettingLocation = false);
    }
  }

  // ... (نفس دالات _notifyCustomerOrderAccepted و _acceptOrder بدون تغيير)

  @override
  Widget build(BuildContext context) {
    if (_isGettingLocation) return const Scaffold(body: Center(child: CircularProgressIndicator(color: Colors.orange)));
    String cleanType = widget.vehicleType.replaceAll('Config', '');

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text("رادار الطلبات ($cleanType)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.sp, fontFamily: 'Cairo')),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0.5,
      ),
      body: SafeArea( // ✅ حماية المحتوى من الحواف
        child: StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance.collection('freeDrivers').doc(_uid).snapshots(),
          builder: (context, driverSnap) {
            double displayBalance = 0;
            if (driverSnap.hasData && driverSnap.data!.exists) {
              var dData = driverSnap.data!.data() as Map<String, dynamic>;
              double wallet = double.tryParse(dData['walletBalance']?.toString() ?? '0') ?? 0.0;
              double limit = double.tryParse(dData['creditLimit']?.toString() ?? '50') ?? 50.0;
              displayBalance = wallet + limit;
            }

            return StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('specialRequests')
                  .where('status', isEqualTo: 'pending')
                  .where('vehicleType', isEqualTo: cleanType)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) return const Center(child: Text("خطأ في الاتصال"));
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

                final nearbyOrders = snapshot.data!.docs.where((doc) {
                  var data = doc.data() as Map<String, dynamic>;
                  GeoPoint? pickup = data['pickupLocation'];
                  if (pickup == null || _myCurrentLocation == null) return false;
                  double dist = Geolocator.distanceBetween(_myCurrentLocation!.latitude, _myCurrentLocation!.longitude, pickup.latitude, pickup.longitude);
                  return dist <= 15000;
                }).toList();

                if (nearbyOrders.isEmpty) return Center(child: Text("لا توجد طلبات $cleanType متاحة حالياً", style: const TextStyle(fontFamily: 'Cairo')));

                return ListView.builder(
                  padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 2.h),
                  itemCount: nearbyOrders.length,
                  itemBuilder: (context, index) => _buildOrderCard(nearbyOrders[index], displayBalance),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildOrderCard(DocumentSnapshot doc, double driverBalance) {
    var data = doc.data() as Map<String, dynamic>;
    double totalPrice = double.tryParse(data['totalPrice']?.toString() ?? '0') ?? 0.0;
    double driverNet = double.tryParse(data['driverNet']?.toString() ?? '0') ?? 0.0;
    double commission = double.tryParse(data['commissionAmount']?.toString() ?? '0') ?? 0.0;
    GeoPoint pickup = data['pickupLocation'];
    GeoPoint dropoff = data['dropoffLocation'];
    double totalTripKm = _calculateFullTripDistance(pickup, dropoff);

    Timestamp? createdAt = data['createdAt'] as Timestamp?;
    String timeLeft = "15:00";
    if (createdAt != null) {
      DateTime expiryTime = createdAt.toDate().add(const Duration(minutes: 15));
      Duration diff = expiryTime.difference(DateTime.now());
      if (diff.isNegative) return const SizedBox.shrink();
      timeLeft = "${diff.inMinutes}:${(diff.inSeconds % 60).toString().padLeft(2, '0')}";
    }

    bool canAccept = driverBalance >= commission;

    return Card(
      elevation: 3,
      shadowColor: Colors.black26,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      margin: EdgeInsets.only(bottom: 2.h),
      child: Column(
        children: [
          Container(
            padding: EdgeInsets.symmetric(horizontal: 5.w, vertical: 1.2.h),
            decoration: BoxDecoration(
              color: canAccept ? const Color(0xFF2D9E68) : Colors.red[600],
              borderRadius: const BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("صافي ربحك: $driverNet ج.م", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12.sp, fontFamily: 'Cairo')),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(8)),
                  child: Text("⏳ $timeLeft", style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.all(4.w),
            child: Column(
              children: [
                // ✅ عرض المسافة بشكل بارز جداً
                Container(
                  padding: EdgeInsets.symmetric(vertical: 1.h, horizontal: 3.w),
                  decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.blue.shade100)),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.route_rounded, color: Colors.blue[800], size: 20),
                      SizedBox(width: 2.w),
                      Text(
                        "إجمالي المشوار: ${totalTripKm.toStringAsFixed(1)} كم تقريباً",
                        style: TextStyle(color: Colors.blue[900], fontWeight: FontWeight.w900, fontSize: 12.sp, fontFamily: 'Cairo'),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 2.h),
                _buildRouteRow(Icons.store_mall_directory_rounded, "نقطة الاستلام (المحل):", data['pickupAddress'] ?? "المتجر", Colors.orange),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 0.5.h),
                  child: Align(alignment: Alignment.centerRight, child: Container(width: 2, height: 20, color: Colors.grey.shade300)),
                ),
                _buildRouteRow(Icons.location_on_rounded, "نقطة التسليم (العميل):", data['dropoffAddress'] ?? "العميل", Colors.red),
                
                const Divider(height: 30),
                
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text("المطلوب تحصيله من العميل:", style: TextStyle(fontSize: 10.sp, color: Colors.grey.shade700, fontFamily: 'Cairo')),
                  Text("$totalPrice ج.م", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.sp, color: Colors.black)),
                ]),
                
                SizedBox(height: 2.h),
                
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: canAccept ? const Color(0xFF2D9E68) : Colors.grey.shade400,
                    minimumSize: Size(100.w, 7.h),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                    elevation: 2,
                  ),
                  onPressed: canAccept ? () => _acceptOrder(doc.id, commission, data['userId']) : null,
                  child: Text(
                    canAccept ? "قبول الطلب والتحرك الآن" : "الرصيد غير كافٍ.. اشحن محفظتك",
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13.sp, fontFamily: 'Cairo')
                  ),
                )
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildRouteRow(IconData icon, String label, String addr, Color color) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 22),
        SizedBox(width: 3.w),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 9.sp, color: Colors.grey[600], fontFamily: 'Cairo')),
            SizedBox(height: 0.5.h),
            Text(
              addr, 
              style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.bold, color: Colors.black87, fontFamily: 'Cairo'), 
              maxLines: 2, 
              overflow: TextOverflow.ellipsis
            ),
          ],
        )),
    ]);
  }
}

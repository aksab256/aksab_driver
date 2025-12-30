import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sizer/sizer.dart';
import 'active_order_screen.dart';

class AvailableOrdersScreen extends StatefulWidget {
  final String vehicleType; // مثل "motorcycleConfig" أو "jumboConfig"
  const AvailableOrdersScreen({super.key, required this.vehicleType});

  @override
  State<AvailableOrdersScreen> createState() => _AvailableOrdersScreenState();
}

class _AvailableOrdersScreenState extends State<AvailableOrdersScreen> {
  Position? _myCurrentLocation;
  bool _isGettingLocation = true;
  final String? _uid = FirebaseAuth.instance.currentUser?.uid;

  @override
  void initState() {
    super.initState();
    _handleLocation();
  }

  Future<void> _handleLocation() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      Position pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      if (mounted) {
        setState(() {
          _myCurrentLocation = pos;
          _isGettingLocation = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isGettingLocation = false);
    }
  }

  String _distToPickup(Map<String, dynamic> data) {
    GeoPoint? pickup = data['pickupLocation'];
    if (pickup == null || _myCurrentLocation == null) return "??";
    double dist = Geolocator.distanceBetween(
        _myCurrentLocation!.latitude, _myCurrentLocation!.longitude,
        pickup.latitude, pickup.longitude);
    return (dist / 1000).toStringAsFixed(1);
  }

  String _tripDistance(Map<String, dynamic> data) {
    GeoPoint? pickup = data['pickupLocation'];
    GeoPoint? dropoff = data['dropoffLocation'];
    if (pickup == null || dropoff == null) return "غير محدد";
    double dist = Geolocator.distanceBetween(
        pickup.latitude, pickup.longitude,
        dropoff.latitude, dropoff.longitude);
    return (dist / 1000).toStringAsFixed(1);
  }

  @override
  Widget build(BuildContext context) {
    if (_isGettingLocation) {
      return const Scaffold(body: Center(child: CircularProgressIndicator(color: Colors.orange)));
    }

    String cleanType = widget.vehicleType.replaceAll('Config', '');

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('systemConfiguration').doc('globalCreditSettings').snapshots(),
      builder: (context, globalSnap) {
        double defaultGlobalLimit = (globalSnap.hasData && globalSnap.data!.exists)
            ? (globalSnap.data!['defaultLimit'] ?? 50.0).toDouble()
            : 50.0;

        return StreamBuilder<DocumentSnapshot>(
          // جلب الإعدادات الهجينة من appSettings
          stream: FirebaseFirestore.instance.collection('appSettings').doc(widget.vehicleType).snapshots(),
          builder: (context, configSnap) {
            Map<String, dynamic> configData = {};
            if (configSnap.hasData && configSnap.data!.exists) {
              configData = configSnap.data!.data() as Map<String, dynamic>;
            }

            return StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance.collection('freeDrivers').doc(_uid).snapshots(),
              builder: (context, driverSnap) {
                double walletBalance = 0;
                double? driverSpecificLimit;

                if (driverSnap.hasData && driverSnap.data!.exists) {
                  var dData = driverSnap.data!.data() as Map<String, dynamic>;
                  walletBalance = (dData['walletBalance'] ?? 0).toDouble();
                  driverSpecificLimit = dData['creditLimit']?.toDouble();
                }

                double finalLimit = driverSpecificLimit ?? defaultGlobalLimit;
                double displayBalance = walletBalance + finalLimit;
                bool hasInitialBalance = displayBalance > 0;

                return Scaffold(
                  backgroundColor: Colors.grey[100],
                  appBar: AppBar(
                    toolbarHeight: 12.h,
                    title: Column(
                      children: [
                        Text("رادار الطلبات المتاحة",
                            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16.sp, color: Colors.black)),
                        SizedBox(height: 1.h),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                              color: hasInitialBalance ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12)),
                          child: Text("الرصيد المتاح للتشغيل: $displayBalance ج.م",
                              style: TextStyle(fontSize: 11.sp, color: hasInitialBalance ? Colors.green[800] : Colors.red, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
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
                        return Center(child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.radar, size: 50.sp, color: Colors.grey[300]),
                            SizedBox(height: 2.h),
                            Text("لا توجد طلبات $cleanType قريبة حالياً",
                                style: TextStyle(fontSize: 15.sp, color: Colors.grey[600], fontWeight: FontWeight.bold)),
                          ],
                        ));
                      }

                      return ListView.builder(
                        padding: const EdgeInsets.all(15),
                        itemCount: nearbyOrders.length,
                        itemBuilder: (context, index) => _buildOrderCard(nearbyOrders[index], displayBalance, configData),
                      );
                    },
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildOrderCard(DocumentSnapshot doc, double displayBalance, Map<String, dynamic> config) {
    var data = doc.data() as Map<String, dynamic>;
    double totalPrice = (data['price'] ?? 0).toDouble();
    String tripDist = _tripDistance(data);
    String distToMe = _distToPickup(data);

    // الحسبة الهجينة (Hybrid Logic)
    double serviceFeePercent = (config['serviceFeePercentage'] ?? 10.0).toDouble();
    double minFee = (config['minServiceFee'] ?? 5.0).toDouble();
    
    double calculatedFromPercent = totalPrice * (serviceFeePercent / 100);
    // نأخذ القيمة الأكبر بين النسبة والحد الأدنى
    double finalCommission = (calculatedFromPercent > minFee) ? calculatedFromPercent : minFee;
    double driverNet = totalPrice - finalCommission;

    // فحص الرصيد المتاح للتشغيل مقابل عمولة هذا الطلب تحديداً
    bool canAcceptThisOrder = displayBalance >= finalCommission;

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(25),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 5))],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: canAcceptThisOrder ? Colors.orange[900] : Colors.grey[700],
              borderRadius: const BorderRadius.vertical(top: Radius.circular(25)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("إجمالي التحصيل", style: TextStyle(color: Colors.white70, fontSize: 11.sp)),
                    Text("$totalPrice ج.م", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 20.sp)),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text("صافي ربحك", style: TextStyle(color: Colors.white70, fontSize: 11.sp)),
                    Text("${driverNet.toStringAsFixed(1)} ج.م", style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.w900, fontSize: 18.sp)),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(Icons.directions_bike, color: Colors.blue[800], size: 18.sp),
                    const SizedBox(width: 10),
                    Text("يبعد عنك: $distToMe كم | المشوار: $tripDist كم",
                        style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.bold, color: Colors.blue[900])),
                  ],
                ),
                const Divider(height: 30, thickness: 1),
                _infoRow(Icons.storefront, "من: ${data['pickupAddress'] ?? 'نقطة الاستلام'}", Colors.green[700]!),
                const SizedBox(height: 12),
                _infoRow(Icons.location_on, "إلى: ${data['dropoffAddress'] ?? 'نقطة التسليم'}", Colors.red[700]!),
                const SizedBox(height: 20),
                
                // تفاصيل العمولة الهجينة للتوضيح للمندوب
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.orange[50], borderRadius: BorderRadius.circular(15)),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.info_outline, size: 14.sp, color: Colors.orange[900]),
                      const SizedBox(width: 8),
                      Text("عمولة المنصة المحجوزة: ${finalCommission.toStringAsFixed(1)} ج.م", 
                        style: TextStyle(fontSize: 11.sp, color: Colors.orange[900], fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                
                const SizedBox(height: 25),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: canAcceptThisOrder ? Colors.green[800] : Colors.red[400],
                    minimumSize: Size(100.w, 8.h),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    elevation: canAcceptThisOrder ? 5 : 0,
                  ),
                  onPressed: canAcceptThisOrder ? () => _acceptOrder(doc.id, finalCommission) : () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(backgroundColor: Colors.red, content: Text("رصيدك الحالي لا يغطي عمولة الطلب (${finalCommission.toStringAsFixed(1)} ج.م)"))
                    );
                  },
                  child: Text(canAcceptThisOrder ? "قبول الطلب فوراً" : "اشحن المحفظة للقبول",
                      style: TextStyle(fontSize: 17.sp, color: Colors.white, fontWeight: FontWeight.w900)),
                )
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String text, Color color) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20.sp, color: color),
        const SizedBox(width: 12),
        Expanded(
          child: Text(text,
              style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.bold, color: Colors.black87),
              maxLines: 2, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }

  Future<void> _acceptOrder(String orderId, double commissionAmount) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    showDialog(context: context, barrierDismissible: false, builder: (c) => const Center(child: CircularProgressIndicator()));
    final orderRef = FirebaseFirestore.instance.collection('specialRequests').doc(orderId);

    try {
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        DocumentSnapshot snapshot = await transaction.get(orderRef);
        if (!snapshot.exists || snapshot.get('status') != 'pending') {
          throw "عذراً، سبقك مندوب آخر لقبول الطلب!";
        }
        transaction.update(orderRef, {
          'status': 'accepted',
          'driverId': uid,
          'acceptedAt': FieldValue.serverTimestamp(),
          'commissionAmount': commissionAmount, // حفظ العمولة المحسوبة في الطلب
        });
      });
      if (!mounted) return;
      Navigator.pop(context);
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => ActiveOrderScreen(orderId: orderId)));
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: Colors.red, content: Text(e.toString())));
    }
  }
}


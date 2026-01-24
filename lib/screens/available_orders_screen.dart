import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
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

  // ✅ [الذكاء الاصطناعي] دالة حساب المسافة الإجمالية المتوقعة قبل القبول
  double _calculateFullTripDistance(GeoPoint pickup, GeoPoint dropoff) {
    if (_myCurrentLocation == null) return 0.0;

    // 1. المسافة من مكان المندوب للمحل
    double toPickup = Geolocator.distanceBetween(
      _myCurrentLocation!.latitude, _myCurrentLocation!.longitude,
      pickup.latitude, pickup.longitude,
    );

    // 2. المسافة من المحل للعميل
    double toCustomer = Geolocator.distanceBetween(
      pickup.latitude, pickup.longitude,
      dropoff.latitude, dropoff.longitude,
    );

    return (toPickup + toCustomer) / 1000; // تحويل لكيلومتر
  }

  Future<bool> _showLocationDisclosure() async {
    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.location_on, color: Colors.orange),
            SizedBox(width: 10),
            Text("تفعيل رادار الطلبات", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: const Text(
          "لكي نتمكن من عرض الطلبات القريبة منك وتنبيهك بها، يحتاج 'أكسب' للوصول إلى موقعك. "
          "\n\nسيتم استخدام الموقع أيضاً لتتبع الطلب وتحديث مكانك للعميل حتى لو كان التطبيق مغلقاً أو في الخلفية.",
          textAlign: TextAlign.right,
          style: TextStyle(height: 1.5),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("ليس الآن")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            onPressed: () => Navigator.pop(context, true),
            child: const Text("موافق ومتابعة", style: TextStyle(color: Colors.white)),
          ),
        ],
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
      if (permission == LocationPermission.denied) {
        if (mounted) setState(() => _isGettingLocation = false);
        return;
      }
    }
    if (permission == LocationPermission.deniedForever) {
      if (mounted) setState(() => _isGettingLocation = false);
      return;
    }
    try {
      Position pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      if (mounted) setState(() { _myCurrentLocation = pos; _isGettingLocation = false; });
    } catch (e) {
      if (mounted) setState(() => _isGettingLocation = false);
    }
  }

  Future<void> _notifyCustomerOrderAccepted(String customerId, String orderId) async {
    const String lambdaUrl = 'https://9ayce138ig.execute-api.us-east-1.amazonaws.com/V1/nofiction';
    try {
      var endpointSnap = await FirebaseFirestore.instance.collection('UserEndpoints').doc(customerId).get();
      if (!endpointSnap.exists || endpointSnap.data()?['endpointArn'] == null) return;
      String arn = endpointSnap.data()!['endpointArn'];
      final payload = {
        "userId": arn, "title": "طلبك اتقبل! ✨",
        "message": "مندوب أكسب في طريقه ليك دلوقتي، تقدر تتابعه من الخريطة.",
        "orderId": orderId,
      };
      await http.post(Uri.parse(lambdaUrl), headers: {"Content-Type": "application/json"}, body: json.encode(payload));
    } catch (e) { debugPrint("Notification Error: $e"); }
  }

  Future<void> _acceptOrder(String orderId, double commission, String? customerId) async {
    if (_uid == null) return;
    showDialog(context: context, barrierDismissible: false, builder: (c) => const Center(child: CircularProgressIndicator(color: Colors.orange)));
    final orderRef = FirebaseFirestore.instance.collection('specialRequests').doc(orderId);
    final driverRef = FirebaseFirestore.instance.collection('freeDrivers').doc(_uid);
    try {
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        DocumentSnapshot orderSnap = await transaction.get(orderRef);
        DocumentSnapshot driverSnap = await transaction.get(driverRef);
        if (!orderSnap.exists || orderSnap.get('status') != 'pending') throw "يا خسارة! مندوب تاني سبقك للطلب ده.";
        double wallet = double.tryParse(driverSnap.get('walletBalance')?.toString() ?? '0') ?? 0.0;
        double limit = double.tryParse(driverSnap.get('creditLimit')?.toString() ?? '50') ?? 50.0;
        if ((wallet + limit) < commission) throw "رصيدك مش كفاية، اشحن محفظتك عشان تقدر تقبل الطلب.";
        transaction.update(orderRef, {'status': 'accepted', 'driverId': _uid, 'acceptedAt': FieldValue.serverTimestamp(), 'commissionAmount': commission});
      });
      if (customerId != null) _notifyCustomerOrderAccepted(customerId, orderId);
      if (!mounted) return;
      Navigator.pop(context);
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => ActiveOrderScreen(orderId: orderId)));
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: Colors.red, content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isGettingLocation) return const Scaffold(body: Center(child: CircularProgressIndicator(color: Colors.orange)));
    String cleanType = widget.vehicleType.replaceAll('Config', '');

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Text("رادار الطلبات القريبة", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.sp)),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: StreamBuilder<DocumentSnapshot>(
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

              if (nearbyOrders.isEmpty) return Center(child: Text("مفيش طلبات $cleanType قريبة دلوقتي"));

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
    double totalPrice = double.tryParse(data['totalPrice']?.toString() ?? '0') ?? 0.0;
    double driverNet = double.tryParse(data['driverNet']?.toString() ?? '0') ?? 0.0;
    double commission = double.tryParse(data['commissionAmount']?.toString() ?? '0') ?? 0.0;
    GeoPoint pickup = data['pickupLocation'];
    GeoPoint dropoff = data['dropoffLocation'];

    // ✅ حقن حساب المسافة الإجمالية
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
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      margin: const EdgeInsets.only(bottom: 15),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
            decoration: BoxDecoration(
              color: canAccept ? Colors.green[600] : Colors.red[600],
              borderRadius: const BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("صافي ربحك: $driverNet ج.م", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                Text("ينتهي خلال: $timeLeft", style: const TextStyle(color: Colors.white, fontSize: 10)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(15),
            child: Column(
              children: [
                // ✅ عرض المسافة الإجمالية بوضوح
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(10)),
                  child: Row(
                    children: [
                      Icon(Icons.directions_run, color: Colors.blue[900], size: 18),
                      const SizedBox(width: 8),
                      Text(
                        "إجمالي المسافة المتوقعة: ${totalTripKm.toStringAsFixed(1)} كم",
                        style: TextStyle(color: Colors.blue[900], fontWeight: FontWeight.bold, fontSize: 11.sp),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 15),
                _buildRouteRow(Icons.store, "من:", data['pickupAddress'] ?? "المتجر", Colors.orange),
                const Padding(
                  padding: EdgeInsets.only(right: 20),
                  child: Icon(Icons.more_vert, color: Colors.grey, size: 15),
                ),
                _buildRouteRow(Icons.person_pin_circle, "إلى:", data['dropoffAddress'] ?? "العميل", Colors.red),
                const Divider(height: 30),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text("المطلوب تحصيله:", style: TextStyle(fontSize: 11.sp)),
                  Text("$totalPrice ج.م", style: const TextStyle(fontWeight: FontWeight.bold)),
                ]),
                const SizedBox(height: 20),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: canAccept ? Colors.green[700] : Colors.grey,
                    minimumSize: Size(100.w, 6.h),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))
                  ),
                  onPressed: canAccept ? () => _acceptOrder(doc.id, commission, data['userId']) : null,
                  child: Text(canAccept ? "قبول الطلب والبدء فوراً" : "الرصيد مش كفاية.. اشحن دلوقتي",
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13.sp)),
                )
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildRouteRow(IconData icon, String label, String addr, Color color) {
    return Row(children: [
      Icon(icon, color: color, size: 18.sp),
      const SizedBox(width: 10),
      Expanded(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 9.sp, color: Colors.grey[600])),
          Text(addr, style: TextStyle(fontSize: 11.sp, fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      )),
    ]);
  }
}

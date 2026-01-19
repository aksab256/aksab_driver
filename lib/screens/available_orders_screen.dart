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

  Future<void> _initSequence() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) setState(() => _isGettingLocation = false);
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (mounted) setState(() => _isGettingLocation = false);
        return;
      }
    }
    
    try {
      Position pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      if (mounted) setState(() { _myCurrentLocation = pos; _isGettingLocation = false; });
    } catch (e) {
      if (mounted) setState(() => _isGettingLocation = false);
    }
  }

  // --- 🔔 دالة الإشعارات بالـ ARN (مصري) ---
  Future<void> _notifyCustomerOrderAccepted(String customerId, String orderId) async {
    const String lambdaUrl = 'https://9ayce138ig.execute-api.us-east-1.amazonaws.com/V1/nofiction';
    try {
      var endpointSnap = await FirebaseFirestore.instance.collection('UserEndpoints').doc(customerId).get();
      if (!endpointSnap.exists || endpointSnap.data()?['endpointArn'] == null) return;

      String arn = endpointSnap.data()!['endpointArn'];
      final payload = {
        "userId": arn,
        "title": "طلبك اتقبل! ✨",
        "message": "مندوب أكسب في طريقه ليك دلوقتي، تقدر تتابعه من الخريطة.",
        "orderId": orderId,
      };

      await http.post(Uri.parse(lambdaUrl), 
        headers: {"Content-Type": "application/json"}, 
        body: json.encode(payload)
      );
    } catch (e) { debugPrint("Notification Error: $e"); }
  }

  // --- 🤝 دالة القبول المؤمنة بـ Transaction ---
  Future<void> _acceptOrder(String orderId, double commission, String? customerId) async {
    if (_uid == null) return;

    showDialog(
      context: context, 
      barrierDismissible: false, 
      builder: (c) => const Center(child: CircularProgressIndicator(color: Colors.orange))
    );

    final orderRef = FirebaseFirestore.instance.collection('specialRequests').doc(orderId);
    final driverRef = FirebaseFirestore.instance.collection('freeDrivers').doc(_uid);

    try {
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        DocumentSnapshot orderSnap = await transaction.get(orderRef);
        DocumentSnapshot driverSnap = await transaction.get(driverRef);

        if (!orderSnap.exists || orderSnap.get('status') != 'pending') {
          throw "يا خسارة! مندوب تاني سبقك للطلب ده.";
        }

        double wallet = double.tryParse(driverSnap.get('walletBalance')?.toString() ?? '0') ?? 0.0;
        double limit = double.tryParse(driverSnap.get('creditLimit')?.toString() ?? '50') ?? 50.0;
        
        if ((wallet + limit) < commission) {
          throw "رصيدك مش كفاية، اشحن محفظتك عشان تقدر تقبل الطلب.";
        }

        transaction.update(orderRef, {
          'status': 'accepted',
          'driverId': _uid,
          'acceptedAt': FieldValue.serverTimestamp(),
          'commissionAmount': commission,
        });
      });

      if (customerId != null) _notifyCustomerOrderAccepted(customerId, orderId);

      if (!mounted) return;
      Navigator.pop(context); // إغلاق الـ Loading
      Navigator.pushReplacement(
        context, 
        MaterialPageRoute(builder: (context) => ActiveOrderScreen(orderId: orderId))
      );

    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: Colors.red, content: Text(e.toString()))
      );
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
              if (snapshot.hasError) return Center(child: Text("خطأ في الاتصال"));
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

              final nearbyOrders = snapshot.data!.docs.where((doc) {
                var data = doc.data() as Map<String, dynamic>;
                GeoPoint? pickup = data['pickupLocation'];
                if (pickup == null || _myCurrentLocation == null) return false;
                double dist = Geolocator.distanceBetween(
                    _myCurrentLocation!.latitude, _myCurrentLocation!.longitude,
                    pickup.latitude, pickup.longitude);
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

    // حساب المسافة
    String distanceText = "جاري الحساب..";
    GeoPoint? pickupLoc = data['pickupLocation'];
    if (pickupLoc != null && _myCurrentLocation != null) {
      double dist = Geolocator.distanceBetween(_myCurrentLocation!.latitude, _myCurrentLocation!.longitude, pickupLoc.latitude, pickupLoc.longitude);
      distanceText = "${(dist / 1000).toStringAsFixed(1)} كم من موقعك";
    }

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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      margin: const EdgeInsets.only(bottom: 15),
      child: Column(
        children: [
          ListTile(
            tileColor: canAccept ? Colors.green[50] : Colors.red[50],
            title: Text("صافي ربحك: $driverNet ج.م", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green[800])),
            subtitle: Text(distanceText, style: TextStyle(color: Colors.blueGrey[800])),
            trailing: Chip(label: Text(timeLeft, style: const TextStyle(color: Colors.white)), backgroundColor: Colors.red),
          ),
          Padding(
            padding: const EdgeInsets.all(15),
            child: Column(
              children: [
                _buildRouteRow(Icons.location_on, "من:", data['pickupAddress'] ?? "عنوان المتجر", Colors.orange),
                const SizedBox(height: 8),
                _buildRouteRow(Icons.flag, "إلى:", data['dropoffAddress'] ?? "عنوان العميل", Colors.red),
                const Divider(height: 30),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text("المطلوب تحصيله:", style: TextStyle(fontSize: 11.sp)),
                  Text("$totalPrice ج.م", style: const TextStyle(fontWeight: FontWeight.bold)),
                ]),
                const SizedBox(height: 5),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text("عمولة المنصة:", style: TextStyle(fontSize: 10.sp, color: Colors.grey[600])),
                  Text("$commission ج.م", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange[900])),
                ]),
                const SizedBox(height: 20),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: canAccept ? Colors.green[700] : Colors.grey,
                    minimumSize: Size(100.w, 6.h),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))
                  ),
                  onPressed: canAccept ? () => _acceptOrder(doc.id, commission, data['userId']) : null,
                  child: Text(canAccept ? "قبول الطلب" : "الرصيد مش كفاية.. اشحن دلوقتي",
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
      Icon(icon, color: color, size: 16.sp),
      const SizedBox(width: 10),
      Expanded(child: Text("$label $addr", style: TextStyle(fontSize: 11.sp), maxLines: 1, overflow: TextOverflow.ellipsis)),
    ]);
  }
}

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
  final String vehicleType; // تستقبل مثلاً motorcycleConfig
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

  // دالة التهيئة لطلب الإذن وجلب الموقع
  Future<void> _initSequence() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) setState(() => _isGettingLocation = false);
      return;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
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

  @override
  Widget build(BuildContext context) {
    if (_isGettingLocation) {
      return const Scaffold(body: Center(child: CircularProgressIndicator(color: Colors.orange)));
    }

    // تنظيف المسمى ليتوافق مع الحقل في الطلبات (motorcycle)
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
          // تأمين جلب الرصيد من الحقول الجديدة (معالجة الـ null والـ int)
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

              // الفلترة الجغرافية (15 كم)
              final nearbyOrders = snapshot.data!.docs.where((doc) {
                var data = doc.data() as Map<String, dynamic>;
                GeoPoint? pickup = data['pickupLocation'];
                if (pickup == null || _myCurrentLocation == null) return false;
                double dist = Geolocator.distanceBetween(
                    _myCurrentLocation!.latitude, _myCurrentLocation!.longitude,
                    pickup.latitude, pickup.longitude);
                return dist <= 15000;
              }).toList();

              if (nearbyOrders.isEmpty) {
                return Center(child: Text("لا توجد طلبات $cleanType حالياً"));
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
    
    // التأمين المالي الصارم (قراءة الحقول الجديدة gVyE..)
    double totalPrice = double.tryParse(data['totalPrice']?.toString() ?? '0') ?? 0.0;
    double driverNet = double.tryParse(data['driverNet']?.toString() ?? '0') ?? 0.0;
    double commission = double.tryParse(data['commissionAmount']?.toString() ?? '0') ?? 0.0;

    // حساب العداد التنازلي
    Timestamp? createdAt = data['createdAt'] as Timestamp?;
    String timeLeft = "15:00";
    if (createdAt != null) {
      DateTime expiryTime = createdAt.toDate().add(const Duration(minutes: 15));
      Duration diff = expiryTime.difference(DateTime.now());
      if (diff.isNegative) return const SizedBox.shrink(); // يخفي الطلب لو انتهى
      timeLeft = "${diff.inMinutes}:${(diff.inSeconds % 60).toString().padLeft(2, '0')}";
    }

    bool canAccept = driverBalance >= commission;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      margin: const EdgeInsets.only(bottom: 15),
      child: Column(
        children: [
          ListTile(
            tileColor: canAccept ? Colors.orange[50] : Colors.grey[200],
            title: Text("صافي ربحك: $driverNet ج.م", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green[800])),
            trailing: Chip(label: Text(timeLeft, style: const TextStyle(color: Colors.white)), backgroundColor: Colors.red),
          ),
          Padding(
            padding: const EdgeInsets.all(15),
            child: Column(
              children: [
                Text("من: ${data['pickupAddress'] ?? ''}", maxLines: 1, overflow: TextOverflow.ellipsis),
                const Divider(),
                Text("المطلوب تحصيله: $totalPrice ج.م", style: const TextStyle(fontWeight: FontWeight.bold)),
                Text("عمولة المنصة: $commission ج.م", style: TextStyle(color: Colors.orange[900], fontSize: 10.sp)),
                const SizedBox(height: 15),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: canAccept ? Colors.green : Colors.grey, minimumSize: Size(100.w, 6.h)),
                  onPressed: canAccept ? () => _acceptOrder(doc.id, commission, data['userId']) : null,
                  child: Text(canAccept ? "قبول الطلب" : "الرصيد غير كافٍ"),
                )
              ],
            ),
          )
        ],
      ),
    );
  }

  Future<void> _acceptOrder(String orderId, double commission, String? customerId) async {
    // ... كود الـ Transaction لتحديث الحالة لـ accepted ...
  }
}

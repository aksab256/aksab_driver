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

  // حساب المسافة بين المندوب ونقطة الاستلام
  String _distToPickup(Map<String, dynamic> data) {
    GeoPoint? pickup = data['pickupLocation'];
    if (pickup == null || _myCurrentLocation == null) return "??";
    double dist = Geolocator.distanceBetween(
      _myCurrentLocation!.latitude, _myCurrentLocation!.longitude,
      pickup.latitude, pickup.longitude);
    return (dist / 1000).toStringAsFixed(1);
  }

  // حساب مسافة الطلب نفسه (من الاستلام للتسليم)
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

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Text("رادار الطلبات المتاحة", 
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18.sp, color: Colors.black)),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0.5,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('specialRequests')
            .where('status', isEqualTo: 'pending')
            .where('vehicleConfig', isEqualTo: widget.vehicleType)
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
            return dist <= 15000; // رادار 15 كيلو
          }).toList();

          if (nearbyOrders.isEmpty) {
            return Center(child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.radar, size: 50.sp, color: Colors.grey[300]),
                SizedBox(height: 2.h),
                Text("لا توجد طلبات قريبة منك حالياً", 
                  style: TextStyle(fontSize: 16.sp, color: Colors.grey[600], fontWeight: FontWeight.bold)),
              ],
            ));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(15),
            itemCount: nearbyOrders.length,
            itemBuilder: (context, index) => _buildOrderCard(nearbyOrders[index]),
          );
        },
      ),
    );
  }

  Widget _buildOrderCard(DocumentSnapshot doc) {
    var data = doc.data() as Map<String, dynamic>;
    String tripDist = _tripDistance(data);
    String distToMe = _distToPickup(data);

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(25),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: Offset(0, 5))],
      ),
      child: Column(
        children: [
          // رأس الكارت: السعر ومسافة التوصيل
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.orange[900],
              borderRadius: const BorderRadius.vertical(top: Radius.circular(25)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("قيمة التوصيل", style: TextStyle(color: Colors.white70, fontSize: 12.sp)),
                    Text("${data['price']} ج.م", 
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 22.sp)),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text("مشوار الطلب", style: TextStyle(color: Colors.white70, fontSize: 12.sp)),
                    Text("$tripDist كم", 
                      style: TextStyle(color: Colors.yellowAccent, fontWeight: FontWeight.w900, fontSize: 18.sp)),
                  ],
                ),
              ],
            ),
          ),
          
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                // المسافة الحالية للمندوب
                Row(
                  children: [
                    Icon(Icons.directions_bike, color: Colors.blue[800], size: 20.sp),
                    SizedBox(width: 10),
                    Text("تبعد عن مكان الاستلام: $distToMe كم", 
                      style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.bold, color: Colors.blue[900])),
                  ],
                ),
                const Divider(height: 30, thickness: 1),
                
                _infoRow(Icons.storefront, "من: ${data['pickupAddress'] ?? 'عنوان الاستلام'}", Colors.green[700]!),
                const SizedBox(height: 15),
                _infoRow(Icons.location_on, "إلى: ${data['dropoffAddress'] ?? 'عنوان التسليم'}", Colors.red[700]!),
                
                if (data['details'] != null && data['details'].toString().isNotEmpty) ...[
                  const SizedBox(height: 15),
                  _infoRow(Icons.info_outline, "ملاحظات: ${data['details']}", Colors.grey[700]!),
                ],
                
                const SizedBox(height: 30),
                
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green[800],
                    minimumSize: Size(100.w, 8.h),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    elevation: 5,
                  ),
                  onPressed: () => _acceptOrder(doc.id),
                  child: Text("قبول الطلب فوراً", 
                    style: TextStyle(fontSize: 18.sp, color: Colors.white, fontWeight: FontWeight.w900)),
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
        Icon(icon, size: 22.sp, color: color),
        const SizedBox(width: 12),
        Expanded(
          child: Text(text, 
            style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.bold, color: Colors.black87),
            maxLines: 2, 
            overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }

  Future<void> _acceptOrder(String orderId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    // إظهار مؤشر تحميل
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
        });
      });

      if (!mounted) return;
      Navigator.pop(context); // إغلاق التحميل
      
      // الانتقال لشاشة الطلب النشط
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => ActiveOrderScreen(orderId: orderId)),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // إغلاق التحميل
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: Colors.red, content: Text(e.toString(), style: TextStyle(fontSize: 14.sp)))
      );
    }
  }
}


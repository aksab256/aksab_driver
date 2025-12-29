import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sizer/sizer.dart';
import 'active_order_screen.dart';

class AvailableOrdersScreen extends StatefulWidget {
  const AvailableOrdersScreen({super.key});

  @override
  State<AvailableOrdersScreen> createState() => _AvailableOrdersScreenState();
}

class _AvailableOrdersScreenState extends State<AvailableOrdersScreen> {
  String? _myVehicle;
  Position? _myCurrentLocation;
  bool _isGettingLocation = true;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _handleLocationAndData();
  }

  Future<void> _handleLocationAndData() async {
    bool serviceEnabled;
    LocationPermission permission;
    try {
      serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          setState(() {
            _errorMessage = 'برجاء تفعيل خدمة الموقع (GPS)';
            _isGettingLocation = false;
          });
        }
        return;
      }

      permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) {
            setState(() {
              _errorMessage = 'إذن الموقع مطلوب لرؤية الطلبات';
              _isGettingLocation = false;
            });
          }
          return;
        }
      }

      Position pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      final prefs = await SharedPreferences.getInstance();
      String savedConfig = prefs.getString('user_vehicle_config') ?? 'motorcycleConfig';

      if (mounted) {
        setState(() {
          _myCurrentLocation = pos;
          _myVehicle = savedConfig == 'motorcycleConfig' ? 'motorcycle' : 'jumbo';
          _isGettingLocation = false;
          _errorMessage = '';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'حدث خطأ أثناء جلب موقعك';
          _isGettingLocation = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isGettingLocation) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    if (_errorMessage.isNotEmpty) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.location_off, size: 40.sp, color: Colors.red),
                const SizedBox(height: 20),
                Text(_errorMessage, textAlign: TextAlign.center, style: TextStyle(fontSize: 16.sp)),
                const SizedBox(height: 10),
                ElevatedButton(onPressed: _handleLocationAndData, child: const Text("إعادة المحاولة"))
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Text("الرادار - طلبات حية", 
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18.sp, color: Colors.orange[900])),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0.5,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('specialRequests')
            .where('status', isEqualTo: 'pending')
            .where('vehicleType', isEqualTo: _myVehicle)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

          final docs = snapshot.data!.docs;
          final nearbyOrders = docs.where((doc) {
            var data = doc.data() as Map<String, dynamic>;
            GeoPoint? pickupLocation = data['pickupLocation'];
            if (pickupLocation == null || _myCurrentLocation == null) return true;
            double distanceInMeters = Geolocator.distanceBetween(
                _myCurrentLocation!.latitude, _myCurrentLocation!.longitude,
                pickupLocation.latitude, pickupLocation.longitude);
            return distanceInMeters <= 15000;
          }).toList();

          if (nearbyOrders.isEmpty) {
            return Center(child: Text("لا توجد طلبات تناسبك حالياً", 
              style: TextStyle(fontSize: 16.sp, color: Colors.grey[600])));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(15),
            itemCount: nearbyOrders.length,
            itemBuilder: (context, index) => _buildOrderCard(
                context, nearbyOrders[index].id, nearbyOrders[index].data() as Map<String, dynamic>),
          );
        },
      ),
    );
  }

  Widget _buildOrderCard(BuildContext context, String id, Map<String, dynamic> data) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(25),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 15, offset: const Offset(0, 5))],
      ),
      child: Column(
        children: [
          // شريط علوي للمسافة والسعر
          Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: Colors.orange[900]!.withOpacity(0.05),
              borderRadius: const BorderRadius.only(topLeft: Radius.circular(25), topRight: Radius.circular(25)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.near_me, color: Colors.blue, size: 16.sp),
                    const SizedBox(width: 5),
                    Text("${_calculateDistance(data)} كم", 
                      style: TextStyle(color: Colors.blue[900], fontWeight: FontWeight.w900, fontSize: 16.sp)),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: Colors.orange[900], borderRadius: BorderRadius.circular(15)),
                  child: Text("${data['price']} ج.م", 
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18.sp)),
                ),
              ],
            ),
          ),
          
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                _infoRow(Icons.storefront, "من: ${data['pickupAddress'] ?? 'غير محدد'}", Colors.green),
                const SizedBox(height: 12),
                _infoRow(Icons.location_on, "إلى: ${data['dropoffAddress'] ?? 'غير محدد'}", Colors.red),
                const SizedBox(height: 12),
                _infoRow(Icons.info_outline, "الوصف: ${data['details'] ?? 'بدون وصف'}", Colors.grey[700]!),
                
                const SizedBox(height: 25),
                
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green[800],
                    minimumSize: Size(100.w, 8.h),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    elevation: 5,
                  ),
                  onPressed: () => _acceptOrder(context, id),
                  child: Text("قبول وتوصيل الطلب", 
                    style: TextStyle(fontSize: 18.sp, color: Colors.white, fontWeight: FontWeight.w900)),
                )
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _calculateDistance(Map<String, dynamic> data) {
    GeoPoint? pickup = data['pickupLocation'];
    if (pickup == null || _myCurrentLocation == null) return "??";
    double dist = Geolocator.distanceBetween(_myCurrentLocation!.latitude, _myCurrentLocation!.longitude, pickup.latitude, pickup.longitude);
    return (dist / 1000).toStringAsFixed(1);
  }

  Future<void> _acceptOrder(BuildContext context, String orderId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => const Center(child: CircularProgressIndicator()),
    );

    final orderRef = FirebaseFirestore.instance.collection('specialRequests').doc(orderId);
    try {
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        DocumentSnapshot snapshot = await transaction.get(orderRef);
        if (!snapshot.exists || snapshot.get('status') != 'pending') throw "سبقك مندوب آخر!";

        transaction.update(orderRef, {
          'status': 'accepted',
          'driverId': uid,
          'acceptedAt': FieldValue.serverTimestamp(),
        });
      });

      if (!mounted) return;
      Navigator.pop(context); // إغلاق الـ Loading

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => ActiveOrderScreen(orderId: orderId)),
      );
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: Colors.red, content: Text(e.toString(), style: TextStyle(fontSize: 14.sp)))
        );
      }
    }
  }

  Widget _infoRow(IconData icon, String text, Color color) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20.sp, color: color),
        const SizedBox(width: 12),
        Expanded(
          child: Text(text, 
            style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.bold, color: Colors.black87),
            maxLines: 2, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}


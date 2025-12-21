import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sizer/sizer.dart';
import 'active_order_screen.dart'; // التأكد من وجود ملف التتبع في نفس المجلد

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

  // دالة التعامل مع الموقع الجغرافي وجلب إعدادات المركبة
  Future<void> _handleLocationAndData() async {
    bool serviceEnabled;
    LocationPermission permission;

    try {
      serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          setState(() {
            _errorMessage = 'برجاء تفعيل خدمة الموقع (GPS) في هاتفك';
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
              _errorMessage = 'يجب الموافقة على إذن الموقع لرؤية الطلبات القريبة';
              _isGettingLocation = false;
            });
          }
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          setState(() {
            _errorMessage = 'لقد رفضت إذن الموقع دائماً، برجاء تفعيله من إعدادات الهاتف';
            _isGettingLocation = false;
          });
        }
        return;
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
    if (_isGettingLocation) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_errorMessage.isNotEmpty) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.location_off, size: 50.sp, color: Colors.red),
                const SizedBox(height: 20),
                Text(_errorMessage, textAlign: TextAlign.center, style: TextStyle(fontSize: 14.sp)),
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
        title: Text("الرادار - طلبات تناسبك", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16.sp)),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
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
            return distanceInMeters <= 15000; // نطاق 15 كم
          }).toList();

          if (nearbyOrders.isEmpty) {
            return Center(child: Text("لا توجد طلبات تناسبك حالياً", style: TextStyle(fontSize: 14.sp)));
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
      margin: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10)]),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("المسافة: ${_calculateDistance(data)} كم", style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
                Text("${data['price']} ج.م", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16.sp, color: Colors.orange[900])),
              ],
            ),
            const Divider(),
            _infoRow(Icons.shopping_bag, "التفاصيل: ${data['details'] ?? 'بدون وصف'}"),
            _infoRow(Icons.location_on, "من: ${data['pickupAddress'] ?? 'غير محدد'}"),
            _infoRow(Icons.flag, "إلى: ${data['dropoffAddress'] ?? 'غير محدد'}"),
            const SizedBox(height: 15),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green[800],
                  minimumSize: Size(100.w, 7.h),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
              onPressed: () => _acceptOrder(context, id),
              child: Text("قبول وتوصيل الطلب",
                  style: TextStyle(fontSize: 14.sp, color: Colors.white, fontWeight: FontWeight.bold)),
            )
          ],
        ),
      ),
    );
  }

  String _calculateDistance(Map<String, dynamic> data) {
    GeoPoint? pickup = data['pickupLocation'];
    if (pickup == null || _myCurrentLocation == null) return "??";
    double dist = Geolocator.distanceBetween(_myCurrentLocation!.latitude, _myCurrentLocation!.longitude, pickup.latitude, pickup.longitude);
    return (dist / 1000).toStringAsFixed(1);
  }

  // دالة قبول الطلب والانتقال المؤمن
  Future<void> _acceptOrder(BuildContext context, String orderId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    // 1. إظهار مؤشر التحميل
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => const Center(child: CircularProgressIndicator()),
    );

    final orderRef = FirebaseFirestore.instance.collection('specialRequests').doc(orderId);
    try {
      // 2. تحديث الحالة في Firestore (Transaction)
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        DocumentSnapshot snapshot = await transaction.get(orderRef);
        if (!snapshot.exists) throw "الطلب غير موجود!";
        if (snapshot.get('status') != 'pending') throw "سبقك مندوب آخر!";

        transaction.update(orderRef, {
          'status': 'accepted',
          'driverId': uid,
          'acceptedAt': FieldValue.serverTimestamp(),
        });
      });

      // 3. إغلاق الـ Loading وتأمين الـ Navigator
      if (!context.mounted) return;
      Navigator.pop(context); // إغلاق الـ Dialog

      // 4. ✅ الانتقال الفوري لصفحة الخريطة (Replacement لعدم الرجوع للرادار)
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => ActiveOrderScreen(orderId: orderId)),
      );

    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context); // إغلاق الـ Loading في حالة الخطأ
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(backgroundColor: Colors.red, content: Text(e.toString()))
        );
      }
    }
  }

  Widget _infoRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 18.sp, color: Colors.orange[800]),
          const SizedBox(width: 10),
          Expanded(child: Text(text, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }
}

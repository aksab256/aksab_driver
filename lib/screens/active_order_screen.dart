import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:sizer/sizer.dart';

class ActiveOrderScreen extends StatefulWidget {
  final String orderId;
  const ActiveOrderScreen({super.key, required this.orderId});

  @override
  State<ActiveOrderScreen> createState() => _ActiveOrderScreenState();
}

class _ActiveOrderScreenState extends State<ActiveOrderScreen> {
  LatLng? _currentLocation;
  final MapController _mapController = MapController();

  @override
  void initState() {
    super.initState();
    _startLiveTracking();
  }

  // 1. تتبع موقع المندوب وتحديث الخريطة و Firestore
  void _startLiveTracking() {
    Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 10),
    ).listen((Position position) {
      if (mounted) {
        setState(() {
          _currentLocation = LatLng(position.latitude, position.longitude);
        });
        // تحديث الموقع في Firestore ليراه العميل
        _updateDriverLocationInFirestore(position);
      }
    });
  }

  void _updateDriverLocationInFirestore(Position pos) {
    FirebaseFirestore.instance.collection('freeDrivers').doc('DRIVER_ID_HERE').update({
      'location': GeoPoint(pos.latitude, pos.longitude),
      'lastSeen': FieldValue.serverTimestamp(),
    });
  }

  // 2. دالة لفتح خرائط جوجل الخارجية للملاحة
  Future<void> _openExternalMap(GeoPoint point) async {
    final url = 'https://www.google.com/maps/search/?api=1&query=${point.latitude},${point.longitude}';
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("تتبع الطلب النشط"),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('specialRequests').doc(widget.orderId).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

          var data = snapshot.data!.data() as Map<String, dynamic>;
          GeoPoint pickup = data['pickupLocation'];
          GeoPoint dropoff = data['dropoffLocation'];
          String status = data['status'];

          return Column(
            children: [
              // قسم الخريطة (CartoDB)
              Expanded(
                flex: 3,
                child: FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _currentLocation ?? LatLng(pickup.latitude, pickup.longitude),
                    initialZoom: 14.0,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png',
                      subdomains: const ['a', 'b', 'c', 'd'],
                    ),
                    MarkerLayer(
                      markers: [
                        // ماركر المندوب (أنت)
                        if (_currentLocation != null)
                          Marker(
                            point: _currentLocation!,
                            child: Icon(Icons.delivery_dining, color: Colors.blue, size: 30.sp),
                          ),
                        // ماركر المتجر (الاستلام)
                        Marker(
                          point: LatLng(pickup.latitude, pickup.longitude),
                          child: Icon(Icons.store, color: Colors.orange[900], size: 30.sp),
                        ),
                        // ماركر العميل (التسليم)
                        Marker(
                          point: LatLng(dropoff.latitude, dropoff.longitude),
                          child: Icon(Icons.location_on, color: Colors.red, size: 30.sp),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // لوحة التحكم السفلية
              _buildControlPanel(status, pickup, dropoff, data['pickupAddress'], data['dropoffAddress']),
            ],
          );
        },
      ),
    );
  }

  Widget _buildControlPanel(String status, GeoPoint pickup, GeoPoint dropoff, String? pAddr, String? dAddr) {
    bool isPickedUp = status == 'picked_up';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _locationInfo(
            isPickedUp ? "وجهة التسليم (العميل)" : "وجهة الاستلام (المتجر)",
            isPickedUp ? dAddr : pAddr,
            () => _openExternalMap(isPickedUp ? dropoff : pickup),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: isPickedUp ? Colors.green : Colors.orange[900],
              minimumSize: Size(double.infinity, 7.h),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            ),
            onPressed: () => _updateStatus(status),
            child: Text(
              isPickedUp ? "تم تسليم الطلب للعميل ✅" : "وصلت للمتجر واستلمت الطلب 📦",
              style: TextStyle(color: Colors.white, fontSize: 13.sp, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _locationInfo(String title, String? address, VoidCallback onNav) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(color: Colors.grey, fontSize: 10.sp)),
              Text(address ?? "جاري التحميل...", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.sp)),
            ],
          ),
        ),
        IconButton(
          onPressed: onNav,
          icon: Icon(Icons.directions, color: Colors.blue, size: 25.sp),
          tooltip: "فتح الملاحة الخارجية",
        )
      ],
    );
  }

  void _updateStatus(String currentStatus) async {
    String nextStatus = currentStatus == 'accepted' ? 'picked_up' : 'delivered';
    await FirebaseFirestore.instance.collection('specialRequests').doc(widget.orderId).update({
      'status': nextStatus,
      if (nextStatus == 'delivered') 'completedAt': FieldValue.serverTimestamp(),
    });

    if (nextStatus == 'delivered') {
      Navigator.pop(context); // العودة بعد الإكمال
    }
  }
}

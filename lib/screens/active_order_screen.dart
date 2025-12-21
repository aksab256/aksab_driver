import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:sizer/sizer.dart';

// ✅ استيراد الملف الصحيح لضمان الانتقال السليم
import 'available_orders_screen.dart'; 

class ActiveOrderScreen extends StatefulWidget {
  final String orderId;
  const ActiveOrderScreen({super.key, required this.orderId});

  @override
  State<ActiveOrderScreen> createState() => _ActiveOrderScreenState();
}

class _ActiveOrderScreenState extends State<ActiveOrderScreen> {
  LatLng? _currentLocation;
  List<LatLng> _routePoints = [];
  final MapController _mapController = MapController();
  final String? _uid = FirebaseAuth.instance.currentUser?.uid;
  final String _mapboxToken = 'pk.eyJ1IjoiYW1yc2hpcGwiLCJhIjoiY21lajRweGdjMDB0eDJsczdiemdzdXV6biJ9.E--si9vOB93NGcAq7uVgGw';

  @override
  void initState() {
    super.initState();
    _startLiveTracking();
  }

  Future<void> _updateRoute(LatLng destination) async {
    if (_currentLocation == null) return;
    final url = 'https://api.mapbox.com/directions/v5/mapbox/driving/${_currentLocation!.longitude},${_currentLocation!.latitude};${destination.longitude},${destination.latitude}?overview=full&geometries=geojson&access_token=$_mapboxToken';
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List coords = data['routes'][0]['geometry']['coordinates'];
        if (mounted) setState(() => _routePoints = coords.map((c) => LatLng(c[1], c[0])).toList());
      }
    } catch (e) { debugPrint("Route Error: $e"); }
  }

  void _startLiveTracking() async {
    Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
    if (mounted) setState(() => _currentLocation = LatLng(position.latitude, position.longitude));
    Geolocator.getPositionStream(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 10)).listen((Position pos) {
      if (mounted) {
        setState(() => _currentLocation = LatLng(pos.latitude, pos.longitude));
        _updateDriverLocationInFirestore(pos);
      }
    });
  }

  void _updateDriverLocationInFirestore(Position pos) {
    if (_uid != null) {
      FirebaseFirestore.instance.collection('freeDrivers').doc(_uid).update({
        'location': GeoPoint(pos.latitude, pos.longitude),
        'lastSeen': FieldValue.serverTimestamp(),
      });
    }
  }

  Future<void> _openExternalMap(GeoPoint point) async {
    final uri = Uri.parse("google.navigation:q=${point.latitude},${point.longitude}");
    if (await canLaunchUrl(uri)) { await launchUrl(uri, mode: LaunchMode.externalApplication); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text("تتبع المسار المباشر", style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white.withOpacity(0.95),
        elevation: 4,
        centerTitle: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(bottom: Radius.circular(25))),
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('specialRequests').doc(widget.orderId).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData || !snapshot.data!.exists) return const Center(child: CircularProgressIndicator());
          var data = snapshot.data!.data() as Map<String, dynamic>;
          GeoPoint pickup = data['pickupLocation'];
          GeoPoint dropoff = data['dropoffLocation'];
          String status = data['status'];
          LatLng target = status == 'accepted' ? LatLng(pickup.latitude, pickup.longitude) : LatLng(dropoff.latitude, dropoff.longitude);

          _updateRoute(target);

          return Stack(
            children: [
              FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: _currentLocation ?? target,
                  initialZoom: 14.0,
                ),
                children: [
                  TileLayer(
                    urlTemplate: 'https://api.mapbox.com/styles/v1/mapbox/streets-v12/tiles/{z}/{x}/{y}?access_token={accessToken}',
                    additionalOptions: {'accessToken': _mapboxToken},
                  ),
                  if (_routePoints.isNotEmpty)
                    PolylineLayer(polylines: [
                      Polyline(points: _routePoints, color: Colors.blue, strokeWidth: 6, borderColor: Colors.white, borderStrokeWidth: 2.0),
                    ]),
                  MarkerLayer(
                    markers: [
                      if (_currentLocation != null)
                        Marker(point: _currentLocation!, child: Icon(Icons.delivery_dining, color: Colors.blue, size: 35.sp)),
                      Marker(point: LatLng(pickup.latitude, pickup.longitude), child: Icon(Icons.store, color: Colors.orange[900], size: 32.sp)),
                      Marker(point: LatLng(dropoff.latitude, dropoff.longitude), child: Icon(Icons.person_pin_circle, color: Colors.red, size: 32.sp)),
                    ],
                  ),
                ],
              ),
              Positioned(
                bottom: 0, left: 0, right: 0, 
                child: SafeArea(child: _build3DControlPanel(status, pickup, dropoff, data['pickupAddress'], data['dropoffAddress']))
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _build3DControlPanel(String status, GeoPoint pickup, GeoPoint dropoff, String? pAddr, String? dAddr) {
    bool isPickedUp = status == 'picked_up';
    return Container(
      margin: EdgeInsets.all(15.sp),
      padding: EdgeInsets.all(20.sp),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 15, offset: const Offset(0, -5))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.location_on, color: Colors.blue[900], size: 30.sp),
              SizedBox(width: 10.sp),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(isPickedUp ? "وجهة التسليم" : "نقطة الاستلام", style: TextStyle(color: Colors.grey[700], fontSize: 14.sp)),
                    Text(isPickedUp ? dAddr ?? "عنوان العميل" : pAddr ?? "عنوان المتجر", 
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17.sp), maxLines: 2),
                  ],
                ),
              ),
              ElevatedButton.icon(
                onPressed: () => _openExternalMap(isPickedUp ? dropoff : pickup),
                icon: Icon(Icons.directions, size: 20.sp),
                label: Text("توجيه", style: TextStyle(fontSize: 12.sp)),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.black, foregroundColor: Colors.white),
              )
            ],
          ),
          SizedBox(height: 20.sp),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: isPickedUp ? Colors.green[700] : Colors.orange[900],
              minimumSize: Size(double.infinity, 8.h),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              elevation: 8,
            ),
            onPressed: () => _updateStatus(status),
            child: Text(isPickedUp ? "تم التسليم بنجاح ✅" : "استلمت من المتجر وبدء الملاحة 📦",
              style: TextStyle(color: Colors.white, fontSize: 18.sp, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _updateStatus(String currentStatus) async {
    String nextStatus = currentStatus == 'accepted' ? 'picked_up' : 'delivered';
    try {
      await FirebaseFirestore.instance.collection('specialRequests').doc(widget.orderId).update({
        'status': nextStatus,
        if (nextStatus == 'delivered') 'completedAt': FieldValue.serverTimestamp(),
      });

      if (nextStatus == 'delivered' && mounted) {
        // ✅ استخدام نفس طريقة الانتقال في تطبيقك (Replacement) للرجوع للرادار
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const AvailableOrdersScreen()),
        );
      }
    } catch (e) {
      debugPrint("Update Error: $e");
    }
  }
}


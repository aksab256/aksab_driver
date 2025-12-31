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
import 'package:shared_preferences/shared_preferences.dart';
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
  LatLng? _lastRouteUpdateLocation;
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
    if (_lastRouteUpdateLocation != null) {
      double distance = Geolocator.distanceBetween(
          _currentLocation!.latitude, _currentLocation!.longitude,
          _lastRouteUpdateLocation!.latitude, _lastRouteUpdateLocation!.longitude
      );
      if (distance < 20) return;
    }

    final url = 'https://api.mapbox.com/directions/v5/mapbox/driving/${_currentLocation!.longitude},${_currentLocation!.latitude};${destination.longitude},${destination.latitude}?overview=full&geometries=geojson&access_token=$_mapboxToken';
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List coords = data['routes'][0]['geometry']['coordinates'];
        if (mounted) {
          setState(() {
            _routePoints = coords.map((c) => LatLng(c[1], c[0])).toList();
            _lastRouteUpdateLocation = _currentLocation;
          });
        }
      }
    } catch (e) { debugPrint("Mapbox Route Error: $e"); }
  }

  void _startLiveTracking() async {
    Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
    if (mounted) setState(() => _currentLocation = LatLng(position.latitude, position.longitude));

    Geolocator.getPositionStream(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 10)
    ).listen((Position pos) {
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

  Future<void> _launchGoogleMaps(GeoPoint point) async {
    final url = 'google.navigation:q=${point.latitude},${point.longitude}';
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text("تتبع المسار المباشر", style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white.withOpacity(0.9),
        elevation: 4,
        centerTitle: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(bottom: Radius.circular(25))),
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('specialRequests').doc(widget.orderId).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData || !snapshot.data!.exists) return const Center(child: CircularProgressIndicator());

          var data = snapshot.data!.data() as Map<String, dynamic>;
          String status = data['status'];
          GeoPoint pickup = data['pickupLocation'];
          GeoPoint dropoff = data['dropoffLocation'];

          GeoPoint targetGeo = (status == 'accepted') ? pickup : dropoff;
          LatLng targetLatLng = LatLng(targetGeo.latitude, targetGeo.longitude);

          _updateRoute(targetLatLng);

          return Stack(
            children: [
              FlutterMap(
                mapController: _mapController,
                options: MapOptions(initialCenter: _currentLocation ?? targetLatLng, initialZoom: 14.5),
                children: [
                  TileLayer(
                    urlTemplate: 'https://api.mapbox.com/styles/v1/mapbox/streets-v12/tiles/{z}/{x}/{y}?access_token={accessToken}',
                    additionalOptions: {'accessToken': _mapboxToken},
                  ),
                  if (_routePoints.isNotEmpty)
                    PolylineLayer(polylines: [
                      Polyline(points: _routePoints, color: Colors.blueAccent, strokeWidth: 6, borderColor: Colors.white, borderStrokeWidth: 2),
                    ]),
                  MarkerLayer(markers: [
                    if (_currentLocation != null)
                      Marker(point: _currentLocation!, child: Icon(Icons.delivery_dining, color: Colors.blue[900], size: 22.sp)),
                    Marker(point: LatLng(pickup.latitude, pickup.longitude), child: Icon(Icons.store, color: Colors.orange[900], size: 18.sp)),
                    Marker(point: LatLng(dropoff.latitude, dropoff.longitude), child: Icon(Icons.person_pin_circle, color: Colors.red, size: 18.sp)),
                  ]),
                ],
              ),
              Positioned(
                bottom: 0, left: 0, right: 0,
                child: SafeArea(
                  child: Container(
                    margin: EdgeInsets.all(12.sp),
                    padding: EdgeInsets.all(15.sp),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(25),
                      boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 15, offset: const Offset(0, -5))],
                    ),
                    child: _buildControlUI(status, data, targetGeo),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildControlUI(String status, Map<String, dynamic> data, GeoPoint targetLoc) {
    bool isAtPickup = status == 'accepted';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            IconButton.filled(
              onPressed: () => _launchGoogleMaps(targetLoc),
              icon: Icon(Icons.directions, size: 20.sp),
              style: IconButton.styleFrom(backgroundColor: Colors.black),
            ),
            SizedBox(width: 10.sp),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(isAtPickup ? "الاستلام من المتجر" : "التوصيل للعميل", style: TextStyle(color: Colors.grey[700], fontSize: 11.sp)),
                  Text(isAtPickup ? data['pickupAddress'] ?? "عنوان المتجر" : data['dropoffAddress'] ?? "عنوان العميل",
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15.sp), maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            IconButton.filled(
              onPressed: () => launchUrl(Uri.parse("tel:${data['userPhone'] ?? ''}")),
              icon: Icon(Icons.phone, size: 20.sp),
              style: IconButton.styleFrom(backgroundColor: Colors.green[700]),
            )
          ],
        ),
        SizedBox(height: 15.sp),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: isAtPickup ? Colors.orange[900] : Colors.green[800],
            minimumSize: Size(double.infinity, 8.h),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            elevation: 8,
          ),
          onPressed: () => isAtPickup ? _showVerificationDialog(data['verificationCode']) : _completeOrder(),
          child: Text(isAtPickup ? "تأكيد كود الاستلام 📦" : "تم التسليم بنجاح ✅",
              style: TextStyle(color: Colors.white, fontSize: 17.sp, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  void _showVerificationDialog(String? correctCode) {
    final TextEditingController _codeController = TextEditingController();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text("أدخل كود الاستلام", textAlign: TextAlign.center, style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: _codeController,
          keyboardType: TextInputType.text,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 22.sp, fontWeight: FontWeight.bold, letterSpacing: 5),
          decoration: const InputDecoration(hintText: "كود المتجر"),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text("إلغاء", style: TextStyle(fontSize: 14.sp))),
          ElevatedButton(
            onPressed: () {
              if (_codeController.text.trim() == correctCode?.trim()) {
                Navigator.pop(context);
                _updateStatus('picked_up');
              } else {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("الكود غير صحيح!")));
              }
            },
            child: Text("تأكيد", style: TextStyle(fontSize: 14.sp)),
          ),
        ],
      ),
    );
  }

  void _updateStatus(String nextStatus) async {
    await FirebaseFirestore.instance.collection('specialRequests').doc(widget.orderId).update({'status': nextStatus});
  }

  // الدالة النهائية والمحدثة للخصم المالي وإتمام الطلب
  void _completeOrder() async {
    // 1. إظهار مؤشر التحميل
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => const Center(child: CircularProgressIndicator(color: Colors.green)),
    );

    final orderRef = FirebaseFirestore.instance.collection('specialRequests').doc(widget.orderId);
    final driverId = FirebaseAuth.instance.currentUser?.uid;

    try {
      double savedCommission = 0;

      // 2. استخدام Transaction لضمان الدقة المالية
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        DocumentSnapshot orderSnap = await transaction.get(orderRef);
        
        if (!orderSnap.exists) throw "الطلب غير موجود!";
        
        // جلب العمولة المحجوزة من مستند الطلب
        savedCommission = (orderSnap.get('commissionAmount') ?? 0.0).toDouble();

        // تحديث حالة الطلب
        transaction.update(orderRef, {
          'status': 'delivered',
          'completedAt': FieldValue.serverTimestamp(),
        });

        // الخصم من محفظة المندوب
        if (driverId != null && savedCommission > 0) {
          final driverRef = FirebaseFirestore.instance.collection('freeDrivers').doc(driverId);
          transaction.update(driverRef, {
            'walletBalance': FieldValue.increment(-savedCommission),
          });
        }
      });

      if (mounted) {
        Navigator.pop(context); // إغلاق التحميل

        final prefs = await SharedPreferences.getInstance();
        String vType = prefs.getString('user_vehicle_config') ?? 'motorcycleConfig';

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.green,
            content: Text("تم التسليم بنجاح! تم خصم عمولة: ${savedCommission.toStringAsFixed(1)} ج.م"),
          ),
        );

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => AvailableOrdersScreen(vehicleType: vType))
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // إغلاق التحميل
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: Colors.red, content: Text("فشل في إتمام الطلب: $e")),
        );
      }
    }
  }
}


import 'dart:async';
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
  StreamSubscription<Position>? _positionStream; // لإدارة غلق التتبع
  
  final MapController _mapController = MapController();
  final String? _uid = FirebaseAuth.instance.currentUser?.uid;
  final String _mapboxToken = 'pk.eyJ1IjoiYW1yc2hpcGwiLCJhIjoiY21lajRweGdjMDB0eDJsczdiemdzdXV6biJ9.E--si9vOB93NGcAq7uVgGw';

  @override
  void initState() {
    super.initState();
    _initInitialLocation();
  }

  @override
  void dispose() {
    _positionStream?.cancel(); // غلق التتبع فور الخروج من الشاشة
    super.dispose();
  }

  // جلب الموقع لأول مرة ثم بدء التتبع الذكي
  Future<void> _initInitialLocation() async {
    Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
    if (mounted) {
      setState(() => _currentLocation = LatLng(position.latitude, position.longitude));
      // البدء في مراقبة الطلب لجلب إحداثيات الهدف (المتجر أو العميل)
      _setupDynamicTracking();
    }
  }

  void _setupDynamicTracking() {
    // مراقبة بيانات الطلب لحظياً لتحديد الهدف (pickup أو dropoff)
    FirebaseFirestore.instance.collection('specialRequests').doc(widget.orderId).snapshots().listen((orderSnap) {
      if (!orderSnap.exists || !mounted) return;
      var data = orderSnap.data() as Map<String, dynamic>;
      String status = data['status'];
      GeoPoint targetGeo = (status == 'accepted') ? data['pickupLocation'] : data['dropoffLocation'];
      LatLng targetLatLng = LatLng(targetGeo.latitude, targetGeo.longitude);

      // بدء أو تحديث التتبع بناءً على الهدف الحالي
      _startSmartLiveTracking(targetLatLng);
    });
  }

  void _startSmartLiveTracking(LatLng target) {
    _positionStream?.cancel(); // إعادة ضبط الـ Stream

    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0, // سنفلتر يدوياً بالذكاء المطلوب
      ),
    ).listen((Position pos) {
      if (!mounted) return;

      double distanceToTarget = Geolocator.distanceBetween(
        pos.latitude, pos.longitude,
        target.latitude, target.longitude,
      );

      // --- 🧠 منطق التحديث الذكي ---
      double dynamicFilter;
      if (distanceToTarget > 2000) {
        dynamicFilter = 50.0; // بعيد: تحديث كل 50 متر لتوفير البيانات
      } else if (distanceToTarget > 500) {
        dynamicFilter = 20.0; // قرب: تحديث كل 20 متر
      } else {
        dynamicFilter = 5.0;  // قريب جداً: تحديث كل 5 متر لسلاسة الحركة عند العميل
      }

      // حساب المسافة المقطوعة عن آخر تحديث
      double travelSinceLastUpdate = _currentLocation != null
          ? Geolocator.distanceBetween(_currentLocation!.latitude, _currentLocation!.longitude, pos.latitude, pos.longitude)
          : dynamicFilter + 1;

      if (travelSinceLastUpdate >= dynamicFilter) {
        if (mounted) {
          setState(() => _currentLocation = LatLng(pos.latitude, pos.longitude));
          _updateDriverLocationInFirestore(pos);
          _updateRoute(target); // تحديث خط السير على الخريطة
        }
      }
    });
  }

  void _updateDriverLocationInFirestore(Position pos) {
    if (_uid != null) {
      FirebaseFirestore.instance.collection('freeDrivers').doc(_uid).update({
        'location': GeoPoint(pos.latitude, pos.longitude),
        'lastSeen': FieldValue.serverTimestamp()
      });
    }
  }

  // --- 🛠️ الدوال الأصلية المحفوظة بالكامل ---

  Future<void> _driverCancelOrder() async {
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("اعتذار عن الرحلة", textAlign: TextAlign.right),
        content: const Text("هل أنت متأكد من الاعتذار عن هذه الرحلة؟ سيتم إخطار العميل وإعادة الطلب للرادار.", textAlign: TextAlign.right),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("تراجع")),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("تأكيد الاعتذار", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      try {
        await FirebaseFirestore.instance.collection('specialRequests').doc(widget.orderId).update({
          'status': 'driver_cancelled_reseeking',
          'lastDriverId': _uid,
          'driverId': FieldValue.delete(),
          'driverName': FieldValue.delete(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        if (mounted) {
          final prefs = await SharedPreferences.getInstance();
          String vType = prefs.getString('user_vehicle_config') ?? 'motorcycleConfig';
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => AvailableOrdersScreen(vehicleType: vType)));
        }
      } catch (e) { debugPrint("Driver Cancel Error: $e"); }
    }
  }

  Future<void> _updateRoute(LatLng destination) async {
    if (_currentLocation == null) return;
    final url = 'https://api.mapbox.com/directions/v5/mapbox/driving/${_currentLocation!.longitude},${_currentLocation!.latitude};${destination.longitude},${destination.latitude}?overview=full&geometries=geojson&access_token=$_mapboxToken';
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List coords = data['routes'][0]['geometry']['coordinates'];
        if (mounted) { setState(() { _routePoints = coords.map((c) => LatLng(c[1], c[0])).toList(); }); }
      }
    } catch (e) { debugPrint("Mapbox Route Error: $e"); }
  }

  Future<void> _launchGoogleMaps(GeoPoint point) async {
    final url = 'google.navigation:q=${point.latitude},${point.longitude}';
    if (await canLaunchUrl(Uri.parse(url))) { await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication); }
  }

  Future<void> _notifyUserOrderDelivered(String targetUserId) async {
    const String lambdaUrl = 'https://9ayce138ig.execute-api.us-east-1.amazonaws.com/V1/nofiction';
    try {
      var endpointSnap = await FirebaseFirestore.instance.collection('UserEndpoints').doc(targetUserId).get();
      if (!endpointSnap.exists || endpointSnap.data()?['endpointArn'] == null) return;
      String arn = endpointSnap.data()!['endpointArn'];
      final payload = {"userId": arn, "title": "أكسب: تم التسليم بنجاح! ✅", "message": "يسعدنا دائماً خدمتك. فضلاً، قم بتقييم المندوب.", "orderId": widget.orderId};
      await http.post(Uri.parse(lambdaUrl), headers: {"Content-Type": "application/json"}, body: json.encode(payload));
    } catch (e) { debugPrint("❌ Notification Error: $e"); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text("تتبع المسار المباشر", style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white.withOpacity(0.9),
        elevation: 4, centerTitle: true,
        actions: [
          TextButton.icon(
            onPressed: _driverCancelOrder,
            icon: Icon(Icons.cancel, color: Colors.red[900], size: 16.sp),
            label: Text("اعتذار", style: TextStyle(color: Colors.red[900], fontWeight: FontWeight.bold, fontSize: 12.sp)),
          )
        ],
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(bottom: Radius.circular(25))),
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('specialRequests').doc(widget.orderId).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData || !snapshot.data!.exists) return const Center(child: CircularProgressIndicator());
          var data = snapshot.data!.data() as Map<String, dynamic>;
          String status = data['status'];

          if (status.contains('cancelled') && status != 'driver_cancelled_reseeking') {
            Future.microtask(() async {
              if (mounted) {
                final prefs = await SharedPreferences.getInstance();
                String vType = prefs.getString('user_vehicle_config') ?? 'motorcycleConfig';
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("⚠️ قام العميل بإلغاء الطلب"), backgroundColor: Colors.redAccent));
                Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => AvailableOrdersScreen(vehicleType: vType)));
              }
            });
            return const Center(child: Text("تم إلغاء الطلب..."));
          }

          GeoPoint pickup = data['pickupLocation'];
          GeoPoint dropoff = data['dropoffLocation'];
          GeoPoint targetGeo = (status == 'accepted') ? pickup : dropoff;

          return Stack(
            children: [
              FlutterMap(
                mapController: _mapController,
                options: MapOptions(initialCenter: _currentLocation ?? LatLng(targetGeo.latitude, targetGeo.longitude), initialZoom: 14.5),
                children: [
                  TileLayer(urlTemplate: 'https://api.mapbox.com/styles/v1/mapbox/streets-v12/tiles/{z}/{x}/{y}?access_token={accessToken}', additionalOptions: {'accessToken': _mapboxToken}),
                  if (_routePoints.isNotEmpty) PolylineLayer(polylines: [Polyline(points: _routePoints, color: Colors.blueAccent, strokeWidth: 6, borderColor: Colors.white, borderStrokeWidth: 2)]),
                  MarkerLayer(markers: [
                    if (_currentLocation != null) Marker(point: _currentLocation!, child: Icon(Icons.delivery_dining, color: Colors.blue[900], size: 22.sp)),
                    Marker(point: LatLng(pickup.latitude, pickup.longitude), child: Icon(Icons.store, color: Colors.orange[900], size: 18.sp)),
                    Marker(point: LatLng(dropoff.latitude, dropoff.longitude), child: Icon(Icons.person_pin_circle, color: Colors.red, size: 18.sp)),
                  ]),
                ],
              ),
              Positioned(
                bottom: 0, left: 0, right: 0,
                child: SafeArea(
                  child: Container(
                    margin: EdgeInsets.all(12.sp), padding: EdgeInsets.all(15.sp),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(25), boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 15, offset: const Offset(0, -5))]),
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
            IconButton.filled(onPressed: () => _launchGoogleMaps(targetLoc), icon: Icon(Icons.directions, size: 20.sp), style: IconButton.styleFrom(backgroundColor: Colors.black)),
            SizedBox(width: 10.sp),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(isAtPickup ? "الاستلام من المتجر" : "التوصيل للعميل", style: TextStyle(color: Colors.grey[700], fontSize: 11.sp)),
              Text(isAtPickup ? data['pickupAddress'] ?? "عنوان المتجر" : data['dropoffAddress'] ?? "عنوان العميل", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15.sp), maxLines: 1, overflow: TextOverflow.ellipsis),
            ])),
            IconButton.filled(onPressed: () => launchUrl(Uri.parse("tel:${data['userPhone'] ?? ''}")), icon: Icon(Icons.phone, size: 20.sp), style: IconButton.styleFrom(backgroundColor: Colors.green[700]))
          ],
        ),
        SizedBox(height: 15.sp),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: isAtPickup ? Colors.orange[900] : Colors.green[800], minimumSize: Size(double.infinity, 8.h), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)), elevation: 8),
          onPressed: () => isAtPickup ? _showVerificationDialog(data['verificationCode']) : _completeOrder(),
          child: Text(isAtPickup ? "تأكيد كود الاستلام 📦" : "تم التسليم بنجاح ✅", style: TextStyle(color: Colors.white, fontSize: 17.sp, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  void _showVerificationDialog(String? correctCode) {
    final TextEditingController _codeController = TextEditingController();
    showDialog(
      context: context, barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text("أدخل كود الاستلام", textAlign: TextAlign.center, style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold)),
        content: TextField(controller: _codeController, textAlign: TextAlign.center, style: TextStyle(fontSize: 22.sp, fontWeight: FontWeight.bold, letterSpacing: 5), decoration: const InputDecoration(hintText: "كود المتجر")),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text("إلغاء", style: TextStyle(fontSize: 14.sp))),
          ElevatedButton(onPressed: () { if (_codeController.text.trim() == correctCode?.trim()) { Navigator.pop(context); _updateStatus('picked_up'); } else { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("الكود غير صحيح!"))); } }, child: Text("تأكيد", style: TextStyle(fontSize: 14.sp))),
        ],
      ),
    );
  }

  void _updateStatus(String nextStatus) async { await FirebaseFirestore.instance.collection('specialRequests').doc(widget.orderId).update({'status': nextStatus}); }

  void _completeOrder() async {
    showDialog(context: context, barrierDismissible: false, builder: (c) => const Center(child: CircularProgressIndicator(color: Colors.green)));
    final orderRef = FirebaseFirestore.instance.collection('specialRequests').doc(widget.orderId);
    final driverId = FirebaseAuth.instance.currentUser?.uid;
    try {
      double savedCommission = 0; String? customerUserId;
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        DocumentSnapshot orderSnap = await transaction.get(orderRef);
        if (!orderSnap.exists) throw "الطلب غير موجود!";
        savedCommission = (orderSnap.get('commissionAmount') ?? 0.0).toDouble();
        customerUserId = orderSnap.get('userId');
        transaction.update(orderRef, {'status': 'delivered', 'completedAt': FieldValue.serverTimestamp()});
        if (driverId != null && savedCommission > 0) {
          final driverRef = FirebaseFirestore.instance.collection('freeDrivers').doc(driverId);
          transaction.update(driverRef, {'walletBalance': FieldValue.increment(-savedCommission)});
        }
      });
      if (customerUserId != null) _notifyUserOrderDelivered(customerUserId!);
      if (mounted) { Navigator.pop(context); final prefs = await SharedPreferences.getInstance(); String vType = prefs.getString('user_vehicle_config') ?? 'motorcycleConfig'; ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: Colors.green, content: Text("تم التسليم! تم خصم عمولة: ${savedCommission.toStringAsFixed(1)} ج.م"))); Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => AvailableOrdersScreen(vehicleType: vType))); }
    } catch (e) { if (mounted) { Navigator.pop(context); ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: Colors.red, content: Text("فشل: $e"))); } }
  }
}

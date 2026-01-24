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
import 'package:flutter_background_service/flutter_background_service.dart';
import 'available_orders_screen.dart';
import 'location_service_handler.dart'; 

class ActiveOrderScreen extends StatefulWidget {
  final String orderId;
  const ActiveOrderScreen({super.key, required this.orderId});

  @override
  State<ActiveOrderScreen> createState() => _ActiveOrderScreenState();
}

class _ActiveOrderScreenState extends State<ActiveOrderScreen> {
  LatLng? _currentLocation;
  List<LatLng> _routePoints = [];
  StreamSubscription<Position>? _positionStream;
  
  final MapController _mapController = MapController();
  final String? _uid = FirebaseAuth.instance.currentUser?.uid;
  final String _mapboxToken = 'pk.eyJ1IjoiYW1yc2hpcGwiLCJhIjoiY21lajRweGdjMDB0eDJsczdiemdzdXV6biJ9.E--si9vOB93NGcAq7uVgGw';

  @override
  void initState() {
    super.initState();
    _startBackgroundTracking(); 
    _initInitialLocation();
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    super.dispose();
  }

  // ✅ حساب المسافة الذكية المتبقية
  double _getSmartDistance(Map<String, dynamic> data, String status) {
    if (_currentLocation == null) return 0.0;

    GeoPoint pickup = data['pickupLocation'];
    GeoPoint dropoff = data['dropoffLocation'];

    if (status == 'accepted') {
      // (المندوب -> المحل) + (المحل -> العميل)
      double d1 = Geolocator.distanceBetween(_currentLocation!.latitude, _currentLocation!.longitude, pickup.latitude, pickup.longitude);
      double d2 = Geolocator.distanceBetween(pickup.latitude, pickup.longitude, dropoff.latitude, dropoff.longitude);
      return (d1 + d2) / 1000;
    } else {
      // (المندوب حالياً -> العميل)
      double dRemaining = Geolocator.distanceBetween(_currentLocation!.latitude, _currentLocation!.longitude, dropoff.latitude, dropoff.longitude);
      return dRemaining / 1000;
    }
  }

  Future<void> _startBackgroundTracking() async {
    if (_uid != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('driver_uid', _uid!);
      final service = FlutterBackgroundService();
      await service.configure(
        androidConfiguration: AndroidConfiguration(
          onStart: onStart, autoStart: true, isForegroundMode: true,
          notificationChannelId: 'aksab_tracking_channel',
          initialNotificationTitle: 'أكسب: رحلة قيد التنفيذ',
          initialNotificationContent: 'جاري مشاركة الموقع لضمان وصول الطلب بدقة',
          foregroundServiceNotificationId: 888,
        ),
        iosConfiguration: IosConfiguration(autoStart: true, onForeground: onStart),
      );
      service.startService();
    }
  }

  Future<void> _stopBackgroundTracking() async {
    FlutterBackgroundService().invoke("stopService");
  }

  Future<void> _initInitialLocation() async {
    Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
    if (mounted) {
      setState(() => _currentLocation = LatLng(position.latitude, position.longitude));
      _setupDynamicTracking();
    }
  }

  void _setupDynamicTracking() {
    FirebaseFirestore.instance.collection('specialRequests').doc(widget.orderId).snapshots().listen((orderSnap) {
      if (!orderSnap.exists || !mounted) return;
      var data = orderSnap.data() as Map<String, dynamic>;
      String status = data['status'];
      GeoPoint targetGeo = (status == 'accepted') ? data['pickupLocation'] : data['dropoffLocation'];
      _startSmartLiveTracking(LatLng(targetGeo.latitude, targetGeo.longitude));
    });
  }

  void _startSmartLiveTracking(LatLng target) {
    _positionStream?.cancel();
    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 0),
    ).listen((Position pos) {
      if (!mounted) return;
      double distanceToTarget = Geolocator.distanceBetween(pos.latitude, pos.longitude, target.latitude, target.longitude);
      
      setState(() {
        _currentLocation = LatLng(pos.latitude, pos.longitude);
        _updateDriverLocationInFirestore(pos);
        _updateRoute(target);
      });
    });
  }

  void _updateDriverLocationInFirestore(Position pos) {
    if (_uid != null) {
      FirebaseFirestore.instance.collection('freeDrivers').doc(_uid!).update({
        'location': GeoPoint(pos.latitude, pos.longitude),
        'lastSeen': FieldValue.serverTimestamp()
      });
    }
  }

  Future<void> _launchGoogleMaps(GeoPoint point) async {
    final url = 'google.navigation:q=${point.latitude},${point.longitude}';
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      final fallbackUrl = 'https://www.google.com/maps/search/?api=1&query=${point.latitude},${point.longitude}';
      await launchUrl(Uri.parse(fallbackUrl), mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        _showExitWarning();
      },
      child: Scaffold(
        body: Stack(
          children: [
            _buildMap(),
            Positioned(
              top: 0, left: 0, right: 0,
              child: SafeArea(child: _buildCustomAppBar()),
            ),
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: SafeArea(child: _buildBottomPanel()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMap() {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('specialRequests').doc(widget.orderId).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        var data = snapshot.data!.data() as Map<String, dynamic>;
        GeoPoint pickup = data['pickupLocation'];
        GeoPoint dropoff = data['dropoffLocation'];
        String status = data['status'];
        GeoPoint targetGeo = (status == 'accepted') ? pickup : dropoff;

        return FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: _currentLocation ?? LatLng(targetGeo.latitude, targetGeo.longitude),
            initialZoom: 15,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://api.mapbox.com/styles/v1/mapbox/streets-v12/tiles/{z}/{x}/{y}?access_token=$_mapboxToken',
            ),
            if (_routePoints.isNotEmpty)
              PolylineLayer(polylines: [
                Polyline(points: _routePoints, color: Colors.blueAccent, strokeWidth: 5),
              ]),
            MarkerLayer(markers: [
              if (_currentLocation != null)
                Marker(point: _currentLocation!, child: Icon(Icons.delivery_dining, color: Colors.blue[900], size: 30.sp)),
              Marker(point: LatLng(pickup.latitude, pickup.longitude), child: Icon(Icons.store, color: Colors.orange[900], size: 25.sp)),
              Marker(point: LatLng(dropoff.latitude, dropoff.longitude), child: Icon(Icons.person_pin_circle, color: Colors.red, size: 25.sp)),
            ]),
          ],
        );
      },
    );
  }

  Widget _buildCustomAppBar() {
    return Container(
      margin: EdgeInsets.all(10.sp),
      padding: EdgeInsets.symmetric(horizontal: 15.sp, vertical: 8.sp),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10)],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(onPressed: _showExitWarning, icon: const Icon(Icons.arrow_back_ios_new)),
          Text("تتبع الطلب المباشر", style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.bold)),
          TextButton(
            onPressed: _driverCancelOrder,
            child: Text("اعتذار", style: TextStyle(color: Colors.red[900], fontWeight: FontWeight.bold, fontSize: 11.sp)),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomPanel() {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('specialRequests').doc(widget.orderId).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || !snapshot.data!.exists) return const SizedBox();
        var data = snapshot.data!.data() as Map<String, dynamic>;
        String status = data['status'];
        GeoPoint targetLoc = (status == 'accepted') ? data['pickupLocation'] : data['dropoffLocation'];
        bool isAtPickup = status == 'accepted';

        // ✅ حساب المسافة الذكية
        double dist = _getSmartDistance(data, status);

        return Container(
          margin: EdgeInsets.all(12.sp),
          padding: EdgeInsets.all(16.sp),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(25),
            boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 20, offset: const Offset(0, -5))],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  _buildCircleAction(
                    icon: Icons.navigation_rounded,
                    label: "توجيه",
                    color: Colors.blue[800]!,
                    onTap: () => _launchGoogleMaps(targetLoc),
                  ),
                  SizedBox(width: 4.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(isAtPickup ? "الاستلام من المتجر" : "التوصيل للعميل", 
                              style: TextStyle(color: Colors.grey[600], fontSize: 10.sp, fontWeight: FontWeight.bold)),
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(5)),
                              child: Text("${dist.toStringAsFixed(1)} كم متبقي", 
                                style: TextStyle(color: Colors.blue[900], fontSize: 9.sp, fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                        SizedBox(height: 4),
                        Text(isAtPickup ? (data['pickupAddress'] ?? "المتجر") : (data['dropoffAddress'] ?? "العميل"),
                          style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w900), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  SizedBox(width: 4.w),
                  _buildCircleAction(
                    icon: Icons.phone_in_talk_rounded,
                    label: "اتصال",
                    color: Colors.green[700]!,
                    onTap: () => launchUrl(Uri.parse("tel:${data['userPhone'] ?? ''}")),
                  ),
                ],
              ),
              SizedBox(height: 2.h),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isAtPickup ? Colors.orange[900] : Colors.green[800],
                    padding: EdgeInsets.symmetric(vertical: 1.8.h),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                    elevation: 4,
                  ),
                  onPressed: () => isAtPickup ? _showVerificationDialog(data['verificationCode']) : _completeOrder(),
                  child: Text(
                    isAtPickup ? "تأكيد كود الاستلام 📦" : "تم التسليم بنجاح ✅",
                    style: TextStyle(color: Colors.white, fontSize: 16.sp, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCircleAction({required IconData icon, required String label, required Color color, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            padding: EdgeInsets.all(12.sp),
            decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle, border: Border.all(color: color.withOpacity(0.2))),
            child: Icon(icon, color: color, size: 22.sp),
          ),
          SizedBox(height: 4),
          Text(label, style: TextStyle(color: color, fontSize: 10.sp, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  void _showExitWarning() async {
    final bool shouldExit = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("تنبيه", textAlign: TextAlign.right),
        content: const Text("هل تريد العودة؟ التتبع سيظل نشطاً.", textAlign: TextAlign.right),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("بقاء")),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("خروج")),
        ],
      ),
    ) ?? false;
    if (shouldExit && mounted) {
      final prefs = await SharedPreferences.getInstance();
      String vType = prefs.getString('user_vehicle_config') ?? 'motorcycleConfig';
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => AvailableOrdersScreen(vehicleType: vType)));
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
        if (mounted) setState(() => _routePoints = coords.map((c) => LatLng(c[1], c[0])).toList());
      }
    } catch (e) { debugPrint("Route Error: $e"); }
  }

  void _showVerificationDialog(String? correctCode) {
    final TextEditingController _codeController = TextEditingController();
    showDialog(
      context: context, barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("أدخل كود الاستلام"),
        content: TextField(controller: _codeController, textAlign: TextAlign.center, style: TextStyle(fontSize: 22.sp, fontWeight: FontWeight.bold), decoration: const InputDecoration(hintText: "كود المتجر")),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("إلغاء")),
          ElevatedButton(onPressed: () { if (_codeController.text.trim() == correctCode?.trim()) { Navigator.pop(context); _updateStatus('picked_up'); } else { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("الكود غير صحيح!"))); } }, child: const Text("تأكيد")),
        ],
      ),
    );
  }

  void _updateStatus(String nextStatus) async { await FirebaseFirestore.instance.collection('specialRequests').doc(widget.orderId).update({'status': nextStatus}); }

  Future<void> _driverCancelOrder() async {
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("اعتذار عن الرحلة", textAlign: TextAlign.right),
        content: const Text("هل أنت متأكد من الاعتذار؟", textAlign: TextAlign.right),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("تراجع")),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), style: ElevatedButton.styleFrom(backgroundColor: Colors.red), child: const Text("تأكيد الاعتذار")),
        ],
      ),
    );
    if (confirm == true) {
      await _stopBackgroundTracking(); 
      try {
        await FirebaseFirestore.instance.collection('specialRequests').doc(widget.orderId).update({
          'status': 'driver_cancelled_reseeking',
          'lastDriverId': _uid,
          'driverId': FieldValue.delete(),
          'driverName': FieldValue.delete(),
        });
        if (mounted) {
          final prefs = await SharedPreferences.getInstance();
          String vType = prefs.getString('user_vehicle_config') ?? 'motorcycleConfig';
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => AvailableOrdersScreen(vehicleType: vType)));
        }
      } catch (e) { debugPrint("Cancel Error: $e"); }
    }
  }

  void _completeOrder() async {
    showDialog(context: context, barrierDismissible: false, builder: (c) => const Center(child: CircularProgressIndicator()));
    await _stopBackgroundTracking(); 
    final orderRef = FirebaseFirestore.instance.collection('specialRequests').doc(widget.orderId);
    try {
      double savedCommission = 0;
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        DocumentSnapshot orderSnap = await transaction.get(orderRef);
        savedCommission = (orderSnap.get('commissionAmount') ?? 0.0).toDouble();
        transaction.update(orderRef, {'status': 'delivered', 'completedAt': FieldValue.serverTimestamp()});
        if (_uid != null && savedCommission > 0) {
          final driverRef = FirebaseFirestore.instance.collection('freeDrivers').doc(_uid!);
          transaction.update(driverRef, {'walletBalance': FieldValue.increment(-savedCommission)});
        }
      });
      if (mounted) {
        Navigator.pop(context);
        final prefs = await SharedPreferences.getInstance();
        String vType = prefs.getString('user_vehicle_config') ?? 'motorcycleConfig';
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => AvailableOrdersScreen(vehicleType: vType)));
      }
    } catch (e) { if (mounted) { Navigator.pop(context); } }
  }
}

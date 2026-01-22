import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:sizer/sizer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'available_orders_screen.dart';

// ✅ دالة البداية للخدمة (يجب أن تكون خارج الكلاس)
@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();

  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService();
    });

    service.on('setAsBackground').listen((event) {
      service.setAsBackgroundService();
    });
  }

  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  // تحديث الموقع دورياً في الخلفية
  Timer.periodic(const Duration(seconds: 15), (timer) async {
    if (service is AndroidServiceInstance) {
      if (await service.isForegroundService()) {
        service.setForegroundNotificationInfo(
          title: "أكسب: رحلة نشطة",
          content: "يتم تحديث موقعك لضمان دقة التوصيل",
        );
      }
    }

    try {
      Position pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      final prefs = await SharedPreferences.getInstance();
      String? uid = prefs.getString('driver_uid');
      
      if (uid != null) {
        // تحديث الفايربيز مباشرة من الخلفية
        FirebaseFirestore.instance.collection('freeDrivers').doc(uid).update({
          'location': GeoPoint(pos.latitude, pos.longitude),
          'lastSeen': FieldValue.serverTimestamp()
        });
      }
    } catch (e) {
      print("Background Update Error: $e");
    }
  });
}

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

  // --- 🛰️ إعدادات تتبع الخلفية الجديدة ---
  Future<void> _startBackgroundTracking() async {
    if (_uid != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('driver_uid', _uid!);

      final service = FlutterBackgroundService();
      
      await service.configure(
        androidConfiguration: AndroidConfiguration(
          onStart: onStart, // الربط بالدالة الخارجية
          autoStart: true,
          isForegroundMode: true,
          notificationChannelId: 'aksab_tracking_channel',
          initialNotificationTitle: 'أكسب: رحلة قيد التنفيذ',
          initialNotificationContent: 'جاري تتبع موقعك الآن',
          foregroundServiceNotificationId: 888,
        ),
        iosConfiguration: IosConfiguration(autoStart: true, onForeground: onStart),
      );
      
      service.startService();
    }
  }

  Future<void> _stopBackgroundTracking() async {
    final service = FlutterBackgroundService();
    service.invoke("stopService");
  }

  // --- 📍 منطق التتبع والخريطة ---
  Future<void> _initInitialLocation() async {
    try {
      Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      if (mounted) {
        setState(() => _currentLocation = LatLng(position.latitude, position.longitude));
        _setupDynamicTracking();
      }
    } catch (e) {
      debugPrint("Location Init Error: $e");
    }
  }

  void _setupDynamicTracking() {
    FirebaseFirestore.instance.collection('specialRequests').doc(widget.orderId).snapshots().listen((orderSnap) {
      if (!orderSnap.exists || !mounted) return;
      var data = orderSnap.data() as Map<String, dynamic>;
      String status = data['status'];
      GeoPoint targetGeo = (status == 'accepted') ? data['pickupLocation'] : data['dropoffLocation'];
      LatLng targetLatLng = LatLng(targetGeo.latitude, targetGeo.longitude);
      _startSmartLiveTracking(targetLatLng);
    });
  }

  void _startSmartLiveTracking(LatLng target) {
    _positionStream?.cancel();
    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 5),
    ).listen((Position pos) {
      if (!mounted) return;
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

  // --- 🛠️ أفعال المندوب ---
  Future<void> _driverCancelOrder() async {
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("اعتذار عن الرحلة", textAlign: TextAlign.right),
        content: const Text("هل أنت متأكد من الاعتذار؟ سيتم سحب الطلب منك.", textAlign: TextAlign.right),
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

  Future<void> _launchGoogleMaps(GeoPoint point) async {
    final url = 'google.navigation:q=${point.latitude},${point.longitude}';
    if (await canLaunchUrl(Uri.parse(url))) { await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication); }
  }

  void _updateStatus(String nextStatus) async { await FirebaseFirestore.instance.collection('specialRequests').doc(widget.orderId).update({'status': nextStatus}); }

  void _completeOrder() async {
    showDialog(context: context, barrierDismissible: false, builder: (c) => const Center(child: CircularProgressIndicator()));
    await _stopBackgroundTracking(); 
    final orderRef = FirebaseFirestore.instance.collection('specialRequests').doc(widget.orderId);
    try {
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        DocumentSnapshot orderSnap = await transaction.get(orderRef);
        double savedCommission = (orderSnap.get('commissionAmount') ?? 0.0).toDouble();
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
    } catch (e) { if (mounted) { Navigator.pop(context); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("فشل: $e"))); } }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final bool shouldExit = await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text("تنبيه"),
            content: const Text("الرحلة وتتبع الموقع سيظلان نشطين في الخلفية. هل تريد العودة؟"),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("بقاء")),
              ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text("عودة")),
            ],
          ),
        ) ?? false;

        if (shouldExit && context.mounted) {
          final prefs = await SharedPreferences.getInstance();
          String vType = prefs.getString('user_vehicle_config') ?? 'motorcycleConfig';
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => AvailableOrdersScreen(vehicleType: vType)));
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text("تتبع المسار", style: TextStyle(fontSize: 14.sp)),
          actions: [IconButton(onPressed: _driverCancelOrder, icon: const Icon(Icons.cancel, color: Colors.red))],
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

            return Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(initialCenter: _currentLocation ?? LatLng(targetGeo.latitude, targetGeo.longitude), initialZoom: 15),
                  children: [
                    TileLayer(urlTemplate: 'https://api.mapbox.com/styles/v1/mapbox/streets-v11/tiles/{z}/{x}/{y}?access_token={accessToken}', additionalOptions: {'accessToken': _mapboxToken}),
                    if (_routePoints.isNotEmpty) PolylineLayer(polylines: [Polyline(points: _routePoints, color: Colors.blue, strokeWidth: 5)]),
                    MarkerLayer(markers: [
                      if (_currentLocation != null) Marker(point: _currentLocation!, child: const Icon(Icons.delivery_dining, color: Colors.blue, size: 40)),
                      Marker(point: LatLng(pickup.latitude, pickup.longitude), child: const Icon(Icons.store, color: Colors.orange)),
                      Marker(point: LatLng(dropoff.latitude, dropoff.longitude), child: const Icon(Icons.person_pin_circle, color: Colors.red)),
                    ]),
                  ],
                ),
                Positioned(
                  bottom: 20, left: 10, right: 10,
                  child: Card(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(status == 'accepted' ? "توجه لنقطة الاستلام" : "توجه لتسليم الطلب", style: const TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 10),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50), backgroundColor: Colors.orange),
                            onPressed: () => status == 'accepted' ? _showVerificationDialog(data['verificationCode']) : _completeOrder(),
                            child: Text(status == 'accepted' ? "تأكيد الاستلام" : "تم التسليم"),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              ],
            );
          },
        ),
      ),
    );
  }

  void _showVerificationDialog(String? correctCode) {
    final TextEditingController _codeController = TextEditingController();
    showDialog(
      context: context, barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text("كود الاستلام"),
        content: TextField(controller: _codeController, keyboardType: TextInputType.number, decoration: const InputDecoration(hintText: "أدخل الكود من المتجر")),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("إلغاء")),
          ElevatedButton(onPressed: () { if (_codeController.text == correctCode) { Navigator.pop(context); _updateStatus('picked_up'); } }, child: const Text("تأكيد")),
        ],
      ),
    );
  }
}

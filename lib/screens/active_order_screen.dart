// lib/screens/active_order_screen.dart
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

  double _getSmartDistance(Map<String, dynamic> data, String status) {
    if (_currentLocation == null) return 0.0;
    GeoPoint pickup = data['pickupLocation'];
    GeoPoint dropoff = data['dropoffLocation'];

    if (status == 'accepted') {
      double d1 = Geolocator.distanceBetween(_currentLocation!.latitude, _currentLocation!.longitude, pickup.latitude, pickup.longitude);
      double d2 = Geolocator.distanceBetween(pickup.latitude, pickup.longitude, dropoff.latitude, dropoff.longitude);
      return (d1 + d2) / 1000;
    } else {
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

  Future<void> _launchGoogleMaps(GeoPoint point) async {
    final url = 'google.navigation:q=${point.latitude},${point.longitude}';
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
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
            Positioned(top: 0, left: 0, right: 0, child: _buildCustomAppBar()),
            Positioned(bottom: 0, left: 0, right: 0, child: _buildBottomPanel()),
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

        return FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: _currentLocation ?? LatLng(pickup.latitude, pickup.longitude),
            initialZoom: 15,
          ),
          children: [
            TileLayer(urlTemplate: 'https://api.mapbox.com/styles/v1/mapbox/streets-v12/tiles/{z}/{x}/{y}?access_token=$_mapboxToken'),
            if (_routePoints.isNotEmpty)
              PolylineLayer(polylines: [Polyline(points: _routePoints, color: Colors.blueAccent, strokeWidth: 5)]),
            MarkerLayer(markers: [
              if (_currentLocation != null)
                Marker(point: _currentLocation!, child: Icon(Icons.delivery_dining, color: Colors.blue[900], size: 30.sp)),
              Marker(point: LatLng(pickup.latitude, pickup.longitude), child: Icon(Icons.location_on, color: Colors.orange[900], size: 25.sp)),
              Marker(point: LatLng(dropoff.latitude, dropoff.longitude), child: Icon(Icons.person_pin_circle, color: Colors.red, size: 25.sp)),
            ]),
          ],
        );
      },
    );
  }

  Widget _buildCustomAppBar() {
    return SafeArea(
      child: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('specialRequests').doc(widget.orderId).snapshots(),
        builder: (context, snapshot) {
          String status = 'accepted';
          if (snapshot.hasData && snapshot.data!.exists) {
            status = snapshot.data!.get('status') ?? 'accepted';
          }
          return Container(
            margin: EdgeInsets.all(10.sp),
            padding: EdgeInsets.symmetric(horizontal: 10.sp, vertical: 5.sp),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10)]),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(onPressed: _showExitWarning, icon: const Icon(Icons.arrow_back_ios_new)),
                Text("تتبع الرحلة النشطة", style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
                status == 'accepted' 
                  ? TextButton(onPressed: _driverCancelOrder, child: Text("اعتذار", style: TextStyle(color: Colors.red[900], fontWeight: FontWeight.bold, fontFamily: 'Cairo')))
                  : SizedBox(width: 40.sp),
              ],
            ),
          );
        }
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
        double dist = _getSmartDistance(data, status);

        return SafeArea(
          child: Container(
            margin: EdgeInsets.fromLTRB(12.sp, 0, 12.sp, 10.sp),
            padding: EdgeInsets.all(16.sp),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(25), boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 20, offset: const Offset(0, -5))]),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    _buildCircleAction(icon: Icons.navigation_rounded, label: "توجيه", color: Colors.blue[800]!, onTap: () => _launchGoogleMaps(targetLoc)),
                    SizedBox(width: 4.w),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(isAtPickup ? "نقطة الاستلام" : "نقطة التسليم", style: TextStyle(color: Colors.grey[600], fontSize: 9.sp, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
                              Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(5)), child: Text("${dist.toStringAsFixed(1)} كم متبقي", style: TextStyle(color: Colors.blue[900], fontSize: 8.sp, fontWeight: FontWeight.bold))),
                            ],
                          ),
                          Text(isAtPickup ? (data['pickupAddress'] ?? "الموقع الأول") : (data['dropoffAddress'] ?? "موقع العميل"), style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w900, fontFamily: 'Cairo'), maxLines: 1, overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                    SizedBox(width: 4.w),
                    _buildCircleAction(icon: Icons.phone_in_talk_rounded, label: "اتصال", color: Colors.green[700]!, onTap: () => launchUrl(Uri.parse("tel:${data['userPhone'] ?? ''}"))),
                  ],
                ),
                SizedBox(height: 2.h),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: isAtPickup ? Colors.orange[900] : Colors.green[800], padding: EdgeInsets.symmetric(vertical: 1.5.h), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)), elevation: 4),
                    onPressed: () => isAtPickup ? _showProfessionalOTPDialog(data['verificationCode']) : _completeOrder(),
                    child: Text(isAtPickup ? "تأكيد كود الاستلام 📦" : "تم التسليم بنجاح ✅", style: TextStyle(color: Colors.white, fontSize: 14.sp, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCircleAction({required IconData icon, required String label, required Color color, required VoidCallback onTap}) {
    return InkWell(onTap: onTap, child: Column(children: [Container(padding: EdgeInsets.all(12.sp), decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle), child: Icon(icon, color: color, size: 20.sp)), const SizedBox(height: 4), Text(label, style: TextStyle(color: color, fontSize: 9.sp, fontWeight: FontWeight.bold, fontFamily: 'Cairo'))]));
  }

  void _showProfessionalOTPDialog(String? correctCode) {
    List<TextEditingController> controllers = List.generate(4, (index) => TextEditingController());
    List<FocusNode> focusNodes = List.generate(4, (index) => FocusNode());

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
        title: const Text("كود تأكيد الاستلام", textAlign: TextAlign.center, style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("اطلب الكود من العميل في نقطة الاستلام", style: TextStyle(fontSize: 10, fontFamily: 'Cairo')),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(4, (index) => SizedBox(
                width: 12.w,
                child: TextField(
                  controller: controllers[index],
                  focusNode: focusNodes[index],
                  textAlign: TextAlign.center,
                  keyboardType: TextInputType.number,
                  maxLength: 1,
                  style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold),
                  decoration: InputDecoration(counterText: "", border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                  onChanged: (value) {
                    if (value.isNotEmpty && index < 3) focusNodes[index + 1].requestFocus();
                    if (value.isEmpty && index > 0) focusNodes[index - 1].requestFocus();
                  },
                ),
              )),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("إلغاء", style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange[900]),
            onPressed: () {
              String enteredCode = controllers.map((e) => e.text).join();
              if (enteredCode == correctCode?.trim()) {
                Navigator.pop(context);
                _updateStatus('picked_up');
              } else {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(backgroundColor: Colors.red, content: Text("الكود غير صحيح!")));
              }
            },
            child: const Text("تأكيد", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _updateStatus(String nextStatus) async { await FirebaseFirestore.instance.collection('specialRequests').doc(widget.orderId).update({'status': nextStatus}); }

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

  void _showExitWarning() async {
    final bool shouldExit = await showDialog(context: context, builder: (context) => AlertDialog(title: const Text("تنبيه"), content: const Text("العودة للرادار؟ تتبع الرحلة سيستمر في الخلفية."), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("بقاء")), TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("خروج"))])) ?? false;
    if (shouldExit && mounted) {
      final prefs = await SharedPreferences.getInstance();
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => AvailableOrdersScreen(vehicleType: prefs.getString('user_vehicle_config') ?? 'motorcycleConfig')));
    }
  }

  Future<void> _driverCancelOrder() async {
    bool? confirm = await showDialog(context: context, builder: (context) => AlertDialog(title: const Text("تأكيد الاعتذار"), content: const Text("سيتم خصم عمولة بسيطة عند تكرار الاعتذار عن رحلات مقبولة."), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("تراجع")), ElevatedButton(onPressed: () => Navigator.pop(context, true), style: ElevatedButton.styleFrom(backgroundColor: Colors.red), child: const Text("تأكيد"))]));
    if (confirm == true) {
      await _stopBackgroundTracking();
      await FirebaseFirestore.instance.collection('specialRequests').doc(widget.orderId).update({'status': 'driver_cancelled_reseeking', 'lastDriverId': _uid, 'driverId': FieldValue.delete()});
      if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => AvailableOrdersScreen(vehicleType: 'motorcycleConfig')));
    }
  }

  // ✅ النسخة المعدلة لإنهاء الطلب بالخصم الذكي (ائتمان ثم محفظة)
  void _completeOrder() async {
    showDialog(context: context, barrierDismissible: false, builder: (c) => const Center(child: CircularProgressIndicator(color: Colors.green)));
    await _stopBackgroundTracking();

    try {
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        // 1. بيانات الطلب والعمولة
        DocumentReference orderRef = FirebaseFirestore.instance.collection('specialRequests').doc(widget.orderId);
        DocumentSnapshot orderSnap = await transaction.get(orderRef);
        double commission = double.tryParse(orderSnap.get('commissionAmount')?.toString() ?? '0') ?? 0.0;

        // 2. بيانات المندوب (الائتمان والمحفظة)
        DocumentReference driverRef = FirebaseFirestore.instance.collection('freeDrivers').doc(_uid!);
        DocumentSnapshot driverSnap = await transaction.get(driverRef);

        double currentCredit = double.tryParse(driverSnap.get('creditLimit')?.toString() ?? '0') ?? 0.0;

        // --- حساب توزيع الخصم ---
        double deductionFromCredit = 0;
        double deductionFromWallet = 0;

        if (currentCredit >= commission) {
          deductionFromCredit = commission;
        } else {
          deductionFromCredit = currentCredit > 0 ? currentCredit : 0;
          deductionFromWallet = commission - deductionFromCredit;
        }

        // 3. تحديث الطلب
        transaction.update(orderRef, {
          'status': 'delivered', 
          'completedAt': FieldValue.serverTimestamp()
        });

        // 4. تحديث حساب المندوب
        transaction.update(driverRef, {
          'creditLimit': FieldValue.increment(-deductionFromCredit),
          'walletBalance': FieldValue.increment(-deductionFromWallet),
        });

        // 5. تسجيل العملية في سجل العمليات
        DocumentReference logRef = FirebaseFirestore.instance.collection('walletLogs').doc();
        transaction.set(logRef, {
          'driverId': _uid,
          'orderId': widget.orderId,
          'amount': -commission,
          'fromCredit': deductionFromCredit,
          'fromWallet': deductionFromWallet,
          'timestamp': FieldValue.serverTimestamp(),
          'type': 'COMMISSION_DEDUCTION',
          'note': 'خصم عمولة طلب توصيل'
        });
      });

      if (mounted) {
        Navigator.pop(context);
        final prefs = await SharedPreferences.getInstance();
        Navigator.pushReplacement(context, MaterialPageRoute(
          builder: (context) => AvailableOrdersScreen(
            vehicleType: prefs.getString('user_vehicle_config') ?? 'motorcycleConfig'
          )
        ));
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("فشل إنهاء الطلب: $e"), backgroundColor: Colors.red));
      }
    }
  }
}

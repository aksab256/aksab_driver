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
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

  // --- 🛡️ منطق الحماية والرجوع ---
  void _handleBackAction() async {
    final bool shouldExit = await showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text("تنبيه الرحلة", style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
          content: const Text("هل تود العودة للقائمة الرئيسية؟ تتبع الرحلة سيستمر في الخلفية لضمان حقوقك وحقوق العميل."),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("بقاء في الرحلة", style: TextStyle(fontFamily: 'Cairo', color: Colors.grey))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange[900], shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              onPressed: () => Navigator.pop(context, true), 
              child: const Text("الرئيسية", style: TextStyle(fontFamily: 'Cairo', color: Colors.white))
            )
          ],
        ),
      )
    ) ?? false;
    if (shouldExit && mounted) Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
  }

  // --- 🛰️ تتبع الموقع ---
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

  Future<void> _stopBackgroundTracking() async => FlutterBackgroundService().invoke("stopService");

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
      GeoPoint targetGeo = (status == 'accepted' || status == 'returning_to_merchant') ? data['pickupLocation'] : data['dropoffLocation'];
      _startSmartLiveTracking(LatLng(targetGeo.latitude, targetGeo.longitude));
    });
  }

  void _startSmartLiveTracking(LatLng target) {
    _positionStream?.cancel();
    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 5),
    ).listen((Position pos) {
      if (mounted) {
        setState(() {
          _currentLocation = LatLng(pos.latitude, pos.longitude);
          _updateDriverLocationInFirestore(pos);
          _updateRoute(target);
        });
      }
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

  // --- 📱 شريط التحكم السفلي ---
  Widget _buildBottomPanel() {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('specialRequests').doc(widget.orderId).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || !snapshot.data!.exists) return const SizedBox();
        var data = snapshot.data!.data() as Map<String, dynamic>;
        
        String status = data['status'];
        // التحقق من المصدر (تاجر أو مستهلك) بناءً على requestSource
        bool isMerchant = data['requestSource'] == 'retailer'; 
        bool isAtPickup = status == 'accepted' || status == 'returning_to_merchant';

        // 📞 جلب الهواتف من الحقول الصحيحة
        String senderPhone = data['userPhone'] ?? ''; 
        String receiverPhone = data['customerPhone'] ?? ''; 
        
        GeoPoint targetLoc = isAtPickup ? data['pickupLocation'] : data['dropoffLocation'];
        double dist = _getSmartDistance(data, status);

        return SafeArea(
          child: Container(
            margin: EdgeInsets.fromLTRB(12.sp, 0, 12.sp, 10.sp),
            padding: EdgeInsets.all(16.sp),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(25), boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 20)]),
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
                          Text(status == 'returning_to_merchant' ? "إرجاع للتاجر" : (isAtPickup ? "نقطة الاستلام" : "نقطة التسليم"), style: TextStyle(color: Colors.grey[600], fontSize: 9.sp, fontFamily: 'Cairo')),
                          Text(isAtPickup ? (data['pickupAddress'] ?? "الموقع") : (data['dropoffAddress'] ?? "العميل"), style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w900, fontFamily: 'Cairo'), maxLines: 1, overflow: TextOverflow.ellipsis),
                          Text("${dist.toStringAsFixed(1)} كم متبقي", style: TextStyle(color: Colors.blue[900], fontSize: 9.sp, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ],
                ),
                const Divider(height: 25),
                
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildPhoneItem(label: isMerchant ? "اتصال بالتاجر" : "اتصال بالراسل", phone: senderPhone, color: Colors.orange[800]!),
                    if (receiverPhone.isNotEmpty) 
                      _buildPhoneItem(label: "اتصال بالمستلم", phone: receiverPhone, color: Colors.green[700]!),
                  ],
                ),
                
                SizedBox(height: 2.h),
                
                if (status == 'accepted') 
                  _mainButton("تأكيد استلام العهدة 📦", Colors.orange[900]!, () => _showProfessionalOTP(data['verificationCode'], isMerchant))
                
                else if (status == 'picked_up')
                  isMerchant 
                    ? Row(children: [
                        Expanded(child: _mainButton("فشل التسليم ❌", Colors.red[800]!, () => _handleReturnFlow())),
                        const SizedBox(width: 10),
                        Expanded(child: _mainButton("تم التسليم ✅", Colors.green[800]!, () => _completeOrder())),
                      ])
                    : _mainButton("تم التسليم للعميل ✅", Colors.green[800]!, () => _completeOrder())
                
                else if (status == 'returning_to_merchant')
                  _mainButton("تأكيد إرجاع العهدة للتاجر 🔄", Colors.blueGrey[800]!, () => _showProfessionalOTP(data['verificationCode'], true)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPhoneItem({required String label, required String phone, required Color color}) {
    return InkWell(
      onTap: () => launchUrl(Uri.parse("tel:$phone")),
      child: Column(
        children: [
          CircleAvatar(backgroundColor: color.withOpacity(0.1), child: Icon(Icons.phone, color: color, size: 18.sp)),
          SizedBox(height: 5),
          Text(label, style: TextStyle(fontFamily: 'Cairo', fontSize: 8.sp, color: color, fontWeight: FontWeight.bold)),
          Text(phone, style: TextStyle(fontSize: 9.sp, color: Colors.grey[700])),
        ],
      ),
    );
  }

  void _showProfessionalOTP(String? correctCode, bool isMerchantAsset) {
    List<TextEditingController> ctrls = List.generate(4, (i) => TextEditingController());
    List<FocusNode> nodes = List.generate(4, (i) => FocusNode());
    showDialog(
      context: context, barrierDismissible: false,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(isMerchantAsset ? "تأكيد العهدة" : "كود الاستلام", textAlign: TextAlign.center, style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isMerchantAsset) const Text("بإدخال كود التاجر، أنت تؤكد استلام الشحنة في عهدتك وسيتم تخصيص نقاط أمان من حسابك.", textAlign: TextAlign.center, style: TextStyle(fontFamily: 'Cairo', fontSize: 10)),
              SizedBox(height: 2.h),
              Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: List.generate(4, (i) => SizedBox(width: 12.w, child: TextField(
                controller: ctrls[i], focusNode: nodes[i], textAlign: TextAlign.center, keyboardType: TextInputType.number, maxLength: 1,
                decoration: InputDecoration(counterText: "", border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
                onChanged: (v) { if (v.isNotEmpty && i < 3) nodes[i + 1].requestFocus(); if (v.isEmpty && i > 0) nodes[i - 1].requestFocus(); },
              )))),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("إلغاء")),
            ElevatedButton(onPressed: () {
              if (ctrls.map((e) => e.text).join() == correctCode?.trim()) {
                Navigator.pop(context);
                _updateStatus('picked_up');
              } else {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("الكود غير صحيح"), backgroundColor: Colors.red));
              }
            }, child: const Text("تأكيد")),
          ],
        ),
      ),
    );
  }

  void _handleReturnFlow() async {
    bool? confirm = await showDialog(context: context, builder: (c) => Directionality(textDirection: TextDirection.rtl, child: AlertDialog(title: const Text("بدء عملية المرتجع"), content: const Text("هل تريد تحويل الطلب لمرتجع والعودة للتاجر؟"), actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text("تراجع")), TextButton(onPressed: () => Navigator.pop(c, true), child: const Text("تأكيد"))])));
    if (confirm == true) _updateStatus('returning_to_merchant');
  }

  void _completeOrder() async {
    showDialog(context: context, barrierDismissible: false, builder: (c) => const Center(child: CircularProgressIndicator(color: Colors.green)));
    await _stopBackgroundTracking();
    try {
      await FirebaseFirestore.instance.collection('specialRequests').doc(widget.orderId).update({'status': 'delivered', 'completedAt': FieldValue.serverTimestamp()});
      if (mounted) { Navigator.pop(context); Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false); }
    } catch (e) { Navigator.pop(context); }
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
          options: MapOptions(initialCenter: _currentLocation ?? LatLng(pickup.latitude, pickup.longitude), initialZoom: 15),
          children: [
            TileLayer(urlTemplate: 'https://api.mapbox.com/styles/v1/mapbox/streets-v12/tiles/{z}/{x}/{y}?access_token=$_mapboxToken'),
            if (_routePoints.isNotEmpty) PolylineLayer(polylines: [Polyline(points: _routePoints, color: Colors.blueAccent, strokeWidth: 5)]),
            MarkerLayer(markers: [
              if (_currentLocation != null) Marker(point: _currentLocation!, child: Icon(Icons.delivery_dining, color: Colors.blue[900], size: 30.sp)),
              Marker(point: LatLng(pickup.latitude, pickup.longitude), child: Icon(Icons.location_on, color: Colors.orange[900], size: 25.sp)),
              Marker(point: LatLng(dropoff.latitude, dropoff.longitude), child: Icon(Icons.person_pin_circle, color: Colors.red, size: 25.sp)),
            ]),
          ],
        );
      },
    );
  }

  double _getSmartDistance(Map<String, dynamic> data, String status) {
    if (_currentLocation == null) return 0.0;
    GeoPoint target = (status == 'accepted' || status == 'returning_to_merchant') ? data['pickupLocation'] : data['dropoffLocation'];
    return Geolocator.distanceBetween(_currentLocation!.latitude, _currentLocation!.longitude, target.latitude, target.longitude) / 1000;
  }

  Widget _mainButton(String label, Color color, VoidCallback onTap) => SizedBox(width: double.infinity, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: color, padding: EdgeInsets.symmetric(vertical: 1.5.h), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))), onPressed: onTap, child: Text(label, style: TextStyle(color: Colors.white, fontSize: 13.sp, fontWeight: FontWeight.bold, fontFamily: 'Cairo'))));

  Widget _buildCircleAction({required IconData icon, required String label, required Color color, required VoidCallback onTap}) => InkWell(onTap: onTap, child: Column(children: [Container(padding: EdgeInsets.all(10.sp), decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle), child: Icon(icon, color: color, size: 20.sp)), Text(label, style: TextStyle(color: color, fontSize: 8.sp, fontFamily: 'Cairo'))]));

  Widget _buildCustomAppBar() => SafeArea(child: Container(margin: EdgeInsets.all(10.sp), padding: EdgeInsets.symmetric(horizontal: 10.sp, vertical: 5.sp), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10)]), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [IconButton(onPressed: _handleBackAction, icon: const Icon(Icons.arrow_back_ios_new)), Text("الرحلة النشطة", style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.bold, fontFamily: 'Cairo')), StreamBuilder<DocumentSnapshot>(stream: FirebaseFirestore.instance.collection('specialRequests').doc(widget.orderId).snapshots(), builder: (context, snap) { if (snap.hasData && snap.data!.exists && snap.data!['status'] == 'accepted') return IconButton(onPressed: _driverCancelOrder, icon: const Icon(Icons.cancel_outlined, color: Colors.red)); return SizedBox(width: 40.sp); })])));

  void _updateStatus(String nextStatus) async => await FirebaseFirestore.instance.collection('specialRequests').doc(widget.orderId).update({'status': nextStatus, 'updatedAt': FieldValue.serverTimestamp()});

  Future<void> _launchGoogleMaps(GeoPoint point) async {
    final url = 'google.navigation:q=${point.latitude},${point.longitude}';
    if (await canLaunchUrl(Uri.parse(url))) await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  Future<void> _updateRoute(LatLng dest) async {
    if (_currentLocation == null) return;
    final url = 'https://api.mapbox.com/directions/v5/mapbox/driving/${_currentLocation!.longitude},${_currentLocation!.latitude};${dest.longitude},${dest.latitude}?overview=full&geometries=geojson&access_token=$_mapboxToken';
    try {
      final res = await http.get(Uri.parse(url));
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final List coords = data['routes'][0]['geometry']['coordinates'];
        if (mounted) setState(() => _routePoints = coords.map((c) => LatLng(c[1], c[0])).toList());
      }
    } catch (e) { debugPrint("Route Error: $e"); }
  }

  Future<void> _driverCancelOrder() async {
    bool? confirm = await showDialog(context: context, builder: (c) => Directionality(textDirection: TextDirection.rtl, child: AlertDialog(title: const Text("اعتذار عن الرحلة"), content: const Text("هل أنت متأكد؟ قد يؤثر ذلك على تقييمك."), actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text("تراجع")), TextButton(onPressed: () => Navigator.pop(c, true), child: const Text("تأكيد", style: TextStyle(color: Colors.red)))])));
    if (confirm == true) {
      await _stopBackgroundTracking();
      await FirebaseFirestore.instance.collection('specialRequests').doc(widget.orderId).update({'status': 'driver_cancelled_reseeking', 'lastDriverId': _uid, 'driverId': FieldValue.delete()});
      if (mounted) Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) { if (!didPop) _handleBackAction(); },
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
}

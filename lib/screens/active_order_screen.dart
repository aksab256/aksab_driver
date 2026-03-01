import 'dart:async';
import 'dart:convert';
import 'dart:math';
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
    // تشغيل الخدمة فقط عند دخول هذه الشاشة
    _startBackgroundTracking(); 
    _initInitialLocation();
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    super.dispose();
  }

  void _handleBackAction() async {
    final bool shouldExit = await showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text("تنبيه الرحلة", style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 18.sp)),
          content: Text("هل تود العودة للقائمة الرئيسية؟ تتبع الرحلة سيستمر في الخلفية لضمان استرداد عهدتك المالية عند الوصول.", style: TextStyle(fontFamily: 'Cairo', fontSize: 14.sp)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text("بقاء في الرحلة", style: TextStyle(fontFamily: 'Cairo', color: Colors.grey, fontSize: 13.sp))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange[900], shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              onPressed: () => Navigator.pop(context, true), 
              child: Text("الرئيسية", style: TextStyle(fontFamily: 'Cairo', color: Colors.white, fontSize: 13.sp))
            )
          ],
        ),
      )
    ) ?? false;
    if (shouldExit && mounted) Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
  }

  Future<void> _startBackgroundTracking() async {
    if (_uid != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('driver_uid', _uid!);
      
      final service = FlutterBackgroundService();
      
      // التعديل الجوهري: إيقاف التشغيل التلقائي autoStart: false
      await service.configure(
        androidConfiguration: AndroidConfiguration(
          onStart: onStart, 
          autoStart: false, // ❌ لن تعمل الخدمة من تلقاء نفسها أبداً
          isForegroundMode: true,
          notificationChannelId: 'aksab_tracking_channel',
          initialNotificationTitle: 'أكسب: تأمين العهدة نشط 🛡️',
          initialNotificationContent: 'جاري تتبع الرحلة لضمان استرداد نقاط التأمين فور الوصول',
          foregroundServiceNotificationId: 888,
        ),
        iosConfiguration: IosConfiguration(
          autoStart: false, // ❌ لن تعمل في iOS تلقائياً أيضاً
          onForeground: onStart
        ),
      );
      
      // تشغيل الخدمة يدوياً الآن فقط لأن المندوب في شاشة الطلب النشط
      service.startService();
    }
  }

  // إيقاف الخدمة فوراً وإخفاء الإشعار
  Future<void> _stopBackgroundTracking() async {
    final service = FlutterBackgroundService();
    var isRunning = await service.isRunning();
    if (isRunning) {
      service.invoke("stopService");
    }
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
      bool moneyLocked = data['moneyLocked'] ?? false;
      
      if (status == 'pending' && !moneyLocked) {
         _showSecurityError();
         return;
      }

      GeoPoint targetGeo = (status == 'accepted' || status.contains('returning')) 
          ? data['pickupLocation'] 
          : data['dropoffLocation'];
          
      _startSmartLiveTracking(LatLng(targetGeo.latitude, targetGeo.longitude));
    });
  }

  void _showSecurityError() {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text("تأمين العهدة", style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
        content: const Text("جاري معالجة تأمين العهدة من رصيدك. إذا لم تتوفر نقاط كافية سيتم إلغاء الرحلة تلقائياً.", style: TextStyle(fontFamily: 'Cairo')),
        actions: [TextButton(onPressed: () => Navigator.pushReplacementNamed(context, '/'), child: const Text("موافق"))],
      )
    );
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

  Widget _phoneButton({required String? phone, required String label, required Color color}) {
    if (phone == null || phone.isEmpty) return const SizedBox();
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        padding: EdgeInsets.symmetric(horizontal: 10.sp, vertical: 5.sp),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      onPressed: () => launchUrl(Uri.parse("tel:$phone")),
      icon: Icon(Icons.phone_in_talk, color: Colors.white, size: 14.sp),
      label: Text(label, style: TextStyle(fontFamily: 'Cairo', color: Colors.white, fontSize: 11.sp, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildBottomPanel() {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('specialRequests').doc(widget.orderId).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || !snapshot.data!.exists) return const SizedBox();
        var data = snapshot.data!.data() as Map<String, dynamic>;
        
        String status = data['status'];
        bool isMerchant = data['requestSource'] == 'retailer'; 
        bool isAtPickup = status == 'accepted' || status.contains('returning');
        bool moneyLocked = data['moneyLocked'] ?? false;
        
        GeoPoint targetLoc = isAtPickup ? data['pickupLocation'] : data['dropoffLocation'];
        double dist = _getSmartDistance(data, status);

        return SafeArea(
          bottom: true,
          child: Container(
            margin: EdgeInsets.fromLTRB(10.sp, 0, 10.sp, 10.sp),
            padding: EdgeInsets.all(18.sp),
            decoration: BoxDecoration(
              color: Colors.white, 
              borderRadius: BorderRadius.circular(25), 
              boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 20)]
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildCircleAction(icon: Icons.navigation_rounded, label: "توجيه", color: Colors.blue[800]!, onTap: () => _launchGoogleMaps(targetLoc)),
                    SizedBox(width: 4.w),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(status.contains('returning') ? "🚨 عودة لتسليم المرتجع" : (isAtPickup ? "جهة الاستلام" : "جهة التسليم"), 
                               style: TextStyle(color: status.contains('returning') ? Colors.red : Colors.grey[700], fontSize: 12.sp, fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                          Text(isAtPickup ? (data['pickupAddress'] ?? "الموقع") : (data['dropoffAddress'] ?? "العميل"), 
                               style: TextStyle(fontSize: 17.sp, fontWeight: FontWeight.w900, fontFamily: 'Cairo', height: 1.2), maxLines: 2, overflow: TextOverflow.ellipsis),
                          SizedBox(height: 5),
                          Text("${dist.toStringAsFixed(1)} كم متبقي للوجهة", style: TextStyle(color: Colors.blue[900], fontSize: 13.sp, fontWeight: FontWeight.w900)),
                        ],
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 15),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Expanded(child: _phoneButton(phone: data['userPhone'], label: "اتصال بالراسل", color: Colors.orange[900]!)),
                    if (!isAtPickup || isMerchant) ...[
                      SizedBox(width: 10),
                      Expanded(child: _phoneButton(phone: data['customerPhone'], label: "اتصال بالمستلم", color: Colors.green[800]!)),
                    ]
                  ],
                ),
                const Divider(height: 30, thickness: 1),
                
                if (status == 'accepted') 
                  moneyLocked 
                    ? _mainButton(isMerchant ? "تأكيد استلام العهدة من التاجر 📦" : "تأكيد استلام الأمانة من العميل 📦", Colors.orange[900]!, () => _showProfessionalOTP(data['verificationCode'], status, isMerchant))
                    : Text("جاري معالجة تأمين العهدة...", style: TextStyle(fontFamily: 'Cairo', fontSize: 15.sp, color: Colors.orange[900], fontWeight: FontWeight.bold))
                
                else if (status == 'picked_up')
                  isMerchant 
                    ? Row(children: [
                        Expanded(child: _mainButton("رفض (مرتجع) ❌", Colors.red[800]!, () => _handleReturnFlow())),
                        const SizedBox(width: 12),
                        Expanded(child: _mainButton("تم التسليم ✅", Colors.green[800]!, () => _completeOrder())),
                      ])
                    : _mainButton("تم التسليم ✅", Colors.green[800]!, () => _completeOrder())
                
                else if (status.contains('returning'))
                  Column(
                    children: [
                      Text("يجب العودة للتاجر لإسترداد عهدتك المالية", style: TextStyle(fontFamily: 'Cairo', fontSize: 13.sp, color: Colors.red[900], fontWeight: FontWeight.w900)),
                      SizedBox(height: 10),
                      _mainButton("تأكيد تسليم المرتجع للتاجر 🔄", Colors.blueGrey[800]!, () => _showProfessionalOTP(data['returnVerificationCode'] ?? data['verificationCode'], status, isMerchant)),
                    ],
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showProfessionalOTP(String? correctCode, String currentStatus, bool isMerchant) {
    final TextEditingController codeController = TextEditingController();
    bool isReturning = currentStatus.contains('returning');

    showDialog(
      context: context, barrierDismissible: false,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(isReturning ? "تأكيد استلام المرتجع" : "تأكيد استلام العهدة", style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 16.sp)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(isReturning 
                ? "أدخل كود المرتجع من التاجر لفك حجز نقاطك فوراً."
                : isMerchant 
                    ? "أدخل الكود المستلم من التاجر لتأكيد العهدة في أمانتك."
                    : "أدخل الكود المستلم من العميل لتأكيد بدء رحلة النقل.", style: TextStyle(fontFamily: 'Cairo', fontSize: 13.sp)),
              SizedBox(height: 20),
              TextField(
                controller: codeController,
                textAlign: TextAlign.center,
                keyboardType: TextInputType.number,
                maxLength: 4,
                style: TextStyle(fontSize: 25.sp, fontWeight: FontWeight.bold, letterSpacing: 20),
                decoration: InputDecoration(
                  hintText: "----",
                  counterText: "",
                  filled: true,
                  fillColor: Colors.grey[100],
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text("إلغاء", style: TextStyle(fontFamily: 'Cairo', fontSize: 13.sp))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue[900], padding: EdgeInsets.symmetric(horizontal: 25, vertical: 10)),
              onPressed: () async {
                if (codeController.text.trim() == correctCode?.trim()) {
                  Navigator.pop(context);
                  if (isReturning) {
                    await FirebaseFirestore.instance.collection('specialRequests').doc(widget.orderId).update({
                      'status': 'returned_successfully', 
                      'updatedAt': FieldValue.serverTimestamp(),
                    });
                    await _stopBackgroundTracking(); // إيقاف الخدمة فوراً عند النجاح
                    if (mounted) Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
                  } else {
                    _updateStatus('picked_up');
                  }
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("الكود غير صحيح، تأكد منه وحاول ثانية", textAlign: TextAlign.center)));
                }
              }, 
              child: Text("تأكيد العملية", style: TextStyle(fontFamily: 'Cairo', color: Colors.white, fontSize: 13.sp))
            ),
          ],
        ),
      ),
    );
  }

  void _handleReturnFlow() async {
    bool? confirm = await showDialog(
      context: context, 
      builder: (c) => Directionality(
        textDirection: TextDirection.rtl, 
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text("بدء إجراءات المرتجع", style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)), 
          content: const Text("سيتم توجيهك الآن لموقع التاجر لاستعادة عهدتك. سيظهر كود تأكيد جديد لدى التاجر لاستلامه الأمانات.", style: TextStyle(fontFamily: 'Cairo')), 
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text("تراجع")), 
            TextButton(onPressed: () => Navigator.pop(c, true), child: const Text("نعم، مرتجع", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)))
          ]
        )
      )
    );

    if (confirm == true) {
      String generatedReturnCode = (1000 + Random().nextInt(8999)).toString();
      await FirebaseFirestore.instance.collection('specialRequests').doc(widget.orderId).update({
        'status': 'returning_to_seller',
        'returnVerificationCode': generatedReturnCode,
        'updatedAt': FieldValue.serverTimestamp()
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("تم تحويل الوجهة لموقع التاجر", textAlign: TextAlign.center), backgroundColor: Colors.redAccent));
    }
  }

  void _completeOrder() async {
    showDialog(context: context, barrierDismissible: false, builder: (c) => const Center(child: CircularProgressIndicator()));
    await _stopBackgroundTracking(); // إيقاف الخدمة فوراً عند انتهاء الرحلة
    try {
      await FirebaseFirestore.instance.collection('specialRequests').doc(widget.orderId).update({'status': 'delivered', 'completedAt': FieldValue.serverTimestamp()});
      if (mounted) { Navigator.pop(context); Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false); }
    } catch (e) { Navigator.pop(context); }
  }

  double _getSmartDistance(Map<String, dynamic> data, String status) {
    if (_currentLocation == null) return 0.0;
    GeoPoint target = (status == 'accepted' || status.contains('returning')) ? data['pickupLocation'] : data['dropoffLocation'];
    return Geolocator.distanceBetween(_currentLocation!.latitude, _currentLocation!.longitude, target.latitude, target.longitude) / 1000;
  }

  Widget _buildMap() {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('specialRequests').doc(widget.orderId).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        var data = snapshot.data!.data() as Map<String, dynamic>;
        String status = data['status'];
        GeoPoint pickup = data['pickupLocation'];
        GeoPoint dropoff = data['dropoffLocation'];
        
        return FlutterMap(
          mapController: _mapController,
          options: MapOptions(initialCenter: _currentLocation ?? LatLng(pickup.latitude, pickup.longitude), initialZoom: 15),
          children: [
            TileLayer(urlTemplate: 'https://api.mapbox.com/styles/v1/mapbox/streets-v12/tiles/{z}/{x}/{y}?access_token=$_mapboxToken'),
            if (_routePoints.isNotEmpty) PolylineLayer(polylines: [Polyline(points: _routePoints, color: Colors.blueAccent, strokeWidth: 6)]),
            MarkerLayer(markers: [
              if (_currentLocation != null) Marker(point: _currentLocation!, child: Icon(Icons.delivery_dining, color: Colors.blue[900], size: 45.sp)),
              Marker(point: LatLng(pickup.latitude, pickup.longitude), child: Icon(Icons.location_on, color: status.contains('returning') ? Colors.red : Colors.orange[900], size: 35.sp)),
              Marker(point: LatLng(dropoff.latitude, dropoff.longitude), child: Icon(Icons.person_pin_circle, color: Colors.black, size: 35.sp)),
            ]),
          ],
        );
      },
    );
  }

  Widget _mainButton(String label, Color color, VoidCallback onTap) => SizedBox(width: double.infinity, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: color, padding: EdgeInsets.symmetric(vertical: 2.2.h), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))), onPressed: onTap, child: Text(label, style: TextStyle(color: Colors.white, fontSize: 16.sp, fontWeight: FontWeight.bold, fontFamily: 'Cairo'))));

  Widget _buildCircleAction({required IconData icon, required String label, required Color color, required VoidCallback onTap}) => InkWell(onTap: onTap, child: Column(children: [Container(padding: EdgeInsets.all(12.sp), decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle), child: Icon(icon, color: color, size: 26.sp)), Text(label, style: TextStyle(color: color, fontSize: 12.sp, fontFamily: 'Cairo', fontWeight: FontWeight.bold))]));

  Widget _buildCustomAppBar() => SafeArea(child: Container(margin: EdgeInsets.all(10.sp), padding: EdgeInsets.symmetric(horizontal: 12.sp, vertical: 8.sp), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10)]), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [IconButton(onPressed: _handleBackAction, icon: const Icon(Icons.arrow_back_ios_new)), Text("تتبع الرحلة والعهدة", style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.bold, fontFamily: 'Cairo')), StreamBuilder<DocumentSnapshot>(stream: FirebaseFirestore.instance.collection('specialRequests').doc(widget.orderId).snapshots(), builder: (context, snap) { if (snap.hasData && snap.data!.exists && snap.data!['status'] == 'accepted') return IconButton(onPressed: _driverCancelOrder, icon: const Icon(Icons.cancel_outlined, color: Colors.red)); return SizedBox(width: 40.sp); })])));

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
    bool? confirm = await showDialog(context: context, builder: (c) => Directionality(textDirection: TextDirection.rtl, child: AlertDialog(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), title: const Text("اعتذار عن الرحلة", style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)), content: const Text("هل أنت متأكد؟ لن يتم خصم عهدة إذا لم تستلم البضاعة بعد.", style: TextStyle(fontFamily: 'Cairo')), actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text("تراجع")), TextButton(onPressed: () => Navigator.pop(c, true), child: const Text("تأكيد الاعتذار", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)))])));
    if (confirm == true) {
      await _stopBackgroundTracking(); // إيقاف الخدمة عند الاعتذار
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

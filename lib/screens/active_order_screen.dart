import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
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

class _ActiveOrderScreenState extends State<ActiveOrderScreen> with WidgetsBindingObserver {
  LatLng? _currentLocation;
  double _currentHeading = 0.0;
  List<LatLng> _routePoints = [];
  StreamSubscription<Position>? _positionStream;
  StreamSubscription<DocumentSnapshot>? _orderSubscription;

  GoogleMapController? _mapController;
  final String? _uid = FirebaseAuth.instance.currentUser?.uid;

  bool _isOrderStillActive = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _updateDriverStatus('busy');
    _configureBackgroundServiceOnly();
    _initInitialLocation();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _positionStream?.cancel();
    _orderSubscription?.cancel();
    _mapController?.dispose();
    if (!_isOrderStillActive) {
      _stopBackgroundTracking();
    }
    super.dispose();
  }

  Future<void> _updateDriverStatus(String status) async {
    if (_uid != null) {
      await FirebaseFirestore.instance.collection('freeDrivers').doc(_uid).update({
        'currentStatus': status,
        'lastSeen': FieldValue.serverTimestamp(),
        'activeOrderId': (status == 'online') ? "" : widget.orderId,
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_isOrderStillActive) return;
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _startBackgroundTracking();
    } else if (state == AppLifecycleState.resumed) {
      _stopBackgroundTracking();
    }
  }

  void _handleBackAction() async {
    final bool shouldExit = await showDialog(
          context: context,
          builder: (context) => Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Text("تنبيه النظام", style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 18.sp)),
              content: Text("هل تود العودة للقائمة الرئيسية؟ تتبع المسار سيستمر في الخلفية لضمان استرداد نقاط التأمين المخصصة عند الوصول.", style: TextStyle(fontFamily: 'Cairo', fontSize: 14.sp)),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: Text("بقاء في الرحلة", style: TextStyle(fontFamily: 'Cairo', color: Colors.grey, fontSize: 13.sp))),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.orange[900], shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                  onPressed: () {
                    _startBackgroundTracking();
                    Navigator.pop(context, true);
                  },
                  child: Text("الرئيسية", style: TextStyle(fontFamily: 'Cairo', color: Colors.white, fontSize: 13.sp)),
                )
              ],
            ),
          ),
        ) ??
        false;
    if (shouldExit && mounted) Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
  }

  Future<void> _configureBackgroundServiceOnly() async {
    if (_uid != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('driver_uid', _uid!);
      await prefs.setString('active_order_id', widget.orderId);
      final service = FlutterBackgroundService();
      await service.configure(
        androidConfiguration: AndroidConfiguration(
          onStart: onStart,
          autoStart: false,
          isForegroundMode: true,
          notificationChannelId: 'high_importance_channel',
          initialNotificationTitle: 'رابية أحلى: إدارة العهدة نشطة 🛡️',
          initialNotificationContent: 'جاري تحديث المسار لضمان استرداد نقاط التأمين',
          foregroundServiceNotificationId: 888,
        ),
        iosConfiguration: IosConfiguration(autoStart: false, onForeground: onStart),
      );
    }
  }

  Future<void> _startBackgroundTracking() async {
    final service = FlutterBackgroundService();
    bool isRunning = await service.isRunning();
    if (!isRunning && _isOrderStillActive) {
      service.startService();
    }
  }

  Future<void> _stopBackgroundTracking() async {
    final service = FlutterBackgroundService();
    bool isRunning = await service.isRunning();
    if (isRunning) {
      service.invoke("stopService");
    }
  }

  Future<void> _initInitialLocation() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.whileInUse) {
      bool? proceed = await _showBackgroundPermissionDialog();
      if (proceed == true) {
        permission = await Geolocator.requestPermission();
      }
    }
    if (permission == LocationPermission.always || permission == LocationPermission.whileInUse) {
      Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      if (mounted) {
        setState(() {
          _currentLocation = LatLng(position.latitude, position.longitude);
          _currentHeading = position.heading;
        });
        _setupDynamicTracking();
      }
    }
  }

  Future<bool?> _showBackgroundPermissionDialog() async {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          title: const Text("تأمين المسار والعهدة 🛡️", style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
          content: const Text("لضمان استحقاق نقاط التأمين وتحديث موقعك حتى لو أغلقت الشاشة، يرجى اختيار 'السماح طوال الوقت' في الخطوة القادمة."),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("فهمت، متابعة")),
          ],
        ),
      ),
    );
  }

  void _setupDynamicTracking() {
    _orderSubscription = FirebaseFirestore.instance.collection('specialRequests').doc(widget.orderId).snapshots().listen((orderSnap) async {
      if (!orderSnap.exists || !mounted) return;
      var data = orderSnap.data() as Map<String, dynamic>;
      String status = data['status'];
      if (status == 'cancelled_by_user_after_accept') {
        setState(() => _isOrderStillActive = false);
        await _stopBackgroundTracking();
        await _updateDriverStatus('online');
        if (mounted) _showCancellationDialog();
        return;
      }
      bool moneyLocked = data['moneyLocked'] ?? false;
      if (status == 'pending' && !moneyLocked) {
        _showSecurityError();
        return;
      }
      GeoPoint targetGeo = (status == 'accepted' || status.contains('returning')) ? data['pickupLocation'] : data['dropoffLocation'];
      _startSmartLiveTracking(LatLng(targetGeo.latitude, targetGeo.longitude));
    });
  }

  void _showCancellationDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text("تنبيه: تحديث الحالة ⚠️", style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, color: Colors.red)),
          content: const Text("تم تغيير حالة الطلب من قبل العميل. سيتم فحص مؤشرات المسار وضمان استرداد عهدتك آلياً في النظام."),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange[900]),
              onPressed: () => Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false),
              child: const Text("العودة للرئيسية", style: TextStyle(fontFamily: 'Cairo', color: Colors.white)),
            )
          ],
        ),
      ),
    );
  }

  void _showSecurityError() {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text("تأمين العهدة", style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
        content: const Text("جاري معالجة تأمين نقاط العهدة من رصيدك. في حال عدم كفاية الملحوظات سيتم إلغاء العملية تلقائياً.", style: TextStyle(fontFamily: 'Cairo')),
        actions: [TextButton(onPressed: () => Navigator.pushReplacementNamed(context, '/'), child: const Text("موافق"))],
      ),
    );
  }

  void _startSmartLiveTracking(LatLng target) {
    _positionStream?.cancel();
    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 10),
    ).listen((Position pos) {
      if (mounted) {
        setState(() {
          _currentLocation = LatLng(pos.latitude, pos.longitude);
          _currentHeading = pos.heading;
          _updateDriverLocationInFirestore(pos);
          _updateRoute(target);
          if (_mapController != null) {
            _mapController!.animateCamera(CameraUpdate.newCameraPosition(CameraPosition(target: _currentLocation!, zoom: 17, bearing: pos.heading, tilt: 45)));
          }
        });
      }
    });
  }

  void _updateDriverLocationInFirestore(Position pos) {
    if (_uid != null) {
      FirebaseFirestore.instance.collection('freeDrivers').doc(_uid!).update({'location': GeoPoint(pos.latitude, pos.longitude), 'lat': pos.latitude, 'lng': pos.longitude, 'heading': pos.heading, 'lastSeen': FieldValue.serverTimestamp()});
    }
  }

  List<LatLng> _decodePolyline(String encoded) {
    List<LatLng> points = [];
    int index = 0, len = encoded.length;
    int lat = 0, lng = 0;
    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat += dlat;
      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng += dlng;
      points.add(LatLng(lat / 1E5, lng / 1E5));
    }
    return points;
  }

  Future<void> _updateRoute(LatLng dest) async {
    if (_currentLocation == null) return;
    final String url = 'https://routes.googleapis.com/directions/v2:computeRoutes';
    final Map<String, dynamic> requestBody = {
      "origin": {
        "location": {
          "latLng": {"latitude": _currentLocation!.latitude, "longitude": _currentLocation!.longitude}
        }
      },
      "destination": {
        "location": {
          "latLng": {"latitude": dest.latitude, "longitude": dest.longitude}
        }
      },
      "travelMode": "DRIVE",
      "routingPreference": "TRAFFIC_AWARE",
    };
    try {
      final res = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'X-Goog-Api-Key': 'AIzaSyDkKyX-w0P1SBgOCmqjfZVMOGUiAiCbhLA',
          'X-Goog-FieldMask': 'routes.polyline.encodedPolyline'
        },
        body: json.encode(requestBody),
      );
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        if (data['routes'] != null && data['routes'].isNotEmpty) {
          String encodedPoints = data['routes'][0]['polyline']['encodedPolyline'];
          if (mounted) {
            setState(() => _routePoints = _decodePolyline(encodedPoints));
          }
        }
      } else {
        debugPrint("Routes API Error: ${res.body}");
      }
    } catch (e) {
      debugPrint("Network Error: $e");
    }
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

        // ✅ معالجة أرقام التليفونات لضمان عدم وجود قيم فارغة
        String phone1 = data['userPhone'] ?? "";
        String phone2 = data['customerPhone'] ?? phone1; // لو مفيش طرف تاني استخدم الأول

        return SafeArea(
          bottom: true,
          child: Container(
            margin: EdgeInsets.fromLTRB(10.sp, 0, 10.sp, 10.sp),
            padding: EdgeInsets.all(18.sp),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(25), boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 20)]),
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
                          Text(status.contains('returning') ? "🚨 العودة لنقطة العهدة" : (isAtPickup ? "نقطة حيازة العهدة" : "جهة تسليم الأمانات"),
                              style: TextStyle(color: status.contains('returning') ? Colors.red : Colors.grey[700], fontSize: 12.sp, fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                          Text(isAtPickup ? (data['pickupAddress'] ?? "الموقع") : (data['dropoffAddress'] ?? "العميل"), style: TextStyle(fontSize: 17.sp, fontWeight: FontWeight.w900, fontFamily: 'Cairo', height: 1.2), maxLines: 2, overflow: TextOverflow.ellipsis),
                          if (!isAtPickup)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text("هاتف المستلم: ${data['customerPhone'] ?? data['userPhone'] ?? 'غير متوفر'}", style: TextStyle(fontFamily: 'Cairo', fontSize: 11.sp, color: Colors.green[800], fontWeight: FontWeight.bold)),
                            ),
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
                    Expanded(child: _phoneButton(phone: phone1, label: isMerchant ? "اتصال بالتاجر" : "اتصال بالعميل", color: Colors.orange[900]!)),
                    if (isMerchant || data['customerPhone'] != null) ...[
                      SizedBox(width: 10),
                      Expanded(child: _phoneButton(phone: phone2, label: "اتصال بالمستلم", color: Colors.green[800]!)),
                    ]
                  ],
                ),
                const Divider(height: 30, thickness: 1),
                if (status == 'accepted')
                  moneyLocked
                      ? _mainButton(isMerchant ? "تأكيد استلام العهدة 📦" : "تأكيد بدء المهمة 📦", Colors.orange[900]!, () => _showProfessionalOTP(data['verificationCode'], status, isMerchant))
                      : Text("جاري معالجة تأمين العهدة...", style: TextStyle(fontFamily: 'Cairo', fontSize: 15.sp, color: Colors.orange[900], fontWeight: FontWeight.bold))
                else if (status == 'picked_up')
                  isMerchant
                      ? Row(children: [
                          Expanded(child: _mainButton("إرجاع العهدة ❌", Colors.red[800]!, () => _handleReturnFlow())),
                          const SizedBox(width: 12),
                          Expanded(child: _mainButton("إخلاء طرف (تسليم) ✅", Colors.green[800]!, () => _completeOrder(data))),
                        ])
                      : _mainButton("تأكيد تسليم الأمانات ✅", Colors.green[800]!, () => _completeOrder(data))
                else if (status.contains('returning'))
                  Column(
                    children: [
                      Text("يجب العودة للمصدر لإخلاء العهدة", style: TextStyle(fontFamily: 'Cairo', fontSize: 13.sp, color: Colors.red[900], fontWeight: FontWeight.w900)),
                      SizedBox(height: 10),
                      _mainButton("تأكيد الإخلاء العكسي 🔄", Colors.blueGrey[800]!, () => _showProfessionalOTP(data['returnVerificationCode'] ?? data['verificationCode'], status, isMerchant)),
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
      context: context,
      barrierDismissible: false,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(isReturning ? "إخلاء العهدة" : "تأكيد استلام العهدة", style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 16.sp)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(isReturning ? "أدخل كود التحقق لاسترداد نقاط التأمين فوراً." : "بإدخال الكود، أنت تؤكد استلام الشحنة في عهدتك وسيتم تخصيص نقاط أمان من حسابك لضمان النقل.", style: TextStyle(fontFamily: 'Cairo', fontSize: 13.sp)),
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
                    await _finishReturnProcess();
                  } else {
                    _updateStatus('picked_up');
                  }
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("الكود غير صحيح، حاول ثانية", textAlign: TextAlign.center)));
                }
              },
              child: Text("تأكيد", style: TextStyle(fontFamily: 'Cairo', color: Colors.white, fontSize: 13.sp)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _finishReturnProcess() async {
    setState(() => _isOrderStillActive = false);
    showDialog(context: context, barrierDismissible: false, builder: (c) => const Center(child: CircularProgressIndicator()));
    try {
      await FirebaseFirestore.instance.collection('specialRequests').doc(widget.orderId).update({
        'status': 'returned_successfully',
        'updatedAt': FieldValue.serverTimestamp(),
      });
      await _updateDriverStatus('online');
      await _stopBackgroundTracking();
      if (mounted) {
        Navigator.pop(context);
        Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
    }
  }

  void _handleReturnFlow() async {
    bool? confirm = await showDialog(
        context: context,
        builder: (c) => Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), title: const Text("بدء الإجراء العكسي", style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)), content: const Text("سيتم توجيهك الآن لنقطة البداية لاسترداد العهدة وتأمين الحالة.", style: TextStyle(fontFamily: 'Cairo')), actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text("تراجع")),
              TextButton(onPressed: () => Navigator.pop(c, true), child: const Text("تأكيد", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)))
            ])));
    if (confirm == true) {
      String generatedReturnCode = (1000 + Random().nextInt(8999)).toString();
      await FirebaseFirestore.instance.collection('specialRequests').doc(widget.orderId).update({'status': 'returning_to_seller', 'returnVerificationCode': generatedReturnCode, 'updatedAt': FieldValue.serverTimestamp()});
    }
  }

  // ✅ الدالة المحدثة للتحصيل بناءً على لقطات الشاشة (Firebase)
  void _completeOrder(Map<String, dynamic> data) async {
    bool isMerchant = data['requestSource'] == 'retailer';
    
    // أجرة المندوب من حقل totalPrice
    double deliveryFee = double.tryParse(data['totalPrice']?.toString() ?? '0') ?? 0.0;
    
    // قيمة العهدة للتاجر فقط
    double goodsValue = isMerchant 
        ? (double.tryParse(data['insurance_points']?.toString() ?? '0') ?? 0.0) 
        : 0.0;
        
    // الإجمالي المطلوب كاش (orderFinalAmount)
    double totalToCollect = isMerchant 
        ? (double.tryParse(data['orderFinalAmount']?.toString() ?? '0') ?? (goodsValue + deliveryFee))
        : deliveryFee;

    bool? confirm = await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(isMerchant ? "تأكيد العهدة والتحصيل 💰" : "تأكيد تسليم الأمانات ✅", style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(isMerchant ? "إخلاء طرف من عهدة بقيمة:" : "تحصيل أجرة النقل:", style: TextStyle(fontFamily: 'Cairo')),
              const SizedBox(height: 15),
              if (isMerchant && goodsValue > 0)
                _amountRow("قيمة البضاعة:", "$goodsValue ج.م"),
              _amountRow("أجرة المندوب:", "$deliveryFee ج.م"),
              const Divider(),
              _amountRow("المطلوب كاش:", "$totalToCollect ج.م", isTotal: true),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("إلغاء")),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green[800]),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text("تم التحصيل ✅", style: TextStyle(fontFamily: 'Cairo', color: Colors.white)),
            ),
          ],
        ),
      ),
    );

    if (confirm != true) return;

    setState(() => _isOrderStillActive = false);
    showDialog(context: context, barrierDismissible: false, builder: (c) => const Center(child: CircularProgressIndicator()));
    try {
      await FirebaseFirestore.instance.collection('specialRequests').doc(widget.orderId).update({'status': 'delivered', 'completedAt': FieldValue.serverTimestamp(), 'updatedAt': FieldValue.serverTimestamp()});
      await _updateDriverStatus('online');
      await _stopBackgroundTracking();
      if (mounted) {
        Navigator.pop(context);
        Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
    }
  }

  Widget _amountRow(String label, String value, {bool isTotal = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontFamily: 'Cairo', fontSize: isTotal ? 13.sp : 11.sp, fontWeight: isTotal ? FontWeight.w900 : FontWeight.normal)),
          Text(value, style: TextStyle(fontFamily: 'Cairo', fontSize: isTotal ? 14.sp : 12.sp, fontWeight: FontWeight.w900, color: isTotal ? Colors.green[900] : Colors.black87)),
        ],
      ),
    );
  }

  Widget _phoneButton({required String? phone, required String label, required Color color}) {
    if (phone == null || phone.isEmpty) return const SizedBox();
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(backgroundColor: color, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
      onPressed: () => launchUrl(Uri.parse("tel:$phone")),
      icon: Icon(Icons.phone_in_talk, color: Colors.white, size: 14.sp),
      label: Text(label, style: TextStyle(fontFamily: 'Cairo', color: Colors.white, fontSize: 11.sp, fontWeight: FontWeight.bold)),
    );
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
        return GoogleMap(
          initialCameraPosition: CameraPosition(
            target: _currentLocation ?? LatLng(pickup.latitude, pickup.longitude),
            zoom: 15,
          ),
          onMapCreated: (controller) => _mapController = controller,
          myLocationEnabled: false,
          zoomControlsEnabled: false,
          mapToolbarEnabled: false,
          polylines: _routePoints.isNotEmpty
              ? {
                  Polyline(
                    polylineId: const PolylineId("route"),
                    points: _routePoints,
                    color: const Color(0xFF1A73E8),
                    width: 6,
                    geodesic: true,
                  )
                }
              : {},
          markers: {
            if (_currentLocation != null) Marker(markerId: const MarkerId("driver"), position: _currentLocation!, rotation: _currentHeading, anchor: const Offset(0.5, 0.5), icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure), infoWindow: const InfoWindow(title: "موقعي الحالي")),
            Marker(markerId: const MarkerId("pickup"), position: LatLng(pickup.latitude, pickup.longitude), icon: BitmapDescriptor.defaultMarkerWithHue(status.contains('returning') ? BitmapDescriptor.hueRed : BitmapDescriptor.hueOrange), infoWindow: const InfoWindow(title: "نقطة العهدة")),
            Marker(markerId: const MarkerId("dropoff"), position: LatLng(dropoff.latitude, dropoff.longitude), icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet), infoWindow: const InfoWindow(title: "نقطة التسليم")),
          },
        );
      },
    );
  }

  Widget _mainButton(String label, Color color, VoidCallback onTap) => SizedBox(width: double.infinity, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: color, padding: EdgeInsets.symmetric(vertical: 2.2.h), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))), onPressed: onTap, child: Text(label, style: TextStyle(color: Colors.white, fontSize: 16.sp, fontWeight: FontWeight.bold, fontFamily: 'Cairo'))));
  Widget _buildCircleAction({required IconData icon, required String label, required Color color, required VoidCallback onTap}) => InkWell(onTap: onTap, child: Column(children: [Container(padding: EdgeInsets.all(12.sp), decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle), child: Icon(icon, color: color, size: 26.sp)), Text(label, style: TextStyle(color: color, fontSize: 12.sp, fontFamily: 'Cairo', fontWeight: FontWeight.bold))]));
  Widget _buildCustomAppBar() => SafeArea(child: Container(margin: EdgeInsets.all(10.sp), padding: EdgeInsets.symmetric(horizontal: 12.sp, vertical: 8.sp), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10)]), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [IconButton(onPressed: _handleBackAction, icon: const Icon(Icons.arrow_back_ios_new)), Text("إدارة المسار والعهدة", style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.bold, fontFamily: 'Cairo')), StreamBuilder<DocumentSnapshot>(stream: FirebaseFirestore.instance.collection('specialRequests').doc(widget.orderId).snapshots(), builder: (context, snap) { if (snap.hasData && snap.data!.exists && snap.data!['status'] == 'accepted') return IconButton(onPressed: _driverCancelOrder, icon: const Icon(Icons.cancel_outlined, color: Colors.red)); return SizedBox(width: 40.sp); })])));
  void _updateStatus(String nextStatus) async => await FirebaseFirestore.instance.collection('specialRequests').doc(widget.orderId).update({'status': nextStatus, 'updatedAt': FieldValue.serverTimestamp()});
  Future<void> _launchGoogleMaps(GeoPoint point) async {
    final url = 'google.navigation:q=${point.latitude},${point.longitude}';
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _driverCancelOrder() async {
    bool? confirm = await showDialog(context: context, builder: (c) => Directionality(textDirection: TextDirection.rtl, child: AlertDialog(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), title: const Text("اعتذار عن المهمة", style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)), content: const Text("هل أنت متأكد؟ لن يتم خصم نقاط تأمين إذا لم يتم استلام العهدة بعد.", style: TextStyle(fontFamily: 'Cairo')), actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text("تراجع")), TextButton(onPressed: () => Navigator.pop(c, true), child: const Text("تأكيد الاعتذار", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)))])));
    if (confirm == true) {
      setState(() => _isOrderStillActive = false);
      await _stopBackgroundTracking();
      await FirebaseFirestore.instance.collection('specialRequests').doc(widget.orderId).update({'status': 'driver_cancelled_reseeking', 'lastDriverId': _uid, 'driverId': FieldValue.delete()});
      await _updateDriverStatus('online');
      if (mounted) Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _handleBackAction();
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
}

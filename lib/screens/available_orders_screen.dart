import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:sizer/sizer.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'active_order_screen.dart';

class AvailableOrdersScreen extends StatefulWidget {
  final String vehicleType;
  const AvailableOrdersScreen({super.key, required this.vehicleType});

  @override
  State<AvailableOrdersScreen> createState() => _AvailableOrdersScreenState();
}

class _AvailableOrdersScreenState extends State<AvailableOrdersScreen> {
  Position? _myCurrentLocation;
  bool _isGettingLocation = true;
  final String? _uid = FirebaseAuth.instance.currentUser?.uid;
  GoogleMapController? _mapController;
  Timer? _uiTimer;

  String get _heatmapDoc => widget.vehicleType;

  @override
  void initState() {
    super.initState();
    _updateDriverStatus('browsing_radar');
    _updateLocationSnapshot();
    _uiTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _updateDriverStatus('online');
    _uiTimer?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _updateDriverStatus(String status) async {
    if (_uid != null) {
      try {
        await FirebaseFirestore.instance.collection('freeDrivers').doc(_uid).update({
          'currentStatus': status,
          'lastSeen': FieldValue.serverTimestamp(),
        });
      } catch (e) {
        debugPrint("❌ Status Error: $e");
      }
    }
  }

  Future<void> _updateLocationSnapshot() async {
    try {
      Position pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      if (mounted) {
        setState(() {
          _myCurrentLocation = pos;
          _isGettingLocation = false;
        });
        if (_uid != null) {
          await FirebaseFirestore.instance.collection('freeDrivers').doc(_uid).update({
            'lat': pos.latitude,
            'lng': pos.longitude,
            'lastLocationUpdate': FieldValue.serverTimestamp(),
          });
        }
        _mapController?.animateCamera(CameraUpdate.newLatLng(LatLng(pos.latitude, pos.longitude)));
      }
    } catch (e) {
      if (mounted) setState(() => _isGettingLocation = false);
    }
  }

  // ✅ تحسين حساب المسافة ليكون مؤمناً ضد كافة أنواع البيانات (GeoPoint, List, Map)
  double _calculateDistance(dynamic pickup, dynamic dropoff) {
    if (_myCurrentLocation == null) return 0.0;
    double pLat = 0.0, pLng = 0.0, dLat = 0.0, dLng = 0.0;

    try {
      // معالجة موقع الاستلام
      if (pickup is GeoPoint) {
        pLat = pickup.latitude; pLng = pickup.longitude;
      } else if (pickup is List || pickup is Iterable) {
        pLat = pickup[0]; pLng = pickup[1];
      } else {
        pLat = pickup['lat'] ?? 0.0; pLng = pickup['lng'] ?? 0.0;
      }

      // معالجة موقع التسليم
      if (dropoff is GeoPoint) {
        dLat = dropoff.latitude; dLng = dropoff.longitude;
      } else if (dropoff is List || dropoff is Iterable) {
        dLat = dropoff[0]; dLng = dropoff[1];
      } else {
        dLat = dropoff['lat'] ?? 0.0; dLng = dropoff['lng'] ?? 0.0;
      }
    } catch (e) {
      return 0.0;
    }

    double toPickup = Geolocator.distanceBetween(_myCurrentLocation!.latitude, _myCurrentLocation!.longitude, pLat, pLng);
    double toDropoff = Geolocator.distanceBetween(pLat, pLng, dLat, dLng);
    return (toPickup + toDropoff) / 1000;
  }

  Future<void> _acceptOrder(String orderId) async {
    try {
      showDialog(
          context: context,
          barrierDismissible: false,
          builder: (c) => const Center(child: CircularProgressIndicator(color: Colors.orange)));

      DocumentSnapshot p = await FirebaseFirestore.instance.collection('freeDrivers').doc(_uid).get();
      String name = p.exists ? (p.get('fullname') ?? "مندوب") : "مندوب";

      await FirebaseFirestore.instance.runTransaction((tx) async {
        DocumentReference oRef = FirebaseFirestore.instance.collection('specialRequests').doc(orderId);
        DocumentReference dRef = FirebaseFirestore.instance.collection('freeDrivers').doc(_uid);
        DocumentSnapshot oSnap = await tx.get(oRef);
        if (oSnap.exists && oSnap.get('status') == 'pending') {
          tx.update(oRef, {
            'status': 'accepted',
            'driverId': _uid,
            'driverName': name,
            'acceptedAt': FieldValue.serverTimestamp(),
            'moneyLocked': false,
            'serverNote': "تأكيد العهدة: جاري معالجة الطلب...",
          });
          tx.update(dRef, {'currentStatus': 'busy', 'activeOrderId': orderId});
        } else {
          throw "الطلب لم يعد متاحاً";
        }
      });
      if (mounted) {
        Navigator.pop(context);
        Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (c) => ActiveOrderScreen(orderId: orderId)), (r) => false);
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString(), style: const TextStyle(fontFamily: 'Cairo')), backgroundColor: Colors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isGettingLocation) return const Scaffold(body: Center(child: CircularProgressIndicator(color: Colors.orange)));
    return Scaffold(
      body: Stack(
        children: [
          _buildHeatmapLayer(),
          _buildTopOverlay(),
          _buildDraggableSheet(),
        ],
      ),
    );
  }

  Widget _buildHeatmapLayer() {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('app_settings').doc(_heatmapDoc).snapshots(),
      builder: (context, snapshot) {
        Set<Marker> markers = {};
        if (snapshot.hasData && snapshot.data!.exists) {
          List points = snapshot.data!['points'] ?? [];
          markers = points.map((p) => Marker(
            markerId: MarkerId("heat_${p['lat']}"),
            position: LatLng(p['lat'], p['lng']),
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
          )).toSet();
        }
        return GoogleMap(
          initialCameraPosition: CameraPosition(target: LatLng(_myCurrentLocation?.latitude ?? 31.2, _myCurrentLocation?.longitude ?? 29.9), zoom: 12),
          onMapCreated: (c) => _mapController = c,
          markers: markers,
          myLocationEnabled: true,
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          mapToolbarEnabled: false,
          compassEnabled: false,
        );
      },
    );
  }

  Widget _buildTopOverlay() {
    return Positioned(
      top: 6.h, left: 4.w, right: 4.w,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: const CircleAvatar(backgroundColor: Colors.white, child: Icon(Icons.arrow_back, color: Colors.black)),
          ),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 5.w, vertical: 1.2.h),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(30), boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 8)]),
            child: Row(
              children: [
                const Icon(Icons.radar, color: Colors.orange, size: 18),
                const SizedBox(width: 8),
                Text("رادار رابية أحلى اللحظي", style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 12.sp)),
              ],
            ),
          ),
          GestureDetector(
            onTap: _updateLocationSnapshot,
            child: const CircleAvatar(backgroundColor: Colors.white, child: Icon(Icons.my_location, color: Colors.blue)),
          ),
        ],
      ),
    );
  }

  Widget _buildDraggableSheet() {
    return SafeArea(
      bottom: true,
      child: DraggableScrollableSheet(
        initialChildSize: 0.35, minChildSize: 0.18, maxChildSize: 0.95,
        builder: (context, scrollController) {
          return Container(
            decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(30)), boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 15)]),
            child: Column(
              children: [
                _buildSheetHandle(),
                Expanded(
                  child: StreamBuilder<DocumentSnapshot>(
                    stream: FirebaseFirestore.instance.collection('freeDrivers').doc(_uid).snapshots(),
                    builder: (context, dSnap) {
                      double wallet = double.tryParse(dSnap.data?['walletBalance']?.toString() ?? '0') ?? 0.0;
                      return _buildOrdersList(scrollController, wallet);
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSheetHandle() {
    return Column(
      children: [
        const SizedBox(height: 12),
        Container(width: 45, height: 5, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10))),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildOrdersList(ScrollController sc, double wallet) {
    String cleanType = widget.vehicleType.replaceAll('Config', '');
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('specialRequests').where('status', isEqualTo: 'pending').where('vehicleType', isEqualTo: cleanType).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text("خطأ في الاتصال بالرادار", style: TextStyle(fontFamily: 'Cairo')));
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

        final nearby = snapshot.data!.docs.where((doc) {
          try {
            // ✅ معالجة ذكية ومؤمنة لموقع الاستلام لضمان عدم الكراش مهما اختلف نوع البيانات
            dynamic p = doc['pickupLocation'];
            double lat, lng;
            if (p is GeoPoint) {
              lat = p.latitude; lng = p.longitude;
            } else if (p is List || p is Iterable) {
              lat = p[0]; lng = p[1];
            } else {
              lat = p['lat'] ?? 0.0; lng = p['lng'] ?? 0.0;
            }
            return Geolocator.distanceBetween(_myCurrentLocation!.latitude, _myCurrentLocation!.longitude, lat, lng) <= 15000;
          } catch (e) {
            return false;
          }
        }).toList();

        if (nearby.isEmpty) {
          return ListView(controller: sc, children: [
            SizedBox(height: 5.h),
            Icon(Icons.search_off, size: 50.sp, color: Colors.grey[300]),
            Center(child: Text("لا توجد طلبات في محيط 15 كم", style: TextStyle(fontFamily: 'Cairo', color: Colors.grey, fontSize: 13.sp))),
          ]);
        }
        return ListView.builder(
          controller: sc, padding: EdgeInsets.symmetric(horizontal: 4.w),
          itemCount: nearby.length,
          itemBuilder: (context, index) => _buildOrderCard(nearby[index], wallet),
        );
      },
    );
  }

  Widget _buildOrderCard(DocumentSnapshot doc, double walletBalance) {
    var data = doc.data() as Map<String, dynamic>;
    double net = double.tryParse(data['driverNet']?.toString() ?? '0') ?? 0.0;
    double orderAmt = double.tryParse(data['orderFinalAmount']?.toString() ?? '0') ?? 0.0;
    double insurance = (orderAmt > 0) ? (orderAmt - net) : 0.0;
    if (insurance < 0) insurance = 0;
    bool canAccept = walletBalance >= insurance;
    bool isMerchant = data['requestSource'] == 'retailer';

    return Container(
      margin: EdgeInsets.only(bottom: 2.h),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.grey[100]!), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10)]),
      child: Column(
        children: [
          Container(
            padding: EdgeInsets.all(3.w),
            decoration: BoxDecoration(
                gradient: isMerchant ? const LinearGradient(colors: [Color(0xFFFFD700), Color(0xFFFFA000)]) : LinearGradient(colors: [Colors.blueGrey[800]!, Colors.blueGrey[900]!]),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20))),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    isMerchant
                        ? FaIcon(FontAwesomeIcons.solidStar, color: const Color(0xFF5D4037), size: 16.sp)
                        : Icon(Icons.delivery_dining, color: Colors.white, size: 17.sp),
                    SizedBox(width: 2.w),
                    Text("$net ج.م صافي", style: TextStyle(color: isMerchant ? const Color(0xFF5D4037) : Colors.white, fontWeight: FontWeight.bold, fontSize: 14.sp, fontFamily: 'Cairo')),
                  ],
                ),
                Text(isMerchant ? "طلب من تاجر" : "طلب مستهلك", style: TextStyle(color: isMerchant ? const Color(0xFF5D4037) : Colors.white70, fontSize: 11.sp, fontFamily: 'Cairo')),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.all(4.w),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _tag(Icons.security, "${insurance.toStringAsFixed(0)} عهدة", Colors.red),
                    _tag(Icons.map, "${_calculateDistance(data['pickupLocation'], data['dropoffLocation']).toStringAsFixed(1)} كم", Colors.blue),
                  ],
                ),
                const Divider(height: 25),
                _route(Icons.circle, "من: ${data['pickupAddress'] ?? 'الموقع'}", Colors.orange),
                _route(Icons.location_on, "إلى: ${data['dropoffAddress'] ?? 'العميل'}", Colors.red),
                const SizedBox(height: 15),
                SizedBox(
                  width: double.infinity, height: 7.h,
                  child: ElevatedButton(
                    onPressed: canAccept ? () => _acceptOrder(doc.id) : null,
                    style: ElevatedButton.styleFrom(backgroundColor: canAccept ? (isMerchant ? const Color(0xFF5D4037) : Colors.green[700]) : Colors.grey, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    child: Text(canAccept ? "تأكيد العهدة وقبول الطلب" : "رصيد الكاش غير كافٍ", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14.sp, fontFamily: 'Cairo')),
                  ),
                )
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _tag(IconData i, String l, Color c) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: c.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
      child: Row(children: [Icon(i, size: 16, color: c), const SizedBox(width: 6), Text(l, style: TextStyle(color: c, fontSize: 11.sp, fontWeight: FontWeight.bold, fontFamily: 'Cairo'))]));

  Widget _route(IconData i, String t, Color c) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(children: [Icon(i, size: 18, color: c), const SizedBox(width: 12), Expanded(child: Text(t, style: TextStyle(fontSize: 12.sp, color: Colors.black87, fontFamily: 'Cairo'), maxLines: 2, overflow: TextOverflow.ellipsis))]));
}

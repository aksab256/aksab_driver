import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:sizer/sizer.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

class TodayTasksScreen extends StatefulWidget {
  const TodayTasksScreen({super.key});

  @override
  State<TodayTasksScreen> createState() => _TodayTasksScreenState();
}

class _TodayTasksScreenState extends State<TodayTasksScreen> {
  final String _mapboxToken = 'pk.eyJ1IjoiYW1yc2hpcGwiLCJhIjoiY21lajRweGdjMDB0eDJsczdiemdzdXV6biJ9.E--si9vOB93NGcAq7uVgGw';
  final String _lambdaUrl = 'https://2soi345n94.execute-api.us-east-1.amazonaws.com/Prode/';

  String? _repCode;
  bool _isLoadingRep = true;
  LatLng? _currentPosition;

  @override
  void initState() {
    super.initState();
    _loadRepCode();
    _determinePosition();
  }

  // جلب الموقع الحي للمندوب
  Future<void> _determinePosition() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }
    
    Position position = await Geolocator.getCurrentPosition();
    if (mounted) {
      setState(() {
        _currentPosition = LatLng(position.latitude, position.longitude);
      });
    }
  }

  Future<void> _loadRepCode() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final doc = await FirebaseFirestore.instance.collection('deliveryReps').doc(uid).get();
    if (doc.exists) {
      if (mounted) {
        setState(() {
          _repCode = doc.data()?['repCode'];
          _isLoadingRep = false;
        });
      }
    }
  }

  // رسم المسار باستخدام Mapbox API
  Future<List<LatLng>> _getRoutePolyline(LatLng start, LatLng end) async {
    final url = 'https://api.mapbox.com/directions/v5/mapbox/driving/${start.longitude},${start.latitude};${end.longitude},${end.latitude}?geometries=geojson&access_token=$_mapboxToken';
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List coords = data['routes'][0]['geometry']['coordinates'];
        return coords.map((c) => LatLng(c[1].toDouble(), c[0].toDouble())).toList();
      }
    } catch (e) {
      debugPrint("Route Error: $e");
    }
    return [];
  }

  void _showRouteMap(Map customerLoc, String address) async {
    LatLng customerPos = LatLng(customerLoc['lat'], customerLoc['lng']);
    LatLng startPos = _currentPosition ?? const LatLng(31.2001, 29.9187);

    List<LatLng> routePoints = await _getRoutePolyline(startPos, customerPos);

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Container(
        height: 85.h,
        padding: EdgeInsets.all(10.sp),
        child: Column(
          children: [
            Text("مسار التوصيل", style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold)),
            SizedBox(height: 10.sp),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(15),
                child: FlutterMap(
                  options: MapOptions(initialCenter: startPos, initialZoom: 13),
                  children: [
                    TileLayer(urlTemplate: 'https://api.mapbox.com/styles/v1/mapbox/streets-v11/tiles/{z}/{x}/{y}?access_token=$_mapboxToken'),
                    if (routePoints.isNotEmpty)
                      PolylineLayer(polylines: [Polyline(points: routePoints, color: Colors.blue, strokeWidth: 4)]),
                    MarkerLayer(markers: [
                      Marker(point: startPos, child: const Icon(Icons.my_location, color: Colors.blue, size: 30)),
                      Marker(point: customerPos, child: const Icon(Icons.location_on, color: Colors.red, size: 35)),
                    ]),
                  ],
                ),
              ),
            ),
            _buildMapActions(customerPos, address),
          ],
        ),
      ),
    );
  }

  Widget _buildMapActions(LatLng dest, String address) {
    return Container(
      padding: EdgeInsets.all(12.sp),
      child: Column(
        children: [
          Text("العنوان: $address", style: TextStyle(fontSize: 11.sp), textAlign: TextAlign.center),
          SizedBox(height: 10.sp),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () async {
                    final url = 'https://www.google.com/maps/dir/?api=1&destination=${dest.latitude},${dest.longitude}';
                    if (await canLaunchUrl(Uri.parse(url))) await launchUrl(Uri.parse(url));
                  },
                  icon: const Icon(Icons.navigation, color: Colors.white),
                  label: const Text("توجيه خارجي", style: TextStyle(color: Colors.white)),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green[700]),
                ),
              ),
              SizedBox(width: 3.w),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.grey[800]),
                  child: const Text("إغلاق", style: TextStyle(color: Colors.white)),
                ),
              ),
            ],
          )
        ],
      ),
    );
  }

  // دالة عرض الفاتورة ومشاركة الواتساب
  void _showOrderDetails(Map<String, dynamic> data) {
    List products = data['products'] ?? [];
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Container(
        height: 75.h,
        padding: EdgeInsets.all(15.sp),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("فاتورة العميل", style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.bold)),
            const Divider(),
            _invoiceRow("العميل:", data['buyer']['name']),
            _invoiceRow("الهاتف:", data['buyer']['phone'] ?? "غير متوفر"),
            const Divider(),
            Expanded(
              child: ListView.builder(
                itemCount: products.length,
                itemBuilder: (context, index) {
                  var item = products[index];
                  return ListTile(
                    title: Text(item['name'] ?? "منتج"),
                    subtitle: Text("${item['quantity']} قطعة × ${item['price']} ج.م"),
                    trailing: Text("${(item['quantity'] * item['price']).toStringAsFixed(2)} ج.م"),
                  );
                },
              ),
            ),
            const Divider(thickness: 2),
            _invoiceRow("الإجمالي النهائي:", "${data['total']} ج.م", isBold: true),
            SizedBox(height: 2.h),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _shareToWhatsApp(data),
                    icon: const Icon(Icons.share, color: Colors.white),
                    label: const Text("ارسال واتساب", style: TextStyle(color: Colors.white)),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green[600]),
                  ),
                ),
                SizedBox(width: 2.w),
                Expanded(
                  child: OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text("إغلاق")),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }

  void _shareToWhatsApp(Map<String, dynamic> data) async {
    String phone = data['buyer']['phone'] ?? "";
    String message = "مرحباً ${data['buyer']['name']}\nمعك مندوب شركة أكسب. تفاصيل طلبك هي:\n";
    for (var item in data['products']) {
      message += "- ${item['name']} (عدد ${item['quantity']})\n";
    }
    message += "\nالإجمالي المطلوب: ${data['total']} ج.م";
    
    final url = "https://wa.me/$phone?text=${Uri.encodeComponent(message)}";
    if (await canLaunchUrl(Uri.parse(url))) await launchUrl(Uri.parse(url));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: AppBar(title: const Text("مهام اليوم"), centerTitle: true, backgroundColor: const Color(0xFF007BFF)),
      body: _isLoadingRep
          ? const Center(child: CircularProgressIndicator())
          : StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('waitingdelivery').where('deliveryRepId', isEqualTo: _repCode).snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                if (snapshot.data!.docs.isEmpty) return const Center(child: Text("لا توجد مهام حالياً"));
                return ListView.builder(
                  padding: EdgeInsets.all(10.sp),
                  itemCount: snapshot.data!.docs.length,
                  itemBuilder: (context, index) {
                    var data = snapshot.data!.docs[index].data() as Map<String, dynamic>;
                    var docId = snapshot.data!.docs[index].id;
                    return _buildTaskCard(docId, data);
                  },
                );
              },
            ),
    );
  }

  Widget _buildTaskCard(String docId, Map<String, dynamic> data) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: EdgeInsets.only(bottom: 12.sp),
      child: InkWell(
        onTap: () => _showOrderDetails(data),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: EdgeInsets.all(12.sp),
          child: Column(
            children: [
              _rowInfo("العميل", data['buyer']['name'] ?? "-"),
              _rowInfo("الإجمالي", "${data['total']} ج.م", isTotal: true),
              const Divider(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _actionBtn(Icons.map, "المسار", Colors.blue[900]!, () => _showRouteMap(data['buyer']['location'], data['buyer']['address'])),
                  _actionBtn(Icons.check_circle, "تسليم", Colors.green, () => _handleStatus(docId, data, 'delivered')),
                  _actionBtn(Icons.cancel, "فشل", Colors.red, () => _handleStatus(docId, data, 'failed')),
                ],
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _rowInfo(String label, String value, {bool isTotal = false}) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4.sp),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey[600])),
          Text(value, style: TextStyle(fontWeight: FontWeight.bold, color: isTotal ? Colors.blue : Colors.black87)),
        ],
      ),
    );
  }

  Widget _invoiceRow(String label, String value, {bool isBold = false}) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4.sp),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(value, style: TextStyle(fontWeight: isBold ? FontWeight.bold : FontWeight.normal)),
        ],
      ),
    );
  }

  Widget _actionBtn(IconData icon, String label, Color color, VoidCallback onTap) {
    return TextButton.icon(onPressed: onTap, icon: Icon(icon, color: color, size: 16.sp), label: Text(label, style: TextStyle(color: color, fontSize: 10.sp, fontWeight: FontWeight.bold)));
  }

  Future<void> _handleStatus(String docId, Map<String, dynamic> data, String status) async {
    String targetColl = (status == 'delivered') ? 'deliveredorders' : 'falseorder';
    try {
      await FirebaseFirestore.instance.collection(targetColl).doc(docId).set({...data, 'status': status, 'finishedAt': FieldValue.serverTimestamp(), 'handledByRepId': _repCode});
      await FirebaseFirestore.instance.collection('orders').doc(docId).update({'status': status, 'deliveryFinishedAt': FieldValue.serverTimestamp()});
      await FirebaseFirestore.instance.collection('waitingdelivery').doc(docId).delete();
      _sendNotification(status, data['buyer']?['name'] ?? "عميل");
    } catch (e) {
      debugPrint("Update Error: $e");
    }
  }

  Future<void> _sendNotification(String status, String customerName) async {
    try {
      await http.post(Uri.parse(_lambdaUrl), headers: {"Content-Type": "application/json"}, body: jsonEncode({"targetArn": "arn:aws:sns:us-east-1:32660558108:AksabNotification", "title": status == 'delivered' ? "✅ تم التسليم" : "❌ فشل التسليم", "message": "المندوب حدد حالة طلب $customerName"}));
    } catch (e) {
      debugPrint("Notification Error: $e");
    }
  }
}


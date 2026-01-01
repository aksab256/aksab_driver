import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:latlong2/latlong.dart';
import 'package:sizer/sizer.dart';

class DeliveryManagementScreen extends StatefulWidget {
  const DeliveryManagementScreen({super.key});

  @override
  State<DeliveryManagementScreen> createState() => _DeliveryManagementScreenState();
}

class _DeliveryManagementScreenState extends State<DeliveryManagementScreen> {
  String? role;
  List<String> myAreas = [];
  Map<String, dynamic>? geoJsonData;
  List<Map<String, dynamic>> myReps = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _initializeData();
  }

  // دالة لإظهار تنبيه احترافي (Custom Toast)
  void _showSuccessOverlay(String message) {
    OverlayEntry overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: 45.h,
        left: 10.w,
        right: 10.w,
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: EdgeInsets.symmetric(vertical: 2.h, horizontal: 5.w),
            decoration: BoxDecoration(
              color: const Color(0xFF2F3542).withOpacity(0.9),
              borderRadius: BorderRadius.circular(15),
              boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10)],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle, color: Colors.green, size: 40),
                SizedBox(height: 1.h),
                Text(message,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white, fontSize: 13.sp, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ),
      ),
    );

    Overlay.of(context).insert(overlayEntry);
    Future.delayed(const Duration(seconds: 2), () => overlayEntry.remove());
  }

  Future<void> _initializeData() async {
    try {
      await _loadGeoJson();
      await _getUserData();
    } catch (e) {
      debugPrint("Error initializing: $e");
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _loadGeoJson() async {
    final String response = await rootBundle.loadString(
        'assets/OSMB-bc319d822a17aa9ad1089fc05e7d4e752460f877.geojson');
    geoJsonData = json.decode(response);
  }

  // --- التعديل الجوهري هنا: البحث الديناميكي عن المناديب ---
  Future<void> _getUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // 1. جلب مستند المدير/المشرف من الفايرستور
    final snap = await FirebaseFirestore.instance
        .collection('managers')
        .where('uid', isEqualTo: user.uid)
        .get();

    if (snap.docs.isNotEmpty) {
      var doc = snap.docs.first;
      var data = doc.data();
      role = data['role'];
      myAreas = List<String>.from(data['geographicArea'] ?? []);
      
      // معرف المستند (Document ID) هو الذي يربط المناديب بالمشرف
      String supervisorDocId = doc.id;

      if (role == 'delivery_supervisor') {
        // 2. البحث في مجموعة deliveryReps عن المناديب التابعين لهذا المشرف
        final repsSnap = await FirebaseFirestore.instance
            .collection('deliveryReps')
            .where('supervisorId', isEqualTo: supervisorDocId)
            .get();

        myReps = repsSnap.docs.map((d) => {
          'id': d.id,
          'fullname': d['fullname'],
          'repCode': d['repCode']
        }).toList();
      }
    }
  }

  bool _isPointInPolygon(LatLng point, List<LatLng> polygon) {
    var lat = point.latitude;
    var lng = point.longitude;
    var inside = false;
    for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      var xi = polygon[i].latitude, yi = polygon[i].longitude;
      var xj = polygon[j].latitude, yj = polygon[j].longitude;
      var intersect = ((yi > lng) != (yj > lng)) && (lat < (xj - xi) * (lng - yi) / (yj - yi) + xi);
      if (intersect) inside = !inside;
    }
    return inside;
  }

  bool _isOrderInMyArea(Map<String, dynamic> locationData) {
    if (role == 'delivery_manager') return true;
    if (geoJsonData == null || myAreas.isEmpty) return false;

    double lat = (locationData['lat'] as num).toDouble();
    double lng = (locationData['lng'] as num).toDouble();
    LatLng orderPoint = LatLng(lat, lng);

    for (var areaName in myAreas) {
      var feature = geoJsonData!['features'].firstWhere(
          (f) => f['properties']['name'] == areaName, orElse: () => null);

      if (feature != null) {
        var geometry = feature['geometry'];
        List coords = geometry['coordinates'][0];
        List<LatLng> polygon = coords.map<LatLng>((c) =>
            LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble())).toList();

        if (_isPointInPolygon(orderPoint, polygon)) return true;
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(role == 'delivery_manager' ? "إدارة طلبات المدير" : "طلبات المشرف - جغرافياً"),
        centerTitle: true,
        backgroundColor: const Color(0xFF2F3542),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('orders').snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

                var filteredOrders = snapshot.data!.docs.where((doc) {
                  var data = doc.data() as Map<String, dynamic>;

                  if (role == 'delivery_manager') {
                    return data['status'] == 'new-order' && data['deliveryManagerAssigned'] != true;
                  } else if (role == 'delivery_supervisor') {
                    return data['deliveryManagerAssigned'] == true &&
                        data['status'] != 'delivered' &&
                        data['deliveryRepId'] == null &&
                        _isOrderInMyArea(data['buyer']['location']);
                  }
                  return false;
                }).toList();

                if (filteredOrders.isEmpty) {
                  return const Center(child: Text("لا توجد طلبات معلقة حالياً"));
                }

                return ListView.builder(
                  itemCount: filteredOrders.length,
                  itemBuilder: (context, index) {
                    var order = filteredOrders[index].data() as Map<String, dynamic>;
                    var orderId = filteredOrders[index].id;

                    return Card(
                      margin: EdgeInsets.symmetric(horizontal: 4.w, vertical: 1.h),
                      elevation: 3,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                      child: Padding(
                        padding: EdgeInsets.all(15.sp),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text("طلب رقم: ${orderId.substring(0, 5)}",
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.sp)),
                                Text("${order['total']} ج.م",
                                    style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 12.sp)),
                              ],
                            ),
                            const Divider(),
                            Text("العميل: ${order['buyer']['name']}"),
                            Text("العنوان: ${order['buyer']['address']}"),
                            SizedBox(height: 2.h),
                            if (role == 'delivery_manager')
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  icon: const Icon(Icons.send),
                                  label: const Text("نقل للتوصيل"),
                                  style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.orange, foregroundColor: Colors.white),
                                  onPressed: () => _managerMoveToDelivery(orderId),
                                ),
                              ),
                            if (role == 'delivery_supervisor')
                              _buildSupervisorAction(orderId, order),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }

  Future<void> _managerMoveToDelivery(String id) async {
    await FirebaseFirestore.instance.collection('orders').doc(id).update({
      'deliveryManagerAssigned': true,
    });
    _showSuccessOverlay("تم النقل لفريق التوصيل جغرافياً");
  }

  Widget _buildSupervisorAction(String orderId, Map<String, dynamic> orderData) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("إسناد لمندوب تحصيل:", style: TextStyle(fontWeight: FontWeight.bold)),
        myReps.isEmpty 
          ? Padding(
              padding: EdgeInsets.symmetric(vertical: 1.h),
              child: const Text("⚠️ لا يوجد مناديب مسجلين تحت إدارتك حالياً", style: TextStyle(color: Colors.redAccent)),
            )
          : DropdownButton<String>(
              isExpanded: true,
              hint: const Text("اختر مندوب من فريقك"),
              items: myReps.map<DropdownMenuItem<String>>((rep) {
                return DropdownMenuItem<String>(
                    value: rep['repCode'].toString(),
                    child: Text(rep['fullname'].toString()));
              }).toList(),
              onChanged: (val) async {
                if (val != null) {
                  var selectedRep = myReps.firstWhere((r) => r['repCode'] == val);
                  await _assignToRep(orderId, orderData, selectedRep);
                }
              },
            ),
      ],
    );
  }

  Future<void> _assignToRep(String id, Map<String, dynamic> data, Map rep) async {
    // 1. تحديث الطلب الأساسي بالإشارة للمندوب
    await FirebaseFirestore.instance.collection('orders').doc(id).update({
      'deliveryRepId': rep['repCode'],
      'repName': rep['fullname'],
    });

    // 2. رفع النسخة لـ waitingdelivery كما في الـ HTML تماماً
    await FirebaseFirestore.instance.collection('waitingdelivery').doc(id).set({
      ...data,
      'deliveryRepId': rep['repCode'],
      'repName': rep['fullname'],
    });

    _showSuccessOverlay("تم الإسناد للمندوب ${rep['fullname']}");
  }
}


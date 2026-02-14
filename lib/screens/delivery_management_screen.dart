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
  
  // لطباعة تقارير الفحص على الشاشة
  String debugConsole = "بدء فحص النظام...";

  @override
  void initState() {
    super.initState();
    _initializeData();
  }

  // دالة لتحديث الكونسول على الشاشة
  void _updateLog(String msg) {
    if (mounted) {
      setState(() {
        debugConsole = "$msg\n$debugConsole";
      });
    }
  }

  // (دالة _showSuccessOverlay تبقى كما هي...)
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
      _updateLog("✅ تم تحميل البيانات بنجاح");
    } catch (e) {
      _updateLog("❌ خطأ في التهيئة: $e");
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _loadGeoJson() async {
    final String response = await rootBundle.loadString(
        'assets/OSMB-bc319d822a17aa9ad1089fc05e7d4e752460f877.geojson');
    geoJsonData = json.decode(response);
    _updateLog("📂 ملف GeoJSON محمل: ${geoJsonData!['features'].length} منطقة");
  }

  Future<void> _getUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final snap = await FirebaseFirestore.instance.collection('managers').where('uid', isEqualTo: user.uid).get();

    if (snap.docs.isNotEmpty) {
      var doc = snap.docs.first;
      var data = doc.data();
      role = data['role'];
      myAreas = List<String>.from(data['geographicArea'] ?? []);
      _updateLog("👤 الدور: $role | المناطق: ${myAreas.join(', ')}");

      if (role == 'delivery_supervisor') {
        final repsSnap = await FirebaseFirestore.instance.collection('deliveryReps').where('supervisorId', isEqualTo: doc.id).get();
        myReps = repsSnap.docs.map((d) => {'id': d.id, 'fullname': d['fullname'], 'repCode': d['repCode']}).toList();
        _updateLog("👥 عدد المندوبين: ${myReps.length}");
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
      // فحص وجود المنطقة في الملف
      var feature = geoJsonData!['features'].firstWhere(
          (f) => f['properties']['name'].toString().trim() == areaName.trim(), 
          orElse: () => null);

      if (feature == null) {
        _updateLog("⚠️ لم يتم العثور على منطقة '$areaName' في ملف الخريطة");
        continue;
      }

      try {
        var geometry = feature['geometry'];
        var type = geometry['type'];
        List coordsLevel1 = geometry['coordinates'];

        // فحص الفهرس - الحل المرن
        List<LatLng> polygon = [];
        if (type == 'Polygon') {
          // إذا كان الفهرس المطلوب هو 0 أو أعمق
          var rawPoints = coordsLevel1[0];
          _updateLog("📍 فحص Polygon لفهرس 0: ${rawPoints.length} نقطة");
          
          polygon = rawPoints.map<LatLng>((c) =>
              LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble())).toList();
        } else if (type == 'MultiPolygon') {
          _updateLog("📍 فحص MultiPolygon...");
          for (var poly in coordsLevel1) {
            var rawPoints = poly[0];
            polygon = rawPoints.map<LatLng>((c) =>
                LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble())).toList();
            if (_isPointInPolygon(orderPoint, polygon)) return true;
          }
        }

        if (_isPointInPolygon(orderPoint, polygon)) {
          _updateLog("🎯 طلب داخل حدود $areaName");
          return true;
        }
      } catch (e) {
        _updateLog("🚨 خطأ في هيكل الفهرس لمنطقة $areaName: $e");
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
      body: Column(
        children: [
          // كونسول الفحص يظهر في الأعلى للمساعدة في التصحيح
          if (role == 'delivery_supervisor')
            Container(
              height: 15.h,
              width: double.infinity,
              margin: const EdgeInsets.all(8),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(10)),
              child: SingleChildScrollView(
                reverse: true,
                child: Text(debugConsole, style: const TextStyle(color: Colors.greenAccent, fontSize: 10, fontFamily: 'monospace')),
              ),
            ),
          
          Expanded(
            child: isLoading
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
                          bool isOk = data['deliveryManagerAssigned'] == true &&
                              data['status'] != 'delivered' &&
                              data['deliveryRepId'] == null &&
                              _isOrderInMyArea(data['buyer']['location']);
                          return isOk;
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
                          return _buildOrderCard(orderId, order);
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderCard(String orderId, Map<String, dynamic> order) {
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
                Text("طلب رقم: ${orderId.substring(0, 5)}", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.sp)),
                Text("${order['total']} ج.م", style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 12.sp)),
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
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
                  onPressed: () => _managerMoveToDelivery(orderId),
                ),
              ),
            if (role == 'delivery_supervisor') _buildSupervisorAction(orderId, order),
          ],
        ),
      ),
    );
  }

  // (باقي الدوال _managerMoveToDelivery و _buildSupervisorAction و _assignToRep تبقى كما هي...)
  Future<void> _managerMoveToDelivery(String id) async {
    await FirebaseFirestore.instance.collection('orders').doc(id).update({'deliveryManagerAssigned': true});
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
    await FirebaseFirestore.instance.collection('orders').doc(id).update({
      'deliveryRepId': rep['repCode'],
      'repName': rep['fullname'],
    });
    await FirebaseFirestore.instance.collection('waitingdelivery').doc(id).set({
      ...data,
      'repCode': rep['repCode'],
      'deliveryRepId': rep['repCode'],
      'repName': rep['fullname'],
    });
    _showSuccessOverlay("تم الإسناد للمندوب ${rep['fullname']}");
  }
}

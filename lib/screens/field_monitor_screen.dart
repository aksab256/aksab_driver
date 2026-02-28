import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:latlong2/latlong.dart'; // مكتبة الحسابات الجغرافية
import 'package:sizer/sizer.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

class FieldMonitorScreen extends StatefulWidget {
  const FieldMonitorScreen({super.key});

  @override
  State<FieldMonitorScreen> createState() => _FieldMonitorScreenState();
}

class _FieldMonitorScreenState extends State<FieldMonitorScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  
  // متغيرات الصلاحيات والجغرافيا
  String? userRole;
  List<String> myAreas = [];
  Map<String, dynamic>? geoJsonData;
  bool isLoadingGeo = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _initializeAuthAndGeo();
  }

  // تهيئة البيانات: معرفة الصلاحيات وتحميل الخريطة
  Future<void> _initializeAuthAndGeo() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // 1. جلب بيانات المستخدم (مدير أم مشرف)
      final userDoc = await FirebaseFirestore.instance.collection('managers').where('uid', isEqualTo: user.uid).get();
      if (userDoc.docs.isNotEmpty) {
        var userData = userDoc.docs.first.data();
        userRole = userData['role'];
        myAreas = List<String>.from(userData['geographicArea'] ?? []);
      }

      // 2. تحميل ملف الحدود الجغرافية
      final String response = await rootBundle.loadString('assets/OSMB-bc319d822a17aa9ad1089fc05e7d4e752460f877.geojson');
      geoJsonData = json.decode(response);

      setState(() => isLoadingGeo = false);
    } catch (e) {
      debugPrint("❌ خطأ في التهيئة: $e");
      setState(() => isLoadingGeo = false);
    }
  }

  // --- دالة الفحص الجغرافي: هل نقطة الاستلام (الراسل) داخل نطاق المشرف؟ ---
  bool _shouldShowOrder(Map<String, dynamic> data) {
    // 1. إذا كان مدير (Delivery Manager) يرى كل شيء
    if (userRole == 'delivery_manager') return true;
    
    // 2. إذا كان مشرف، نتحقق من موقع الاستلام (الراسل)
    if (geoJsonData == null || myAreas.isEmpty) return false;
    
    var loc = data['pickupLocation'];
    if (loc == null) return false;

    double lat = 0, lng = 0;
    if (loc is GeoPoint) {
      lat = loc.latitude; lng = loc.longitude;
    } else if (loc is List && loc.length >= 2) {
      lat = loc[0]; lng = loc[1];
    }

    LatLng point = LatLng(lat, lng);

    for (var areaName in myAreas) {
      var feature = geoJsonData!['features'].firstWhere(
        (f) => f['properties']['name'].toString().trim() == areaName.trim(),
        orElse: () => null
      );
      if (feature == null) continue;

      var geometry = feature['geometry'];
      if (geometry['type'] == 'Polygon') {
        if (_checkPolygon(point, geometry['coordinates'][0])) return true;
      } else if (geometry['type'] == 'MultiPolygon') {
        for (var poly in geometry['coordinates']) {
          if (_checkPolygon(point, poly[0])) return true;
        }
      }
    }
    return false;
  }

  // خوارزمية Ray-Casting لتحديد النقطة داخل المضلع
  bool _checkPolygon(LatLng point, List coords) {
    List<LatLng> polyPoints = coords.map<LatLng>((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble())).toList();
    var lat = point.latitude; var lng = point.longitude; var inside = false;
    for (var i = 0, j = polyPoints.length - 1; i < polyPoints.length; j = i++) {
      if (((polyPoints[i].longitude > lng) != (polyPoints[j].longitude > lng)) && 
          (lat < (polyPoints[j].latitude - polyPoints[i].latitude) * (lng - polyPoints[i].longitude) / 
          (polyPoints[j].longitude - polyPoints[i].longitude) + polyPoints[i].latitude)) {
        inside = !inside;
      }
    }
    return inside;
  }

  @override
  Widget build(BuildContext context) {
    if (isLoadingGeo) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: AppBar(
        title: Text(userRole == 'delivery_manager' ? "رقابة العهد (عام)" : "متابعة النطاق الجغرافي", 
          style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 14.sp, color: Colors.white)),
        centerTitle: true,
        backgroundColor: Colors.blueGrey[900],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [ Tab(text: "الرحلات النشطة"), Tab(text: "المرتجع 🚨") ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [ _buildOrdersList(isOnlyReturns: false), _buildOrdersList(isOnlyReturns: true) ],
      ),
    );
  }

  Widget _buildOrdersList({required bool isOnlyReturns}) {
    List<String> statuses = isOnlyReturns ? ['returning_to_seller'] : ['pending', 'accepted', 'picked_up', 'returning_to_seller'];

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('specialRequests').where('status', whereIn: statuses).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

        // فلترة البيانات بناءً على الصلاحية والجغرافيا (الراسل داخل المنطقة)
        var filteredDocs = snapshot.data!.docs.where((doc) {
          return _shouldShowOrder(doc.data() as Map<String, dynamic>);
        }).toList();

        if (filteredDocs.isEmpty) return Center(child: Text("لا توجد بيانات متاحة لنطاقك"));

        // ترتيب يدوي للأحدث
        filteredDocs.sort((a, b) {
          Timestamp? tA = (a.data() as Map)['createdAt'];
          Timestamp? tB = (b.data() as Map)['createdAt'];
          return (tB ?? Timestamp.now()).compareTo(tA ?? Timestamp.now());
        });

        return ListView.builder(
          padding: EdgeInsets.all(10.sp),
          itemCount: filteredDocs.length,
          itemBuilder: (context, index) => _buildOrderCard(filteredDocs[index].data() as Map<String, dynamic>),
        );
      },
    );
  }

  // --- كارد الطلب (بنفس منطق نقاط الأمان والعهدة) ---
  Widget _buildOrderCard(Map<String, dynamic> data) {
    bool isRetailer = data['requestSource'] == 'retailer';
    String status = data['status'];
    bool isMoneyLocked = data['moneyLocked'] ?? false;

    return Card(
      margin: EdgeInsets.only(bottom: 12.sp),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Column(
        children: [
          Container(
            padding: EdgeInsets.all(8.sp),
            decoration: BoxDecoration(
              color: status == 'returning_to_seller' ? Colors.red[900] : (isRetailer ? Colors.blue[900] : Colors.orange[800]),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(isRetailer ? "🏪 تاجر: ${data['userName'] ?? ''}" : "👤 مستهلك: ${data['userName'] ?? ''}", 
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 9.sp)),
                Text(_translateStatus(status), style: TextStyle(color: Colors.white, fontSize: 9.sp)),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.all(12.sp),
            child: Column(
              children: [
                Row(
                  children: [
                    CircleAvatar(child: Icon(Icons.delivery_dining)),
                    SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(data['driverName'] ?? "بحث عن مندوب...", style: TextStyle(fontWeight: FontWeight.bold)),
                          Text("العهدة المحجوزة: ${data['insurance_points'] ?? 0} نقطة", 
                            style: TextStyle(color: Colors.blue[900], fontSize: 10.sp, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                    IconButton(icon: Icon(Icons.phone, color: Colors.green), onPressed: () => launchUrl(Uri.parse("tel:${data['userPhone']}"))),
                  ],
                ),
                Divider(),
                _locationLine(Icons.login, "من (الاستلام): ${data['pickupAddress']}"),
                _locationLine(Icons.logout, "إلى (التسليم): ${data['dropoffAddress']}"),
                Divider(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    isMoneyLocked ? const Text("✅ عهدة مؤمنة", style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold))
                                  : const Text("⚠️ قيد التأمين", style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
                    Text(data['createdAt'] != null ? DateFormat('hh:mm a').format(data['createdAt'].toDate()) : ""),
                  ],
                )
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _locationLine(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icon, size: 12, color: Colors.grey),
          SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(fontSize: 10, color: Colors.black54), overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }

  String _translateStatus(String status) {
    switch (status) {
      case 'pending': return "انتظار";
      case 'accepted': return "تم القبول";
      case 'picked_up': return "تم الاستلام";
      case 'returning_to_seller': return "مرتجع";
      default: return status;
    }
  }
}

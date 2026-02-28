import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:latlong2/latlong.dart'; 
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

  Future<void> _initializeAuthAndGeo() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final userDoc = await FirebaseFirestore.instance.collection('managers').where('uid', isEqualTo: user.uid).get();
      if (userDoc.docs.isNotEmpty) {
        var userData = userDoc.docs.first.data();
        userRole = userData['role'];
        myAreas = List<String>.from(userData['geographicArea'] ?? []);
      }

      final String response = await rootBundle.loadString('assets/OSMB-bc319d822a17aa9ad1089fc05e7d4e752460f877.geojson');
      geoJsonData = json.decode(response);

      setState(() => isLoadingGeo = false);
    } catch (e) {
      debugPrint("❌ خطأ في التهيئة: $e");
      setState(() => isLoadingGeo = false);
    }
  }

  bool _shouldShowOrder(Map<String, dynamic> data) {
    if (userRole == 'delivery_manager') return true;
    if (geoJsonData == null || myAreas.isEmpty) return false;
    
    var loc = data['pickupLocation'];
    if (loc == null) return false;

    double lat = 0, lng = 0;
    if (loc is GeoPoint) {
      lat = loc.latitude; lng = loc.longitude;
    } else if (loc is List && loc.length >= 2) {
      lat = (loc[0] as num).toDouble(); lng = (loc[1] as num).toDouble();
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
        elevation: 0,
        title: Text(userRole == 'delivery_manager' ? "رقابة العهد (عام)" : "متابعة النطاق الجغرافي", 
          style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 16.sp, color: Colors.white)),
        centerTitle: true,
        backgroundColor: Colors.blueGrey[900],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.orangeAccent,
          indicatorWeight: 4,
          labelStyle: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 11.sp),
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

        var filteredDocs = snapshot.data!.docs.where((doc) {
          return _shouldShowOrder(doc.data() as Map<String, dynamic>);
        }).toList();

        int pendingCount = filteredDocs.where((d) => d['status'] == 'pending').length;
        double totalInsurance = filteredDocs.fold(0.0, (sum, item) {
          var data = item.data() as Map<String, dynamic>;
          return sum + (data['insurance_points'] ?? 0).toDouble();
        });

        filteredDocs.sort((a, b) {
          Timestamp? tA = (a.data() as Map)['createdAt'];
          Timestamp? tB = (b.data() as Map)['createdAt'];
          return (tB ?? Timestamp.now()).compareTo(tA ?? Timestamp.now());
        });

        return Column(
          children: [
            _buildStatsDashboard(pendingCount, totalInsurance, filteredDocs.length),
            Expanded(
              child: filteredDocs.isEmpty 
              ? Center(child: Text("لا توجد بيانات حالياً", style: TextStyle(fontFamily: 'Cairo', fontSize: 13.sp)))
              : ListView.builder(
                  padding: EdgeInsets.fromLTRB(10.sp, 5.sp, 10.sp, 15.sp),
                  itemCount: filteredDocs.length,
                  itemBuilder: (context, index) => _buildOrderCard(filteredDocs[index].data() as Map<String, dynamic>),
                ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildStatsDashboard(int pending, double insurance, int total) {
    return Container(
      padding: EdgeInsets.fromLTRB(10.sp, 5.sp, 10.sp, 15.sp),
      decoration: BoxDecoration(
        color: Colors.blueGrey[900],
        borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(30), bottomRight: Radius.circular(30)),
      ),
      child: Row(
        children: [
          _statCard("في الانتظار", pending.toString(), Icons.hourglass_top_rounded, Colors.orangeAccent),
          SizedBox(width: 8.sp),
          _statCard("نقاط الأمان", insurance.toStringAsFixed(0), Icons.shield_outlined, Colors.greenAccent),
          SizedBox(width: 8.sp),
          _statCard("إجمالي النشط", total.toString(), Icons.assignment_outlined, Colors.blueAccent),
        ],
      ),
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 12.sp),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.15)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 20.sp),
            SizedBox(height: 5.sp),
            Text(value, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16.sp, height: 1.1)),
            Text(label, style: TextStyle(color: Colors.white70, fontSize: 9.sp, fontFamily: 'Cairo', fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderCard(Map<String, dynamic> data) {
    bool isRetailer = data['requestSource'] == 'retailer';
    String status = data['status'];
    bool isMoneyLocked = data['moneyLocked'] ?? false;

    return Card(
      margin: EdgeInsets.only(top: 10.sp),
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Column(
        children: [
          Container(
            padding: EdgeInsets.symmetric(horizontal: 12.sp, vertical: 10.sp),
            decoration: BoxDecoration(
              color: status == 'returning_to_seller' ? Colors.red[900] : (isRetailer ? Colors.blue[900] : Colors.orange[900]),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(data['userName'] ?? '', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11.5.sp, fontFamily: 'Cairo')),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(12)),
                  child: Text(_translateStatus(status), style: TextStyle(color: Colors.white, fontSize: 10.sp, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.all(12.sp),
            child: Column(
              children: [
                Row(
                  children: [
                    CircleAvatar(radius: 22.sp, backgroundColor: Colors.blueGrey[50], child: Icon(Icons.person, size: 22.sp, color: Colors.blueGrey[800])),
                    SizedBox(width: 12.sp),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(data['driverName'] ?? "في انتظار مندوب...", 
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.sp, color: Colors.black87, fontFamily: 'Cairo')),
                          Text("تأمين العهدة: ${data['insurance_points'] ?? 0} نقطة", 
                            style: TextStyle(color: Colors.blue[900], fontSize: 11.5.sp, fontWeight: FontWeight.w900)),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: CircleAvatar(radius: 20.sp, backgroundColor: Colors.green[600], child: const Icon(Icons.phone, color: Colors.white)), 
                      onPressed: () => launchUrl(Uri.parse("tel:${data['userPhone']}"))
                    ),
                  ],
                ),
                const Divider(height: 25, thickness: 1),
                _locationLine(Icons.location_on, "من: ${data['pickupAddress']}"),
                SizedBox(height: 8.sp),
                _locationLine(Icons.flag_circle, "إلى: ${data['dropoffAddress']}"),
                const Divider(height: 25, thickness: 1),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(isMoneyLocked ? Icons.verified_user : Icons.security_update_warning, 
                          color: isMoneyLocked ? Colors.green[700] : Colors.orange[800], size: 16.sp),
                        SizedBox(width: 6.sp),
                        Text(isMoneyLocked ? "عهدة مؤمنة ✅" : "قيد التأمين ⚠️", 
                          style: TextStyle(color: isMoneyLocked ? Colors.green[700] : Colors.orange[800], fontWeight: FontWeight.bold, fontSize: 11.sp)),
                      ],
                    ),
                    Text(data['createdAt'] != null ? DateFormat('hh:mm a').format(data['createdAt'].toDate()) : "",
                      style: TextStyle(color: Colors.grey[700], fontSize: 10.sp, fontWeight: FontWeight.bold)),
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
    return Row(
      children: [
        Icon(icon, size: 16.sp, color: Colors.blueGrey[400]),
        SizedBox(width: 10.sp),
        Expanded(child: Text(text, style: TextStyle(fontSize: 11.sp, color: Colors.black87, fontWeight: FontWeight.w500, fontFamily: 'Cairo'), overflow: TextOverflow.ellipsis)),
      ],
    );
  }

  String _translateStatus(String status) {
    switch (status) {
      case 'pending': return "إرسال الطلب";
      case 'accepted': return "تم القبول";
      case 'picked_up': return "بعهد المندوب";
      case 'returning_to_seller': return "جاري المرتجع";
      default: return "غير معروف";
    }
  }
}

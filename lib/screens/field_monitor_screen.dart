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
          style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 14.sp, color: Colors.white)),
        centerTitle: true,
        backgroundColor: Colors.blueGrey[900],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.orangeAccent,
          indicatorWeight: 3,
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

        // حساب إحصائيات العدادات بناءً على الطلبات الجارية في منطقة المشرف فقط
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
            // العدادات الاحترافية (Dashboard Header)
            _buildStatsDashboard(pendingCount, totalInsurance, filteredDocs.length),
            
            Expanded(
              child: filteredDocs.isEmpty 
              ? Center(child: Text("لا توجد بيانات متاحة لنطاقك حالياً", style: TextStyle(fontFamily: 'Cairo', fontSize: 11.sp)))
              : ListView.builder(
                  padding: EdgeInsets.all(10.sp),
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
      padding: EdgeInsets.fromLTRB(10.sp, 0, 10.sp, 15.sp),
      decoration: BoxDecoration(
        color: Colors.blueGrey[900],
        borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(25), bottomRight: Radius.circular(25)),
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
        padding: EdgeInsets.symmetric(vertical: 10.sp),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 16.sp),
            SizedBox(height: 4.sp),
            Text(value, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12.sp, height: 1.1)),
            Text(label, style: TextStyle(color: Colors.white70, fontSize: 7.sp, fontFamily: 'Cairo')),
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
      margin: EdgeInsets.only(bottom: 12.sp),
      elevation: 3,
      shadowColor: Colors.black26,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Column(
        children: [
          Container(
            padding: EdgeInsets.symmetric(horizontal: 12.sp, vertical: 8.sp),
            decoration: BoxDecoration(
              color: status == 'returning_to_seller' ? Colors.red[900] : (isRetailer ? Colors.blue[900] : Colors.orange[800]),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(isRetailer ? Icons.storefront : Icons.person_outline, color: Colors.white, size: 12.sp),
                    SizedBox(width: 5),
                    Text(data['userName'] ?? '', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 9.sp, fontFamily: 'Cairo')),
                  ],
                ),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10)),
                  child: Text(_translateStatus(status), style: TextStyle(color: Colors.white, fontSize: 8.sp, fontWeight: FontWeight.w500)),
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
                    CircleAvatar(
                      backgroundColor: Colors.blueGrey[50],
                      child: Icon(Icons.delivery_dining, color: Colors.blueGrey[900]),
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(data['driverName'] ?? "في انتظار قبول المندوب...", 
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10.sp, color: Colors.black87)),
                          Text("تأمين العهدة: ${data['insurance_points'] ?? 0} نقطة", 
                            style: TextStyle(color: Colors.blue[900], fontSize: 9.sp, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                    if (data['userPhone'] != null)
                      IconButton(
                        icon: CircleAvatar(backgroundColor: Colors.green[50], child: Icon(Icons.phone, color: Colors.green, size: 15.sp)), 
                        onPressed: () => launchUrl(Uri.parse("tel:${data['userPhone']}"))
                      ),
                  ],
                ),
                const Divider(height: 20),
                _locationLine(Icons.location_on_outlined, "الاستلام: ${data['pickupAddress']}"),
                SizedBox(height: 5),
                _locationLine(Icons.flag_outlined, "التسليم: ${data['dropoffAddress']}"),
                const Divider(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(isMoneyLocked ? Icons.verified_user : Icons.gpp_maybe, 
                          color: isMoneyLocked ? Colors.green : Colors.orange, size: 14.sp),
                        SizedBox(width: 5),
                        Text(isMoneyLocked ? "تأمين عهدة مكتمل" : "قيد تأمين النقاط", 
                          style: TextStyle(color: isMoneyLocked ? Colors.green : Colors.orange, fontWeight: FontWeight.bold, fontSize: 9.sp)),
                      ],
                    ),
                    Text(data['createdAt'] != null ? DateFormat('hh:mm a').format(data['createdAt'].toDate()) : "",
                      style: TextStyle(color: Colors.grey, fontSize: 8.sp)),
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
        Icon(icon, size: 13.sp, color: Colors.blueGrey[300]),
        SizedBox(width: 8),
        Expanded(child: Text(text, style: TextStyle(fontSize: 9.sp, color: Colors.black54, fontFamily: 'Cairo'), overflow: TextOverflow.ellipsis)),
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

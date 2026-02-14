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
  String debugConsole = "🚀 فحص الاتصال المباشر...";

  @override
  void initState() {
    super.initState();
    _initializeData();
  }

  void _updateLog(String msg) {
    if (mounted) {
      setState(() => debugConsole = "$msg\n$debugConsole");
    }
  }

  Future<void> _initializeData() async {
    _updateLog("⏳ جاري سحب بيانات المشرف...");
    await _getUserData();
    
    _updateLog("⏳ تحميل ملف الخريطة...");
    try {
      final response = await rootBundle.loadString('assets/OSMB-bc319d822a17aa9ad1089fc05e7d4e752460f877.geojson');
      geoJsonData = json.decode(response);
      _updateLog("✅ الخريطة جاهزة (${geoJsonData!['features'].length} منطقة)");
    } catch (e) {
      _updateLog("❌ خطأ خريطة: $e");
    }

    if (mounted) setState(() => isLoading = false);
  }

  Future<void> _getUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) { _updateLog("❌ لا يوجد مستخدم!"); return; }
    
    final snap = await FirebaseFirestore.instance.collection('managers').where('uid', isEqualTo: user.uid).get();
    if (snap.docs.isNotEmpty) {
      var doc = snap.docs.first;
      role = doc['role'];
      myAreas = List<String>.from(doc['geographicArea'] ?? []);
      _updateLog("👤 $role | مناطق: ${myAreas.length}");

      if (role == 'delivery_supervisor') {
        final reps = await FirebaseFirestore.instance.collection('deliveryReps').where('supervisorId', isEqualTo: doc.id).get();
        myReps = reps.docs.map((d) => {'fullname': d['fullname'], 'repCode': d['repCode']}).toList();
      }
    }
  }

  bool _isOrderInMyArea(Map<String, dynamic> locationData) {
    if (role == 'delivery_manager') return true;
    if (geoJsonData == null) return false;
    
    double lat = (locationData['lat'] as num).toDouble();
    double lng = (locationData['lng'] as num).toDouble();
    LatLng point = LatLng(lat, lng);

    for (var area in myAreas) {
      var feature = geoJsonData!['features'].firstWhere(
          (f) => f['properties']['name'].toString().trim() == area.trim(), orElse: () => null);
      if (feature == null) continue;

      var coords = feature['geometry']['coordinates'];
      var type = feature['geometry']['type'];

      if (type == 'Polygon') {
        if (_checkPolygon(point, coords[0])) return true;
      } else if (type == 'MultiPolygon') {
        for (var poly in coords) { if (_checkPolygon(point, poly[0])) return true; }
      }
    }
    return false;
  }

  bool _checkPolygon(LatLng point, List coords) {
    List<LatLng> polyPoints = coords.map<LatLng>((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble())).toList();
    var lat = point.latitude;
    var lng = point.longitude;
    var inside = false;
    for (var i = 0, j = polyPoints.length - 1; i < polyPoints.length; j = i++) {
      if (((polyPoints[i].longitude > lng) != (polyPoints[j].longitude > lng)) &&
          (lat < (polyPoints[j].latitude - polyPoints[i].latitude) * (lng - polyPoints[i].longitude) / (polyPoints[j].longitude - polyPoints[i].longitude) + polyPoints[i].latitude)) {
        inside = !inside;
      }
    }
    return inside;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("نظام التوجيه الجغرافي"), backgroundColor: const Color(0xFF2F3542)),
      body: Column(
        children: [
          Container(
            height: 15.h, width: double.infinity, margin: const EdgeInsets.all(5),
            padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(10)),
            child: SingleChildScrollView(reverse: true, child: Text(debugConsole, style: const TextStyle(color: Colors.greenAccent, fontSize: 10, fontFamily: 'monospace'))),
          ),
          Expanded(
            child: isLoading ? const Center(child: CircularProgressIndicator()) : StreamBuilder<QuerySnapshot>(
              // تم تبسيط الاستعلام لأقصى درجة لتجنب أي تعليق
              stream: FirebaseFirestore.instance.collection('orders').snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  _updateLog("🚨 خطأ صريح: ${snapshot.error}");
                  return Center(child: Text("خطأ: ${snapshot.error}"));
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: Text("⏳ بانتظار رد السيرفر..."));
                }
                
                var docs = snapshot.data?.docs ?? [];
                _updateLog("📥 تم استلام ${docs.length} طلبات");

                var filtered = docs.where((doc) {
                  var data = doc.data() as Map<String, dynamic>;
                  if (role == 'delivery_manager') return data['status'] == 'new-order' && data['deliveryManagerAssigned'] != true;
                  
                  // شروط المشرف
                  bool cond = data['deliveryManagerAssigned'] == true && data['deliveryRepId'] == null;
                  if (cond && data['buyer']?['location'] != null) {
                    return _isOrderInMyArea(data['buyer']['location']);
                  }
                  return false;
                }).toList();

                _updateLog("🎯 متاح للعرض: ${filtered.length}");

                if (filtered.isEmpty) return const Center(child: Text("لا توجد طلبات مطابقة"));

                return ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (context, index) => _buildOrderCard(filtered[index].id, filtered[index].data() as Map<String, dynamic>),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderCard(String id, Map data) {
    return Card(
      margin: const EdgeInsets.all(8),
      child: ListTile(
        title: Text("طلب #${id.substring(0,5)}"),
        subtitle: Text("العميل: ${data['buyer']['name']}"),
        trailing: role == 'delivery_supervisor' ? _buildRepPicker(id, data) : null,
      ),
    );
  }

  Widget _buildRepPicker(String id, Map data) {
    return DropdownButton<String>(
      hint: const Text("إسناد"),
      items: myReps.map((r) => DropdownMenuItem(value: r['repCode'].toString(), child: Text(r['fullname']))).toList(),
      onChanged: (val) async {
        var rep = myReps.firstWhere((r) => r['repCode'] == val);
        await FirebaseFirestore.instance.collection('orders').doc(id).update({'deliveryRepId': val, 'repName': rep['fullname']});
        _updateLog("✅ تم إسناد الطلب لـ ${rep['fullname']}");
      },
    );
  }
}

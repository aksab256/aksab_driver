import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:latlong2/latlong.dart';

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

  Future<void> _initializeData() async {
    await _getUserData();
    try {
      final response = await rootBundle.loadString('assets/OSMB-bc319d822a17aa9ad1089fc05e7d4e752460f877.geojson');
      geoJsonData = json.decode(response);
    } catch (e) {
      debugPrint("Error loading GeoJSON: $e");
    }
    if (mounted) setState(() => isLoading = false);
  }

  Future<void> _getUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    
    final snap = await FirebaseFirestore.instance.collection('managers').where('uid', isEqualTo: user.uid).get();
    if (snap.docs.isNotEmpty) {
      var doc = snap.docs.first;
      role = doc['role'];
      myAreas = List<String>.from(doc['geographicArea'] ?? []);

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
      appBar: AppBar(
        title: Text(role == 'delivery_manager' ? "إدارة التوصيل (مدير)" : "توجيه الطلبات (مشرف)"),
        backgroundColor: const Color(0xFF2F3542),
      ),
      body: isLoading 
        ? const Center(child: CircularProgressIndicator()) 
        : StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('orders').snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) return Center(child: Text("حدث خطأ: ${snapshot.error}"));
              
              // كسر حالة التعليق إذا كانت البيانات موجودة فعلياً
              if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              
              var docs = snapshot.data?.docs ?? [];
              var filtered = docs.where((doc) {
                var data = doc.data() as Map<String, dynamic>;
                
                // منطق المدير
                if (role == 'delivery_manager') {
                  return data['status'] == 'new-order' && data['deliveryManagerAssigned'] != true;
                }
                
                // منطق المشرف
                bool isApproved = data['deliveryManagerAssigned'] == true;
                bool isNotAssignedToRep = data['deliveryRepId'] == null;
                if (isApproved && isNotAssignedToRep && data['buyer']?['location'] != null) {
                  return _isOrderInMyArea(data['buyer']['location']);
                }
                return false;
              }).toList();

              if (filtered.isEmpty) {
                return const Center(child: Text("لا توجد طلبات بانتظار الإجراء حالياً"));
              }

              return ListView.builder(
                padding: const EdgeInsets.all(10),
                itemCount: filtered.length,
                itemBuilder: (context, index) => _buildOrderCard(
                  filtered[index].id, 
                  filtered[index].data() as Map<String, dynamic>
                ),
              );
            },
          ),
    );
  }

  Widget _buildOrderCard(String id, Map data) {
    return Card(
      elevation: 3,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ListTile(
        contentPadding: const EdgeInsets.all(15),
        title: Text("طلب #${id.substring(0,6)}", style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 5),
            Text("العميل: ${data['buyer']['name']}"),
            Text("العنوان: ${data['buyer']['address']}"),
          ],
        ),
        trailing: role == 'delivery_manager' 
          ? ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              onPressed: () => _approveOrder(id),
              child: const Text("نقل للمشرف"),
            )
          : _buildRepPicker(id),
      ),
    );
  }

  Future<void> _approveOrder(String id) async {
    await FirebaseFirestore.instance.collection('orders').doc(id).update({
      'deliveryManagerAssigned': true,
    });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("تم تحويل الطلب للمشرف المختص")));
  }

  Widget _buildRepPicker(String id) {
    return DropdownButton<String>(
      hint: const Text("إسناد لمندوب"),
      underline: const SizedBox(),
      icon: const Icon(Icons.delivery_dining, color: Color(0xFF2F3542)),
      items: myReps.map((r) => DropdownMenuItem(value: r['repCode'].toString(), child: Text(r['fullname']))).toList(),
      onChanged: (val) async {
        if (val == null) return;
        var rep = myReps.firstWhere((r) => r['repCode'] == val);
        await FirebaseFirestore.instance.collection('orders').doc(id).update({
          'deliveryRepId': val, 
          'repName': rep['fullname']
        });
        // هنا يمكنك إضافة منطق نقل الطلب لمجموعة waitingdelivery إذا كان مطلوباً
      },
    );
  }
}

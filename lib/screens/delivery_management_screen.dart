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

  Future<void> _initializeData() async {
    try {
      await _getUserData();
      final response = await rootBundle.loadString('assets/OSMB-bc319d822a17aa9ad1089fc05e7d4e752460f877.geojson');
      if (mounted) {
        setState(() {
          geoJsonData = json.decode(response);
          isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error loading data: $e");
      if (mounted) setState(() => isLoading = false);
    }
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
        myReps = reps.docs.map((d) => {
          'fullname': d['fullname'], 
          'repCode': d['repCode'].toString() 
        }).toList();
      }
    }
  }

  // دالة الفحص الجغرافي (بدون تعديل لضمان الدقة)
  bool _isOrderInMyArea(Map<String, dynamic> locationData) {
    if (role == 'delivery_manager') return true;
    if (geoJsonData == null) return false;
    double lat = (locationData['lat'] as num).toDouble();
    double lng = (locationData['lng'] as num).toDouble();
    LatLng point = LatLng(lat, lng);
    for (var area in myAreas) {
      var feature = geoJsonData!['features'].firstWhere((f) => f['properties']['name'].toString().trim() == area.trim(), orElse: () => null);
      if (feature == null) continue;
      var coords = feature['geometry']['coordinates'];
      var type = feature['geometry']['type'];
      if (type == 'Polygon') { if (_checkPolygon(point, coords[0])) return true; } 
      else if (type == 'MultiPolygon') { for (var poly in coords) { if (_checkPolygon(point, poly[0])) return true; } }
    }
    return false;
  }

  bool _checkPolygon(LatLng point, List coords) {
    List<LatLng> polyPoints = coords.map<LatLng>((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble())).toList();
    var lat = point.latitude; var lng = point.longitude; var inside = false;
    for (var i = 0, j = polyPoints.length - 1; i < polyPoints.length; j = i++) {
      if (((polyPoints[i].longitude > lng) != (polyPoints[j].longitude > lng)) && (lat < (polyPoints[j].latitude - polyPoints[i].latitude) * (lng - polyPoints[i].longitude) / (polyPoints[j].longitude - polyPoints[i].longitude) + polyPoints[i].latitude)) {
        inside = !inside;
      }
    }
    return inside;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F2F6),
      appBar: AppBar(
        title: Text(role == 'delivery_manager' ? "إدارة التوصيل (مدير)" : "توجيه الطلبات (مشرف)",
            style: TextStyle(fontSize: 16.sp, color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF2C3E50),
        centerTitle: true,
      ),
      body: SafeArea( // حماية الصفحة بالكامل
        child: isLoading 
          ? const Center(child: CircularProgressIndicator(color: Colors.blue)) 
          : StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('orders').snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) return Center(child: Text("حدث خطأ في جلب البيانات"));
                if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                
                var docs = snapshot.data?.docs ?? [];
                var filtered = docs.where((doc) {
                  var data = doc.data() as Map<String, dynamic>;
                  if (role == 'delivery_manager') {
                    return data['status'] == 'new-order' && data['deliveryManagerAssigned'] != true;
                  }
                  bool isApproved = data['deliveryManagerAssigned'] == true;
                  bool isNotAssignedToRep = data['deliveryRepId'] == null;
                  if (isApproved && isNotAssignedToRep && data['buyer']?['location'] != null) {
                    return _isOrderInMyArea(data['buyer']['location']);
                  }
                  return false;
                }).toList();

                if (filtered.isEmpty) {
                  return Center(child: Text("لا توجد طلبات جديدة حالياً", style: TextStyle(fontSize: 13.sp, color: Colors.grey)));
                }

                return ListView.builder(
                  padding: EdgeInsets.all(12.sp),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final doc = filtered[index];
                    return _buildOrderCard(doc.id, doc.data() as Map<String, dynamic>);
                  },
                );
              },
            ),
      ),
    );
  }

  Widget _buildOrderCard(String id, Map<String, dynamic> data) {
    return Card(
      elevation: 3,
      margin: EdgeInsets.only(bottom: 12.sp),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: InkWell(
        onTap: () => _showOrderDetails(id, data), // المنبثقة تعمل هنا
        borderRadius: BorderRadius.circular(15),
        child: Padding(
          padding: EdgeInsets.all(15.sp),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("طلب #${id.substring(0,8)}", 
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15.sp, color: const Color(0xFF2C3E50))),
                    SizedBox(height: 6.sp),
                    Text("العميل: ${data['buyer']?['name'] ?? 'غير معروف'}", style: TextStyle(fontSize: 13.sp, color: Colors.black87)),
                    Text("📍 ${data['buyer']?['address'] ?? 'بدون عنوان'}", 
                        style: TextStyle(fontSize: 11.sp, color: Colors.grey[600]), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              role == 'delivery_manager' 
                ? ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green, padding: EdgeInsets.symmetric(horizontal: 10.sp)),
                    onPressed: () => _approveOrder(id),
                    child: Text("موافق", style: TextStyle(color: Colors.white, fontSize: 12.sp)),
                  )
                : _buildRepPicker(id, data),
            ],
          ),
        ),
      ),
    );
  }

  void _showOrderDetails(String id, Map<String, dynamic> data) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => SafeArea(
        child: Container(
          height: 70.h,
          decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
          padding: EdgeInsets.all(20.sp),
          child: Column(
            children: [
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10))),
              SizedBox(height: 20.sp),
              Text("ملخص الطلب", style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold)),
              const Divider(),
              Expanded(
                child: ListView(
                  children: [
                    _infoRow("رقم الطلب", id),
                    _infoRow("المشتري", data['buyer']?['name'] ?? '-'),
                    _infoRow("الهاتف", data['buyer']?['phone'] ?? '-'),
                    _infoRow("العنوان", data['buyer']?['address'] ?? '-'),
                    _infoRow("الإجمالي", "${data['total'] ?? 0} ج.م"),
                  ],
                ),
              ),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2C3E50), padding: EdgeInsets.symmetric(vertical: 12.sp)),
                  onPressed: () => Navigator.pop(context),
                  child: const Text("رجوع", style: TextStyle(color: Colors.white)),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8.sp),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey, fontSize: 12.sp)),
          Expanded(child: Text(value, textAlign: TextAlign.left, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.sp))),
        ],
      ),
    );
  }

  Future<void> _approveOrder(String id) async {
    try {
      await FirebaseFirestore.instance.collection('orders').doc(id).update({'deliveryManagerAssigned': true});
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("تم النقل للمشرف بنجاح")));
    } catch (e) {
      debugPrint("Approve error: $e");
    }
  }

  Widget _buildRepPicker(String id, Map<String, dynamic> orderData) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 5.sp),
      decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(10)),
      child: DropdownButton<String>(
        hint: Text("إسناد", style: TextStyle(fontSize: 11.sp, color: Colors.blue[900], fontWeight: FontWeight.bold)),
        underline: const SizedBox(),
        items: myReps.map((r) => DropdownMenuItem(value: r['repCode'].toString(), child: Text(r['fullname'], style: TextStyle(fontSize: 11.sp)))).toList(),
        onChanged: (val) async {
          if (val == null) return;
          var rep = myReps.firstWhere((r) => r['repCode'] == val);
          await FirebaseFirestore.instance.collection('waitingdelivery').doc(id).set({
            ...orderData,
            'repCode': val,
            'repName': rep['fullname'],
            'assignedAt': FieldValue.serverTimestamp(),
            'deliveryTaskStatus': 'pending',
          });
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("تم الإسناد لـ ${rep['fullname']}")));
        },
      ),
    );
  }
}

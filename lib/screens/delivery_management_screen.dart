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

  // ... (تحميل البيانات والـ GeoJSON كما هو بدون تغيير) ...
  Future<void> _initializeData() async {
    await _getUserData();
    try {
      final response = await rootBundle.loadString('assets/OSMB-bc319d822a17aa9ad1089fc05e7d4e752460f877.geojson');
      setState(() {
        geoJsonData = json.decode(response);
      });
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
        setState(() {
          myReps = reps.docs.map((d) => {
            'fullname': d['fullname'], 
            'repCode': d['repCode'].toString() 
          }).toList();
        });
      }
    }
  }

  // ... (دوال الفحص الجغرافي كما هي بدون تغيير لضمان الدقة) ...
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
            style: TextStyle(fontSize: 15.sp, color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF2C3E50),
        centerTitle: true,
      ),
      // --- التعديل: إضافة SafeArea لحماية الصفحة بالكامل ---
      body: SafeArea(
        child: isLoading 
          ? const Center(child: CircularProgressIndicator()) 
          : StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('orders').snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) return Center(child: Text("حدث خطأ: ${snapshot.error}"));
                if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                
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
                  return Center(child: Text("لا توجد طلبات جديدة حالياً", style: TextStyle(fontSize: 14.sp, color: Colors.grey)));
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
      elevation: 4,
      margin: EdgeInsets.only(bottom: 15.sp),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: InkWell( // تجعل الكارت بالكامل قابل للضغط
        onTap: () => _showOrderDetails(id, data), // فتح المنبثقة
        borderRadius: BorderRadius.circular(15),
        child: Padding(
          padding: EdgeInsets.all(12.sp),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("طلب #${id.substring(0,8)}", 
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.sp, color: const Color(0xFF2C3E50))),
                    SizedBox(height: 5.sp),
                    Row(
                      children: [
                        Icon(Icons.person, size: 12.sp, color: Colors.grey),
                        SizedBox(width: 5.sp),
                        Text("${data['buyer']?['name'] ?? 'غير معروف'}", style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w600)),
                      ],
                    ),
                    Text("📍 ${data['buyer']?['address'] ?? 'بدون عنوان'}", 
                        style: TextStyle(fontSize: 11.sp, color: Colors.blueGrey), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              role == 'delivery_manager' 
                ? ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                    onPressed: () => _approveOrder(id),
                    child: const Text("موافق", style: TextStyle(color: Colors.white)),
                  )
                : _buildRepPicker(id, data),
            ],
          ),
        ),
      ),
    );
  }

  // --- المنبثقة: تفاصيل الطلب في مساحة آمنة ---
  void _showOrderDetails(String id, Map<String, dynamic> data) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => SafeArea( // حماية داخل المنبثقة
        child: Container(
          height: 80.h,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
          ),
          padding: EdgeInsets.all(20.sp),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Container(width: 50, height: 5, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10)))),
              SizedBox(height: 15.sp),
              Text("تفاصيل الطلب بالكامل", style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold)),
              const Divider(),
              Expanded(
                child: ListView(
                  children: [
                    _detailItem("رقم الطلب", id),
                    _detailItem("اسم المشتري", data['buyer']?['name'] ?? '---'),
                    _detailItem("رقم الهاتف", data['buyer']?['phone'] ?? '---'),
                    _detailItem("العنوان", data['buyer']?['address'] ?? '---'),
                    _detailItem("المبلغ الإجمالي", "${data['total'] ?? 0} ج.م"),
                    SizedBox(height: 15.sp),
                    const Text("المنتجات:", style: TextStyle(fontWeight: FontWeight.bold)),
                    ...(data['items'] as List? ?? []).map((item) => ListTile(
                      title: Text(item['name'] ?? 'منتج'),
                      trailing: Text("x${item['quantity']}"),
                      subtitle: Text("${item['price']} ج.م"),
                    )),
                  ],
                ),
              ),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2C3E50), padding: const EdgeInsets.symmetric(vertical: 15)),
                  onPressed: () => Navigator.pop(context),
                  child: const Text("إغلاق", style: TextStyle(color: Colors.white)),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailItem(String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 5.sp),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Future<void> _approveOrder(String id) async {
    await FirebaseFirestore.instance.collection('orders').doc(id).update({'deliveryManagerAssigned': true});
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("تم تحويل الطلب للمشرف")));
  }

  Widget _buildRepPicker(String id, Map<String, dynamic> orderData) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(10)),
      child: DropdownButton<String>(
        hint: Text("إسناد", style: TextStyle(fontSize: 11.sp, fontWeight: FontWeight.bold, color: Colors.blue[900])),
        underline: const SizedBox(),
        icon: Icon(Icons.delivery_dining, color: Colors.blue[900]),
        items: myReps.map<DropdownMenuItem<String>>((Map<String, dynamic> r) {
          return DropdownMenuItem<String>(
            value: r['repCode'].toString(),
            child: Text(r['fullname'], style: TextStyle(fontSize: 12.sp)),
          );
        }).toList(),
        onChanged: (val) async {
          if (val == null) return;
          var rep = myReps.firstWhere((r) => r['repCode'] == val);
          try {
            DocumentReference waitingRef = FirebaseFirestore.instance.collection('waitingdelivery').doc(id);
            Map<String, dynamic> taskData = Map.from(orderData);
            taskData['repCode'] = val;
            taskData['repName'] = rep['fullname'];
            taskData['assignedAt'] = FieldValue.serverTimestamp();
            taskData['deliveryTaskStatus'] = 'pending'; 
            await waitingRef.set(taskData);
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("🚀 تم إسناد الطلب لـ: ${rep['fullname']}")));
          } catch (e) { debugPrint("Error: $e"); }
        },
      ),
    );
  }
}

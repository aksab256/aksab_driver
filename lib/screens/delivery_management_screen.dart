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
  
  // الكونسول الأسود للتشخيص المباشر
  String debugConsole = "🚀 بدء تشغيل النظام...";

  @override
  void initState() {
    super.initState();
    _initializeData();
  }

  void _updateLog(String msg) {
    if (mounted) {
      setState(() {
        debugConsole = "$msg\n$debugConsole";
      });
      print(msg); // للرؤية في الـ Debug Console الخاص بالكمبيوتر أيضاً
    }
  }

  Future<void> _initializeData() async {
    _updateLog("⏳ جاري جلب بيانات المستخدم...");
    await _getUserData();
    
    _updateLog("⏳ جاري تحميل الخريطة في الخلفية...");
    _loadGeoJson().then((_) => _updateLog("✅ الخريطة جاهزة"));

    if (mounted) setState(() => isLoading = false);
  }

  Future<void> _loadGeoJson() async {
    try {
      final String response = await rootBundle.loadString(
          'assets/OSMB-bc319d822a17aa9ad1089fc05e7d4e752460f877.geojson');
      geoJsonData = json.decode(response);
    } catch (e) {
      _updateLog("❌ خطأ في ملف الخريطة: $e");
    }
  }

  Future<void> _getUserData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        _updateLog("❌ لا يوجد مستخدم مسجل");
        return;
      }
      
      final snap = await FirebaseFirestore.instance
          .collection('managers')
          .where('uid', isEqualTo: user.uid)
          .get();

      if (snap.docs.isNotEmpty) {
        var doc = snap.docs.first;
        var data = doc.data();
        role = data['role'];
        myAreas = List<String>.from(data['geographicArea'] ?? []);
        _updateLog("👤 الدور: $role | المناطق: ${myAreas.length}");

        if (role == 'delivery_supervisor') {
          final repsSnap = await FirebaseFirestore.instance
              .collection('deliveryReps')
              .where('supervisorId', isEqualTo: doc.id)
              .get();
          myReps = repsSnap.docs.map((d) => {
            'id': d.id, 
            'fullname': d['fullname'], 
            'repCode': d['repCode']
          }).toList();
          _updateLog("👥 الفريق: ${myReps.length} مناديب");
        }
      } else {
        _updateLog("❌ لم يتم العثور على حسابك في Firestore");
      }
    } catch (e) {
      _updateLog("❌ خطأ في الـ User Data: $e");
    }
  }

  bool _isPointInPolygon(LatLng point, List<LatLng> polygon) {
    var lat = point.latitude;
    var lng = point.longitude;
    var inside = false;
    for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      var xi = polygon[i].latitude, yi = polygon[i].longitude;
      var xj = polygon[j].latitude, yj = polygon[j].longitude;
      var intersect = ((yi > lng) != (yj > lng)) && 
          (lat < (xj - xi) * (lng - yi) / (yj - yi) + xi);
      if (intersect) inside = !inside;
    }
    return inside;
  }

  bool _isOrderInMyArea(Map<String, dynamic> locationData, String orderId) {
    if (role == 'delivery_manager') return true;
    if (geoJsonData == null || myAreas.isEmpty) return false;

    double lat = (locationData['lat'] as num).toDouble();
    double lng = (locationData['lng'] as num).toDouble();
    LatLng orderPoint = LatLng(lat, lng);

    for (var areaName in myAreas) {
      var feature = geoJsonData!['features'].firstWhere(
          (f) => f['properties']['name'].toString().trim() == areaName.trim(), 
          orElse: () => null);

      if (feature == null) continue;

      try {
        var geometry = feature['geometry'];
        var type = geometry['type'];
        var coords = geometry['coordinates'];

        if (type == 'Polygon') {
          for (var ring in coords) {
            List<LatLng> polyPoints = (ring as List).map<LatLng>((c) =>
                LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble())).toList();
            if (_isPointInPolygon(orderPoint, polyPoints)) return true;
          }
        } 
        else if (type == 'MultiPolygon') {
          for (var polygonData in coords) {
            for (var ring in polygonData) {
              List<LatLng> polyPoints = (ring as List).map<LatLng>((c) =>
                  LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble())).toList();
              if (_isPointInPolygon(orderPoint, polyPoints)) return true;
            }
          }
        }
      } catch (e) {
        _updateLog("🚨 خطأ في منطقة $areaName");
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(role == 'delivery_manager' ? "إدارة المدير" : "إدارة المشرف"),
        backgroundColor: const Color(0xFF2F3542),
      ),
      body: Column(
        children: [
          // كونسول المراقبة لمتابعة الاتصال
          Container(
            height: 12.h,
            width: double.infinity,
            margin: const EdgeInsets.all(8),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(10)),
            child: SingleChildScrollView(
              reverse: true,
              child: Text(debugConsole, 
                style: const TextStyle(color: Colors.greenAccent, fontSize: 9, fontFamily: 'monospace')),
            ),
          ),
          
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance.collection('orders').snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: Text("جاري الاتصال بالسيرفر..."));
                      }
                      if (snapshot.hasError) {
                        _updateLog("🚨 خطأ فايربيز: ${snapshot.error}");
                        return Center(child: Text("حدث خطأ في جلب البيانات"));
                      }
                      if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                        return const Center(child: Text("لا توجد طلبات في السجل"));
                      }

                      _updateLog("📥 استلمت ${snapshot.data!.docs.length} طلبات");

                      var filteredOrders = snapshot.data!.docs.where((doc) {
                        var data = doc.data() as Map<String, dynamic>;
                        
                        if (role == 'delivery_manager') {
                          return data['status'] == 'new-order' && data['deliveryManagerAssigned'] != true;
                        } else if (role == 'delivery_supervisor') {
                          bool isApproved = data['deliveryManagerAssigned'] == true;
                          bool noRep = data['deliveryRepId'] == null;
                          bool active = data['status'] != 'delivered';
                          
                          if (isApproved && noRep && active) {
                            if (data['buyer'] != null && data['buyer']['location'] != null) {
                              return _isOrderInMyArea(data['buyer']['location'], doc.id);
                            }
                          }
                        }
                        return false;
                      }).toList();

                      _updateLog("🎯 متاح لمنطقتك: ${filteredOrders.length} طلب");

                      if (filteredOrders.isEmpty) {
                        return const Center(child: Text("لا توجد طلبات مطابقة لمنطقتك"));
                      }

                      return ListView.builder(
                        itemCount: filteredOrders.length,
                        itemBuilder: (context, index) {
                          return _buildOrderCard(filteredOrders[index].id, 
                              filteredOrders[index].data() as Map<String, dynamic>);
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Padding(
        padding: EdgeInsets.all(12.sp),
        child: Column(
          children: [
            ListTile(
              title: Text("طلب: #${orderId.substring(0,6)}", style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text("العميل: ${order['buyer']['name']}"),
              trailing: Text("${order['total']} ج.م", style: const TextStyle(color: Colors.green)),
            ),
            if (role == 'delivery_manager')
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                onPressed: () => _managerMoveToDelivery(orderId),
                child: const Text("موافقة ونقل للمشرف الجغرافي", style: TextStyle(color: Colors.white)),
              ),
            if (role == 'delivery_supervisor') _buildSupervisorAction(orderId, order),
          ],
        ),
      ),
    );
  }

  Future<void> _managerMoveToDelivery(String id) async {
    await FirebaseFirestore.instance.collection('orders').doc(id).update({'deliveryManagerAssigned': true});
    _updateLog("✅ تم نقل الطلب $id للمشرف");
  }

  Widget _buildSupervisorAction(String orderId, Map<String, dynamic> orderData) {
    return Column(
      children: [
        const Divider(),
        DropdownButton<String>(
          isExpanded: true,
          hint: const Text("اختر مندوب للإسناد"),
          items: myReps.map((rep) => DropdownMenuItem(
            value: rep['repCode'].toString(),
            child: Text(rep['fullname']),
          )).toList(),
          onChanged: (val) {
            if (val != null) {
              var rep = myReps.firstWhere((r) => r['repCode'] == val);
              _assignToRep(orderId, orderData, rep);
            }
          },
        ),
      ],
    );
  }

  Future<void> _assignToRep(String id, Map<String, dynamic> data, Map rep) async {
    try {
      await FirebaseFirestore.instance.collection('orders').doc(id).update({
        'deliveryRepId': rep['repCode'],
        'repName': rep['fullname'],
      });
      _updateLog("✅ تم الإسناد لـ ${rep['fullname']}");
    } catch (e) {
      _updateLog("❌ فشل الإسناد: $e");
    }
  }
}

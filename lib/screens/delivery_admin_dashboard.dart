import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:sizer/sizer.dart';

// استدعاء الصفحات التابعة
import 'delivery_management_screen.dart'; 
import 'delivery_fleet_screen.dart';      
import 'manager_geo_dist_screen.dart';    

class DeliveryAdminDashboard extends StatefulWidget {
  const DeliveryAdminDashboard({super.key});

  @override
  State<DeliveryAdminDashboard> createState() => _DeliveryAdminDashboardState();
}

class _DeliveryAdminDashboardState extends State<DeliveryAdminDashboard> {
  final String? _uid = FirebaseAuth.instance.currentUser?.uid;
  Map<String, dynamic>? _userData;
  bool _isLoading = true;

  // إحصائيات اللوحة
  int _totalOrders = 0;
  double _totalSales = 0;
  int _totalReps = 0;
  double _avgRating = 0;

  @override
  void initState() {
    super.initState();
    _checkAuthAndLoadData();
  }

  Future<void> _checkAuthAndLoadData() async {
    try {
      var managerSnap = await FirebaseFirestore.instance
          .collection('managers')
          .where('uid', isEqualTo: _uid)
          .get();

      if (managerSnap.docs.isNotEmpty) {
        var doc = managerSnap.docs.first;
        _userData = doc.data();
        String role = _userData!['role'] ?? 'delivery_supervisor';
        String managerDocId = doc.id;

        await _loadStats(role, managerDocId);
      }

      if (mounted) setState(() => _isLoading = false);
    } catch (e) {
      debugPrint("Dashboard Error: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadStats(String role, String managerDocId) async {
    Query ordersQuery = FirebaseFirestore.instance.collection('orders');
    Query repsQuery = FirebaseFirestore.instance.collection('deliveryReps');

    if (role == 'delivery_supervisor') {
      var myReps = await repsQuery.where('supervisorId', isEqualTo: managerDocId).get();
      _totalReps = myReps.size;

      if (myReps.docs.isNotEmpty) {
        List<String> repCodes = myReps.docs.map((d) => d['repCode'] as String).toList();
        ordersQuery = ordersQuery.where('buyer.repCode', whereIn: repCodes);
      } else {
        return;
      }
    } else {
      var allReps = await repsQuery.get();
      _totalReps = allReps.size;
    }

    var ordersSnap = await ordersQuery.get();
    _totalOrders = ordersSnap.size;

    double salesSum = 0;
    double ratingsSum = 0;
    int ratedCount = 0;

    for (var doc in ordersSnap.docs) {
      var data = doc.data() as Map<String, dynamic>;
      salesSum += (data['total'] ?? 0).toDouble();
      if (data['rating'] != null) {
        ratingsSum += data['rating'].toDouble();
        ratedCount++;
      }
    }

    _totalSales = salesSum;
    _avgRating = ratedCount > 0 ? ratingsSum / ratedCount : 0;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator(color: Colors.orange)));

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        title: Text(_userData?['role'] == 'delivery_manager' ? "لوحة مدير التوصيل" : "لوحة مشرف التوصيل",
            style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF2F3542),
        centerTitle: true,
        elevation: 0,
      ),
      drawer: _buildDrawer(),
      body: Padding(
        padding: EdgeInsets.all(15.sp),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("مرحباً بك، ${_userData?['fullname'] ?? ''}",
                style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
            SizedBox(height: 2.h),
            Expanded(
              child: GridView.count(
                crossAxisCount: 2,
                crossAxisSpacing: 15,
                mainAxisSpacing: 15,
                children: [
                  _buildStatCard("إجمالي الطلبات", "$_totalOrders", Icons.inventory_2, Colors.blue),
                  _buildStatCard("إجمالي التحصيل", "${_totalSales.toStringAsFixed(0)} ج.م", Icons.payments, Colors.green),
                  _buildStatCard("عدد المناديب", "$_totalReps", Icons.groups, Colors.orange),
                  _buildStatCard("متوسط التقييم", _avgRating.toStringAsFixed(1), Icons.star, Colors.amber),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: EdgeInsets.all(12.sp),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 28.sp),
          SizedBox(height: 1.h),
          Text(title, style: TextStyle(fontSize: 10.sp, color: Colors.grey[600], fontFamily: 'Cairo')),
          Text(value,
              style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.bold, color: color, fontFamily: 'Cairo'),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: const BoxDecoration(color: Color(0xFF2F3542)),
            child: Center(
                child: Text("أكسب - إدارة التوصيل", 
                  style: TextStyle(color: Colors.white, fontSize: 16.sp, fontFamily: 'Cairo', fontWeight: FontWeight.bold))),
          ),
          
          _drawerItem(Icons.analytics, "تقارير الطلبات", () {
            Navigator.pop(context); // إغلاق الدرور أولاً
            Navigator.push(context, MaterialPageRoute(builder: (context) => const DeliveryManagementScreen()));
          }),

          _drawerItem(Icons.people_alt, "إدارة المناديب", () {
            Navigator.pop(context);
            Navigator.push(context, MaterialPageRoute(builder: (context) => const DeliveryFleetScreen()));
          }),

          if (_userData?['role'] == 'delivery_manager')
            _drawerItem(Icons.map, "مناطق التوصيل", () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (context) => const ManagerGeoDistScreen()));
            }),

          const Divider(),
          
          // أيقونة تسجيل الخروج مع التنبيه
          _drawerItem(Icons.logout, "تسجيل الخروج", () {
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                title: const Text("تسجيل الخروج", style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                content: const Text("هل أنت متأكد أنك تريد مغادرة لوحة التحكم؟", style: TextStyle(fontFamily: 'Cairo')),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context), 
                    child: const Text("إلغاء", style: TextStyle(fontFamily: 'Cairo', color: Colors.grey))
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))
                    ),
                    onPressed: () async {
                      await FirebaseAuth.instance.signOut();
                      if (context.mounted) {
                        // يتم الانتقال لصفحة تسجيل الدخول وحذف كل السجلات السابقة
                        Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
                      }
                    },
                    child: const Text("خروج", style: TextStyle(color: Colors.white, fontFamily: 'Cairo')),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _drawerItem(IconData icon, String title, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: const Color(0xFF1ABC9C)),
      title: Text(title, style: TextStyle(fontSize: 12.sp, fontFamily: 'Cairo', fontWeight: FontWeight.w600)),
      onTap: onTap,
    );
  }
}

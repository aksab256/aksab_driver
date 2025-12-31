import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:sizer/sizer.dart';

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
      // 1. التحقق من الدور في كولكشن managers
      // تم التصحيح هنا ليعمل بأسلوب Flutter
      var managerSnap = await FirebaseFirestore.instance
          .collection('managers')
          .where('uid', isEqualTo: _uid)
          .get();

      if (managerSnap.docs.isNotEmpty) {
        var doc = managerSnap.docs.first;
        _userData = doc.data();
        String role = _userData!['role'];
        String managerDocId = doc.id; 

        // 2. تحميل البيانات بناءً على الصلاحيات
        await _loadStats(role, managerDocId);
      }
      
      if (mounted) setState(() => _isLoading = false);
    } catch (e) {
      debugPrint("Dashboard Error: $e");
    }
  }

  Future<void> _loadStats(String role, String managerDocId) async {
    Query ordersQuery = FirebaseFirestore.instance.collection('orders');
    Query repsQuery = FirebaseFirestore.instance.collection('deliveryReps');

    if (role == 'delivery_supervisor') {
      // تم التصحيح هنا باستخدام isEqualTo
      var myReps = await repsQuery.where('supervisorId', isEqualTo: managerDocId).get();
      _totalReps = myReps.size;

      if (myReps.docs.isNotEmpty) {
        List<String> repCodes = myReps.docs.map((d) => d['repCode'] as String).toList();
        // فلترة الطلبات بواسطة أكواد المناديب
        ordersQuery = ordersQuery.where('buyer.repCode', whereIn: repCodes);
      } else {
        return; 
      }
    } else {
      // المدير يرى الكل
      var allReps = await repsQuery.get();
      _totalReps = allReps.size;
    }

    // جلب الطلبات وحساب الإجماليات
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
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        title: Text(_userData?['role'] == 'delivery_manager' ? "لوحة مدير التوصيل" : "لوحة مشرف التوصيل"),
        backgroundColor: const Color(0xFF2F3542),
        centerTitle: true,
      ),
      drawer: _buildDrawer(),
      body: Padding(
        padding: EdgeInsets.all(15.sp),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("مرحباً بك، ${_userData?['fullname'] ?? ''}", 
              style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold)),
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
          BoxShadow(
            color: Colors.black.withOpacity(0.1), // تصحيح لون الظل
            blurRadius: 8,
          )
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 28.sp),
          SizedBox(height: 1.h),
          Text(title, style: TextStyle(fontSize: 10.sp, color: Colors.grey[600])),
          Text(value, style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      child: ListView(
        children: [
          DrawerHeader(
            decoration: const BoxDecoration(color: Color(0xFF2F3542)),
            child: Center(child: Text("أكسب - إدارة التوصيل", style: TextStyle(color: Colors.white, fontSize: 18.sp))),
          ),
          _drawerItem(Icons.analytics, "تقارير الطلبات", () {}),
          _drawerItem(Icons.people, "إدارة المناديب", () {}),
          if (_userData?['role'] == 'delivery_manager')
            _drawerItem(Icons.map, "مناطق المشرفين", () {}),
          const Divider(),
          _drawerItem(Icons.logout, "تسجيل الخروج", () => FirebaseAuth.instance.signOut()),
        ],
      ),
    );
  }

  Widget _drawerItem(IconData icon, String title, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: const Color(0xFF1ABC9C)),
      title: Text(title, style: TextStyle(fontSize: 12.sp)),
      onTap: onTap,
    );
  }
}


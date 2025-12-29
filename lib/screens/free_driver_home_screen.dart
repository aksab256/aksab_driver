import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:sizer/sizer.dart';
import 'available_orders_screen.dart';
import 'active_order_screen.dart'; 
import 'wallet_screen.dart';

class FreeDriverHomeScreen extends StatefulWidget {
  const FreeDriverHomeScreen({super.key});

  @override
  State<FreeDriverHomeScreen> createState() => _FreeDriverHomeScreenState();
}

class _FreeDriverHomeScreenState extends State<FreeDriverHomeScreen> {
  bool isOnline = false;
  int _selectedIndex = 0;
  bool _showHandHint = false;
  String? _activeOrderId;

  @override
  void initState() {
    super.initState();
    _fetchInitialStatus();
    _listenToActiveOrders();
  }

  // مراقبة الطلبات النشطة (المقبولة أو الجاري استلامها)
  void _listenToActiveOrders() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    FirebaseFirestore.instance
        .collection('specialRequests')
        .where('driverId', isEqualTo: uid)
        .where('status', whereIn: ['accepted', 'picked_up'])
        .snapshots()
        .listen((snapshot) {
      if (mounted) {
        setState(() {
          _activeOrderId = snapshot.docs.isNotEmpty ? snapshot.docs.first.id : null;
        });
      }
    });
  }

  void _fetchInitialStatus() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      var doc = await FirebaseFirestore.instance.collection('freeDrivers').doc(uid).get();
      if (doc.exists && mounted) {
        setState(() {
          isOnline = doc.data()?['isOnline'] ?? false;
        });
      }
    }
  }

  void _toggleOnlineStatus(bool value) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      await FirebaseFirestore.instance.collection('freeDrivers').doc(uid).update({
        'isOnline': value,
        'lastSeen': FieldValue.serverTimestamp(),
      });
      setState(() {
        isOnline = value;
        if (isOnline) _showHandHint = true;
      });
      if (isOnline) {
        Future.delayed(const Duration(seconds: 4), () {
          if (mounted) setState(() => _showHandHint = false);
        });
      }
    }
  }

  void _showStatusAlert() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off, size: 40.sp, color: Colors.redAccent),
            const SizedBox(height: 15),
            Text("وضع العمل غير نشط", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18.sp)),
            const SizedBox(height: 10),
            Text("برجاء تفعيل زر الاتصال بالأعلى أولاً لتتمكن من رؤية طلبات الرادار",
                textAlign: TextAlign.center, style: TextStyle(fontSize: 14.sp, color: Colors.grey[600])),
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green, padding: EdgeInsets.symmetric(horizontal: 30, vertical: 10)),
              onPressed: () => Navigator.pop(context),
              child: Text("فهمت", style: TextStyle(color: Colors.white, fontSize: 16.sp)),
            )
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> _pages = [
      _buildDashboardContent(),
      _activeOrderId != null ? ActiveOrderScreen(orderId: _activeOrderId!) : const AvailableOrdersScreen(),
      const Center(child: Text("سجل الطلبات قريباً")),
      const WalletScreen(),
    ];

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        title: Text(
          _activeOrderId != null ? "طلب نشط حالياً" : "لوحة التحكم",
          style: TextStyle(color: Colors.black, fontSize: 18.sp, fontWeight: FontWeight.w900),
        ),
        centerTitle: true,
        actions: [
          Row(
            children: [
              Text(isOnline ? "متصل" : "مختفي",
                  style: TextStyle(color: isOnline ? Colors.green : Colors.red, fontSize: 12.sp, fontWeight: FontWeight.bold)),
              Transform.scale(
                scale: 1.1,
                child: Switch(
                  value: isOnline,
                  activeColor: Colors.green,
                  onChanged: _toggleOnlineStatus,
                ),
              ),
            ],
          ),
          SizedBox(width: 2.w),
        ],
      ),
      body: Stack(
        children: [
          _pages[_selectedIndex],
          if (_showHandHint && _selectedIndex == 0 && _activeOrderId == null)
            Positioned(
              bottom: 2.h,
              left: 25.w,
              child: _buildHandPointer(),
            ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) {
          if (index == 1 && !isOnline && _activeOrderId == null) {
            _showStatusAlert();
            return;
          }
          setState(() => _selectedIndex = index);
        },
        selectedItemColor: Colors.orange[900],
        unselectedItemColor: Colors.grey[600],
        selectedLabelStyle: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.bold),
        type: BottomNavigationBarType.fixed,
        items: [
          const BottomNavigationBarItem(icon: Icon(Icons.dashboard), label: "الرئيسية"),
          BottomNavigationBarItem(
            icon: _activeOrderId != null
                ? const Icon(Icons.directions_run, color: Colors.green)
                : (isOnline ? _buildPulseIcon() : Opacity(opacity: 0.4, child: const Icon(Icons.radar))),
            label: _activeOrderId != null ? "الطلب النشط" : "الرادار",
          ),
          const BottomNavigationBarItem(icon: Icon(Icons.history), label: "طلباتي"),
          const BottomNavigationBarItem(icon: Icon(Icons.account_balance_wallet), label: "المحفظة"),
        ],
      ),
    );
  }

  Widget _buildDashboardContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          if (_activeOrderId != null) _activeOrderBanner(),
          // بطاقة الحالة (متصل/مختفي)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isOnline ? Colors.green[50] : Colors.red[50],
              borderRadius: BorderRadius.circular(25),
              border: Border.all(color: isOnline ? Colors.green : Colors.red, width: 2),
            ),
            child: Row(
              children: [
                Icon(isOnline ? Icons.check_circle : Icons.do_not_disturb_on, color: isOnline ? Colors.green : Colors.red, size: 35.sp),
                const SizedBox(width: 15),
                Expanded(
                    child: Text(isOnline ? "أنت متاح الآن لاستقبال الطلبات" : "أنت حالياً خارج التغطية",
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15.sp))),
              ],
            ),
          ),
          const SizedBox(height: 25),
          // الإحصائيات الحقيقية
          _buildLiveStatsGrid(),
        ],
      ),
    );
  }

  // محرك الإحصائيات الحية
  Widget _buildLiveStatsGrid() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('specialRequests')
          .where('driverId', isEqualTo: uid)
          .where('status', isEqualTo: 'delivered')
          .snapshots(),
      builder: (context, snapshot) {
        double todayEarnings = 0.0;
        int completedCount = 0;

        if (snapshot.hasData) {
          var docs = snapshot.data!.docs;
          completedCount = docs.length;
          for (var doc in docs) {
            final data = doc.data() as Map<String, dynamic>;
            todayEarnings += (data['deliveryFee'] as num? ?? 0.0).toDouble();
          }
        }

        return GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          crossAxisSpacing: 15,
          mainAxisSpacing: 15,
          childAspectRatio: 1.0,
          children: [
            _statCard("أرباح اليوم", "${todayEarnings.toStringAsFixed(2)} ج.م", Icons.monetization_on, Colors.blue),
            _statCard("طلبات منفذة", "$completedCount", Icons.shopping_basket, Colors.orange),
            _statCard("تقييمك", "5.0", Icons.star, Colors.amber),
            _statCard("ساعات العمل", "نشط", Icons.timer, Colors.purple),
          ],
        );
      },
    );
  }

  Widget _statCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: Colors.white, 
          borderRadius: BorderRadius.circular(20), 
          boxShadow: [const BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 5))]),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 30.sp),
          const SizedBox(height: 10),
          Text(title, style: TextStyle(color: Colors.grey[600], fontSize: 12.sp, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          // الرقم الأساسي ضخم وواضح جداً (18.sp)
          FittedBox(
            child: Text(value, 
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18.sp, color: Colors.black)),
          ),
        ],
      ),
    );
  }

  // البنرات والأيقونات المتحركة كما هي مع تحسين الخط
  Widget _activeOrderBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(color: Colors.orange[900], borderRadius: BorderRadius.circular(20)),
      child: Row(
        children: [
          const Icon(Icons.delivery_dining, color: Colors.white, size: 30),
          const SizedBox(width: 10),
          Expanded(child: Text("لديك طلب قيد التنفيذ", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14.sp))),
          TextButton(
            onPressed: () => setState(() => _selectedIndex = 1),
            child: Text("تابعه الآن", style: TextStyle(color: Colors.yellow, fontWeight: FontWeight.bold, fontSize: 14.sp)),
          )
        ],
      ),
    );
  }

  Widget _buildHandPointer() {
    return TweenAnimationBuilder(
      tween: Tween<double>(begin: 0, end: 15),
      duration: const Duration(milliseconds: 600),
      builder: (context, double value, child) {
        return Transform.translate(
          offset: Offset(0, -value),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: Colors.orange[900], borderRadius: BorderRadius.circular(10)),
                child: Text("ابدأ من هنا", style: TextStyle(color: Colors.white, fontSize: 12.sp, fontWeight: FontWeight.bold)),
              ),
              Icon(Icons.pan_tool_alt, size: 35.sp, color: Colors.orange[900]),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPulseIcon() {
    return TweenAnimationBuilder(
      tween: Tween<double>(begin: 1.0, end: 1.3),
      duration: const Duration(milliseconds: 1000),
      builder: (context, double scale, child) {
        return Transform.scale(
          scale: scale,
          child: Icon(Icons.radar, color: Color.lerp(Colors.orange[900], Colors.red, (scale - 1) * 3)),
        );
      },
      onEnd: () => setState(() {}),
    );
  }
}


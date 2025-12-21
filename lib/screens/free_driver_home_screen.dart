import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:sizer/sizer.dart';
import 'available_orders_screen.dart';
import 'active_order_screen.dart'; // الصفحة التي صممناها بـ CartoDB
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
  String? _activeOrderId; // لتخزين معرف الطلب النشط إن وجد

  @override
  void initState() {
    super.initState();
    _fetchInitialStatus();
    _listenToActiveOrders(); // البدء في مراقبة الطلبات النشطة
  }

  // مراقبة فورية لأي طلب نشط يخص هذا المندوب
  void _listenToActiveOrders() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    FirebaseFirestore.instance
        .collection('specialRequests')
        .where('driverId', isEqualTo: uid)
        .where('status', whereIn: ['accepted', 'picked_up'])
        .snapshots()
        .listen((snapshot) {
      if (snapshot.docs.isNotEmpty) {
        if (mounted) {
          setState(() {
            _activeOrderId = snapshot.docs.first.id;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _activeOrderId = null;
          });
        }
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
            Text("وضع العمل غير نشط", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.sp)),
            const SizedBox(height: 10),
            Text("برجاء تفعيل زر الاتصال بالأعلى أولاً لتتمكن من رؤية طلبات الرادار",
                textAlign: TextAlign.center, style: TextStyle(fontSize: 11.sp, color: Colors.grey[600])),
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              onPressed: () => Navigator.pop(context),
              child: const Text("فهمت", style: TextStyle(color: Colors.white)),
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
        title: Text(_activeOrderId != null ? "طلب نشط حالياً" : "لوحة التحكم",
            style: TextStyle(color: Colors.black, fontSize: 16.sp, fontWeight: FontWeight.bold)),
        centerTitle: true,
        actions: [
          Row(
            children: [
              Text(isOnline ? "متصل" : "مختفي",
                  style: TextStyle(color: isOnline ? Colors.green : Colors.red, fontSize: 10.sp, fontWeight: FontWeight.bold)),
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
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: Colors.orange[900], borderRadius: BorderRadius.circular(8)),
                child: Text("ابدأ من هنا", style: TextStyle(color: Colors.white, fontSize: 10.sp)),
              ),
              Icon(Icons.pan_tool_alt, size: 30.sp, color: Colors.orange[900]),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPulseIcon() {
    return TweenAnimationBuilder(
      tween: Tween<double>(begin: 1.0, end: 1.2),
      duration: const Duration(milliseconds: 1000),
      builder: (context, double scale, child) {
        return Transform.scale(
          scale: scale,
          child: Icon(
            Icons.radar,
            color: Color.lerp(Colors.orange[900], Colors.red, (scale - 1) * 5),
          ),
        );
      },
      onEnd: () => setState(() {}),
    );
  }

  Widget _buildDashboardContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          if (_activeOrderId != null) _activeOrderBanner(),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isOnline ? Colors.green[50] : Colors.red[50],
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: isOnline ? Colors.green : Colors.red, width: 2),
            ),
            child: Row(
              children: [
                Icon(isOnline ? Icons.check_circle : Icons.do_not_disturb_on, color: isOnline ? Colors.green : Colors.red, size: 30.sp),
                const SizedBox(width: 15),
                Expanded(
                    child: Text(isOnline ? "أنت متاح الآن لاستقبال الطلبات" : "أنت حالياً خارج التغطية",
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.sp))),
              ],
            ),
          ),
          const SizedBox(height: 25),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            crossAxisSpacing: 15,
            mainAxisSpacing: 15,
            childAspectRatio: 1.1,
            children: [
              _statCard("أرباح اليوم", "0.00 ج.م", Icons.monetization_on, Colors.blue),
              _statCard("طلبات منفذة", "0", Icons.shopping_basket, Colors.orange),
              _statCard("تقييمك", "5.0", Icons.star, Colors.amber),
              _statCard("ساعات العمل", "0h", Icons.timer, Colors.purple),
            ],
          ),
        ],
      ),
    );
  }

  Widget _activeOrderBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 15), // ✅ تم إصلاح الخطأ هنا
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(color: Colors.orange[900], borderRadius: BorderRadius.circular(15)),
      child: Row(
        children: [
          const Icon(Icons.delivery_dining, color: Colors.white),
          const SizedBox(width: 10),
          const Expanded(child: Text("لديك طلب قيد التنفيذ حالياً", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
          TextButton(
            onPressed: () => setState(() => _selectedIndex = 1),
            child: const Text("تابعه الآن", style: TextStyle(color: Colors.yellow, fontWeight: FontWeight.bold)),
          )
        ],
      ),
    );
  }

  Widget _statCard(String title, String value, IconData icon, Color color) {
    return Container(
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [const BoxShadow(color: Colors.black12, blurRadius: 5)]),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 25.sp),
          const SizedBox(height: 8),
          Text(title, style: TextStyle(color: Colors.grey[700], fontSize: 11.sp)),
          Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.sp)),
        ],
      ),
    );
  }
}

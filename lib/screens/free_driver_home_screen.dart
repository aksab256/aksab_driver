import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:sizer/sizer.dart';
import 'available_orders_screen.dart';
import 'wallet_screen.dart';

class FreeDriverHomeScreen extends StatefulWidget {
  const FreeDriverHomeScreen({super.key});

  @override
  State<FreeDriverHomeScreen> createState() => _FreeDriverHomeScreenState();
}

class _FreeDriverHomeScreenState extends State<FreeDriverHomeScreen> {
  bool isOnline = false;
  int _selectedIndex = 0;
  bool _showHandHint = false; // التحكم في ظهور اليد

  @override
  void initState() {
    super.initState();
    _fetchInitialStatus();
  }

  // جلب الحالة الحالية من Firestore عند فتح التطبيق
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
        if (isOnline) _showHandHint = true; // إظهار اليد عند التفعيل
      });

      // إخفاء اليد تلقائياً بعد 4 ثواني
      if (isOnline) {
        Future.delayed(const Duration(seconds: 4), () {
          if (mounted) setState(() => _showHandHint = false);
        });
      }
    }
  }

  // رسالة تنبيه عائمة إذا حاول دخول الرادار وهو Offline
  void _showStatusAlert() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off, size: 40.sp, color: Colors.redAccent),
            SizedBox(height: 15),
            Text("وضع العمل غير نشط", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.sp)),
            SizedBox(height: 10),
            Text("برجاء تفعيل زر الاتصال بالأعلى أولاً لتتمكن من رؤية طلبات الرادار",
                textAlign: TextAlign.center, style: TextStyle(fontSize: 11.sp, color: Colors.grey[600])),
            SizedBox(height: 20),
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
      const AvailableOrdersScreen(),
      const Center(child: Text("سجل الطلبات قريباً")),
      const WalletScreen(),
    ];

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        title: Text("لوحة التحكم", style: TextStyle(color: Colors.black, fontSize: 16.sp, fontWeight: FontWeight.bold)),
        centerTitle: true,
        actions: [
          Row(
            children: [
              Text(isOnline ? "متصل" : "مختفي", style: TextStyle(color: isOnline ? Colors.green : Colors.red, fontSize: 10.sp, fontWeight: FontWeight.bold)),
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
          
          // 💡 أنيميشن اليد التي تشير للأيقونة
          if (_showHandHint && _selectedIndex == 0)
            Positioned(
              bottom: 2.h,
              left: 25.w, // موضع تقريبي فوق أيقونة الرادار
              child: TweenAnimationBuilder(
                tween: Tween<double>(begin: 0, end: 15),
                duration: const Duration(milliseconds: 600),
                builder: (context, double value, child) {
                  return Transform.translate(
                    offset: Offset(0, -value),
                    child: Column(
                      children: [
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(color: Colors.orange[900], borderRadius: BorderRadius.circular(8)),
                          child: Text("ابدأ من هنا", style: TextStyle(color: Colors.white, fontSize: 10.sp)),
                        ),
                        Icon(Icons.pan_tool_alt, size: 30.sp, color: Colors.orange[900]),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) {
          if (index == 1 && !isOnline) {
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
            icon: isOnline ? _buildPulseIcon() : Opacity(opacity: 0.4, child: Icon(Icons.radar)),
            label: "الرادار",
          ),
          const BottomNavigationBarItem(icon: Icon(Icons.history), label: "طلباتي"),
          const BottomNavigationBarItem(icon: Icon(Icons.account_balance_wallet), label: "المحفظة"),
        ],
      ),
    );
  }

  // ويدجت أيقونة الرادار التي تنبض (تتوهج)
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
      onEnd: () => setState(() {}), // تكرار الأنيميشن
    );
  }

  Widget _buildDashboardContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
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
                Icon(isOnline ? Icons.check_circle : Icons.do_not_disturb_on,
                    color: isOnline ? Colors.green : Colors.red, size: 30.sp),
                const SizedBox(width: 15),
                Expanded(child: Text(isOnline ? "أنت متاح الآن لاستقبال الطلبات" : "أنت حالياً خارج التغطية",
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

  Widget _statCard(String title, String value, IconData icon, Color color) {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 5)]),
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

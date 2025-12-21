import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:sizer/sizer.dart';
import 'available_orders_screen.dart'; 
import 'wallet_screen.dart'; // 💡 استيراد شاشة المحفظة الجديدة

class FreeDriverHomeScreen extends StatefulWidget {
  const FreeDriverHomeScreen({super.key});

  @override
  State<FreeDriverHomeScreen> createState() => _FreeDriverHomeScreenState();
}

class _FreeDriverHomeScreenState extends State<FreeDriverHomeScreen> {
  bool isOnline = false;
  int _selectedIndex = 0;

  void _toggleOnlineStatus(bool value) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      await FirebaseFirestore.instance.collection('freeDrivers').doc(uid).update({
        'isOnline': value,
        'lastSeen': FieldValue.serverTimestamp(),
      });
      setState(() => isOnline = value);
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(value ? "أنت الآن متصل" : "تم تسجيل الخروج", 
        style: TextStyle(fontSize: 12.sp), textAlign: TextAlign.center))
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> _pages = [
      _buildDashboardContent(),
      const AvailableOrdersScreen(),
      const Center(child: Text("سجل الطلبات قريباً")),
      const WalletScreen(), // 💡 تفعيل صفحة المحفظة هنا
    ];

    return Scaffold(
      backgroundColor: Colors.grey[100],
      drawer: _buildSidebar(context),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        title: Text("لوحة التحكم", 
          style: TextStyle(color: Colors.black, fontSize: 18.sp, fontWeight: FontWeight.bold)),
        centerTitle: true,
        iconTheme: IconThemeData(color: Colors.black, size: 22.sp),
        actions: [
          Transform.scale(
            scale: 1.2,
            child: Switch(
              value: isOnline,
              activeColor: Colors.green,
              onChanged: _toggleOnlineStatus,
            ),
          ),
          SizedBox(width: 3.w),
        ],
      ),
      body: _pages[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        selectedItemColor: Colors.orange[900],
        unselectedItemColor: Colors.grey[600],
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.dashboard), label: "الرئيسية"),
          BottomNavigationBarItem(icon: Icon(Icons.radar), label: "الرادار"),
          BottomNavigationBarItem(icon: Icon(Icons.history), label: "طلباتي"),
          BottomNavigationBarItem(icon: Icon(Icons.account_balance_wallet), label: "المحفظة"),
        ],
      ),
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
                  color: isOnline ? Colors.green : Colors.red, size: 35.sp),
                const SizedBox(width: 20),
                Expanded(child: Text(isOnline ? "أنت متاح للاستلام" : "أنت غير متصل",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15.sp))),
              ],
            ),
          ),
          const SizedBox(height: 25),
          _buildQuickStats(),
        ],
      ),
    );
  }

  Widget _buildQuickStats() {
    return GridView.count(
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
    );
  }

  Widget _statCard(String title, String value, IconData icon, Color color) {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20),
      boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 5)]),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 30.sp),
          const SizedBox(height: 10),
          Text(title, style: TextStyle(color: Colors.grey[700], fontSize: 12.sp)),
          // ✅ تم التصحيح لضمان نجاح الـ Build
          Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.sp, color: Colors.black87)),
        ],
      ),
    );
  }

  Widget _buildSidebar(BuildContext context) {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          UserAccountsDrawerHeader(
            decoration: BoxDecoration(color: Colors.orange[800]),
            accountName: Text("المندوب الحر", style: TextStyle(fontWeight: FontWeight.bold)),
            accountEmail: Text(FirebaseAuth.instance.currentUser?.email ?? ""),
          ),
          _sidebarItem(Icons.person, "الملف الشخصي"),
          _sidebarItem(Icons.settings, "إعدادات المركبة"),
          const Divider(),
          _sidebarItem(Icons.logout, "تسجيل الخروج", color: Colors.red, isLogout: true),
        ],
      ),
    );
  }

  // ✅ تم التصحيح هنا أيضاً لضمان نجاح الـ Build
  Widget _sidebarItem(IconData icon, String title, {Color color = Colors.black87, bool isLogout = false}) {
    return ListTile(
      leading: Icon(icon, color: color, size: 20.sp),
      title: Text(title, style: TextStyle(fontSize: 13.sp, color: color)),
      onTap: () {
        if (isLogout) FirebaseAuth.instance.signOut();
      },
    );
  }
}

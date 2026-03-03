import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:sizer/sizer.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:permission_handler/permission_handler.dart'; 
import 'package:geolocator/geolocator.dart'; // تأكد من إضافة هذه المكتبة

// الصفحات التابعة
import 'available_orders_screen.dart';
import 'active_order_screen.dart';
import 'wallet_screen.dart';
import 'orders_history_screen.dart';
import 'profile_screen.dart';
import 'support_screen.dart'; 
import 'freelance_terms_screen.dart'; 

class FreeDriverHomeScreen extends StatefulWidget {
  const FreeDriverHomeScreen({super.key});

  @override
  State<FreeDriverHomeScreen> createState() => _FreeDriverHomeScreenState();
}

class _FreeDriverHomeScreenState extends State<FreeDriverHomeScreen> {
  bool isOnline = false; 
  int _selectedIndex = 0;
  String? _activeOrderId;
  String _vehicleConfig = 'motorcycleConfig';
  bool _hasNewOrders = false; 
  final String uid = FirebaseAuth.instance.currentUser?.uid ?? "";
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  DateTime? _lastBackPressTime;

  @override
  void initState() {
    super.initState();
    _loadVehicleConfig();
    _fetchInitialStatus(); 
    _listenToActiveOrders();
    _listenToRadarNotifications();
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkSecurityAndTerms();
    });
  }

  // --- 🔔 سماع تنبيهات الرادار للنقطة الحمراء ---
  void _listenToRadarNotifications() {
    FirebaseFirestore.instance
        .collection('notifications')
        .where('userId', isEqualTo: uid)
        .where('eventType', isEqualTo: 'radar_new_order')
        .where('isRead', isEqualTo: false)
        .snapshots()
        .listen((snap) {
      if (mounted) {
        setState(() => _hasNewOrders = snap.docs.isNotEmpty);
      }
    });
  }

  // --- 🛡️ منطق التعامل مع زر الرجوع الذكي ---
  Future<bool> _handleWillPop() async {
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      Navigator.pop(context);
      return false;
    }
    if (_selectedIndex != 0) {
      setState(() => _selectedIndex = 0);
      return false;
    }
    DateTime now = DateTime.now();
    if (_lastBackPressTime == null || now.difference(_lastBackPressTime!) > const Duration(seconds: 2)) {
      _lastBackPressTime = now;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("إضغط مرة أخرى للخروج من التطبيق", 
            style: TextStyle(fontFamily: 'Cairo'), textAlign: TextAlign.center),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return false;
    }
    return true;
  }

  // --- 📍 منطق الأونلاين (نظام اللقطة الواحدة Snapshot) ---
  void _toggleOnlineStatus(bool value) async {
    if (value) {
      // فحص الأذونات بالترتيب الصحيح (Location ثم Always)
      var status = await Permission.location.status;
      if (status.isGranted) {
        _updateOnlineInDB(true);
      } else {
        _showLocationDisclosure();
      }
    } else {
      _updateOnlineInDB(false);
    }
  }

  void _showLocationDisclosure() async {
    bool? proceed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
        title: Row(
          children: [
            Icon(Icons.location_on, color: Colors.orange[900]),
            const SizedBox(width: 10),
            const Text("تحسين الرادار", style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        content: const Text(
          "يقوم تطبيق 'أكسب كابتن' بجمع بيانات الموقع لتمكين 'رادار الطلبات' وتتبع الرحلات النشطة لضمان النقل الآمن للعهدة، حتى عند إغلاق التطبيق أو عدم استخدامه.\n\n"
          "سيتم استخدام الموقع لـ:\n"
          "• عرض الطلبات المتاحة في نطاقك.\n"
          "• تحديث حالة العهدة في الوقت الفعلي أثناء الرحلات.",
          textAlign: TextAlign.right,
          style: TextStyle(fontFamily: 'Cairo', fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("ليس الآن", style: TextStyle(fontFamily: 'Cairo', color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange[900],
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text("موافق ومتابعة", style: TextStyle(fontFamily: 'Cairo', color: Colors.white)),
          ),
        ],
      ),
    );

    if (proceed == true) {
      if (await Permission.location.request().isGranted) {
        // نطلب Always لتكون جاهزة للطلب النشط (العهدة) مستقبلاً
        await Permission.locationAlways.request(); 
        _updateOnlineInDB(true);
      } else {
        _showPermissionDeniedSnackBar();
      }
    }
  }

  // التحديث بإرسال "لقطة" الموقع الحالية فقط لـ Firebase
  void _updateOnlineInDB(bool value) async {
    setState(() => isOnline = value);
    
    Map<String, dynamic> updateData = {
      'isOnline': value,
      'lastSeen': FieldValue.serverTimestamp(),
    };

    if (value) {
      try {
        // جلب الموقع الحالي (مرة واحدة)
        Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 5)
        );
        updateData['lat'] = position.latitude;
        updateData['lng'] = position.longitude;
        updateData['lastLocationUpdate'] = FieldValue.serverTimestamp();
      } catch (e) {
        debugPrint("⚠️ Location Error: $e");
      }
    }

    await FirebaseFirestore.instance.collection('freeDrivers').doc(uid).update(updateData);
  }

  void _showPermissionDeniedSnackBar() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("⚠️ يتطلب وضع الاتصال الوصول للموقع دائمًا", textAlign: TextAlign.center, style: TextStyle(fontFamily: 'Cairo')),
        backgroundColor: Colors.red,
      ),
    );
  }

  // --- 🛡️ بوابة الأمان وفحص الشروط ---
  Future<void> _checkSecurityAndTerms() async {
    if (uid.isEmpty) return;
    await Future.delayed(const Duration(milliseconds: 1000));
    try {
      var userDoc = await FirebaseFirestore.instance.collection('freeDrivers').doc(uid).get();
      bool hasAccepted = userDoc.exists ? (userDoc.data()?['hasAcceptedTerms'] ?? false) : false;

      if (!hasAccepted) {
        if (!mounted) return;
        final result = await showModalBottomSheet<bool>(
          context: context,
          isScrollControlled: true,
          isDismissible: false,
          enableDrag: false,
          backgroundColor: Colors.transparent,
          builder: (context) => FreelanceTermsScreen(userId: uid),
        );
        if (result == true) _requestNotificationPermissionWithDisclosure();
      } else {
        _requestNotificationPermissionWithDisclosure();
      }
    } catch (e) {
      debugPrint("⚠️ Security Check Error: $e");
    }
  }

  // --- 🔗 دالة ربط المندوب الحر بنظام AWS ---
  Future<void> _syncFreeDriverWithAWS() async {
    try {
      String? token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        const String apiUrl = "https://5uex7vzy64.execute-api.us-east-1.amazonaws.com/V2/new_nofiction";
        await http.post(
          Uri.parse(apiUrl),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode({"userId": uid, "fcmToken": token, "role": "free_driver"}),
        );
      }
    } catch (e) {
      debugPrint("❌ AWS Sync Error: $e");
    }
  }

  // --- 🔔 طلب إذن الإشعارات ---
  Future<void> _requestNotificationPermissionWithDisclosure() async {
    FirebaseMessaging messaging = FirebaseMessaging.instance;
    NotificationSettings settings = await messaging.getNotificationSettings();
    if (settings.authorizationStatus != AuthorizationStatus.authorized) {
      if (!mounted) return;
      bool? proceed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
          title: Column(
            children: [
              Icon(Icons.radar_rounded, size: 50, color: Colors.orange[900]),
              const SizedBox(height: 15),
              const Text("رادار الطلبات الجديدة", style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w900, fontSize: 18)),
            ],
          ),
          content: const Text(
            "كابتن أكسب، تفعيل الإشعارات يضمن ظهور الطلبات القريبة منك فور صدورها، لتتمكن من قبولها وزيادة أرباحك.",
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'Cairo', fontSize: 14),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("ليس الآن", style: TextStyle(fontFamily: 'Cairo', color: Colors.grey))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange[900], shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
              onPressed: () => Navigator.pop(context, true),
              child: const Text("تفعيل الرادار", style: TextStyle(fontFamily: 'Cairo', color: Colors.white)),
            ),
          ],
        ),
      );
      if (proceed == true) {
        NotificationSettings newSettings = await messaging.requestPermission(alert: true, badge: true, sound: true);
        if (newSettings.authorizationStatus == AuthorizationStatus.authorized) await _syncFreeDriverWithAWS();
      }
    }
  }

  void _loadVehicleConfig() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _vehicleConfig = prefs.getString('user_vehicle_config') ?? 'motorcycleConfig');
  }

  void _fetchInitialStatus() async {
    var doc = await FirebaseFirestore.instance.collection('freeDrivers').doc(uid).get();
    if (doc.exists && mounted) setState(() => isOnline = doc.data()?['isOnline'] ?? false);
  }

  void _listenToActiveOrders() {
    FirebaseFirestore.instance
        .collection('specialRequests')
        .where('driverId', isEqualTo: uid)
        .where('status', whereIn: ['accepted', 'picked_up', 'returning_to_seller', 'returning_to_merchant'])
        .snapshots()
        .listen((snap) {
      if (mounted) setState(() => _activeOrderId = snap.docs.isNotEmpty ? snap.docs.first.id : null);
    });
  }

  Future<void> _launchPrivacyPolicy() async {
    final Uri url = Uri.parse('https://aksab.shop/');
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) return;
  }

  void _onItemTapped(int index) async {
    if (index == 1) {
       if (!isOnline) { _showOnlineSnackBar(); return; }
       setState(() => _hasNewOrders = false); 
    }
    setState(() => _selectedIndex = index);
  }

  void _showOnlineSnackBar() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text("⚠️ برجاء تفعيل وضع الاتصال (أونلاين) لفتح الرادار", textAlign: TextAlign.center, style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w900)),
        backgroundColor: Colors.orange[900],
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, 
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldExit = await _handleWillPop();
        if (shouldExit && mounted) {
          SystemNavigator.pop(); 
        }
      },
      child: Scaffold(
        key: _scaffoldKey,
        drawer: _buildSideDrawer(), 
        backgroundColor: const Color(0xFFF4F7FA),
        body: _selectedIndex == 0 ? _buildModernDashboard() : _buildOtherPages(),
        bottomNavigationBar: _buildBottomNav(),
      ),
    );
  }

  Widget _buildSideDrawer() {
    return Drawer(
      width: 75.w,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.only(topLeft: Radius.circular(35), bottomLeft: Radius.circular(35))),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            decoration: BoxDecoration(gradient: LinearGradient(colors: [Colors.orange[900]!, Colors.orange[700]!]), borderRadius: const BorderRadius.only(bottomRight: Radius.circular(30))),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const CircleAvatar(radius: 35, backgroundColor: Colors.white, child: Icon(Icons.person, size: 45, color: Colors.orange)),
                    const SizedBox(height: 15),
                    const Text("كابتن أكسب", style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w900, fontSize: 18, color: Colors.white)),
                    Text(FirebaseAuth.instance.currentUser?.phoneNumber ?? "", style: const TextStyle(fontFamily: 'Cairo', color: Colors.white70, fontSize: 12)),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
              children: [
                _buildDrawerItem(Icons.account_circle_outlined, "حسابي الشخصي", () => Navigator.push(context, MaterialPageRoute(builder: (context) => const ProfileScreen()))),
                _buildDrawerItem(Icons.privacy_tip_outlined, "سياسة الخصوصية", _launchPrivacyPolicy),
                _buildDrawerItem(Icons.help_outline_rounded, "الدعم الفني", () => Navigator.push(context, MaterialPageRoute(builder: (context) => const SupportScreen()))),
              ],
            ),
          ),
          const Divider(indent: 20, endIndent: 20),
          SafeArea(
            top: false,
            child: ListTile(
              leading: const Icon(Icons.logout_rounded, color: Colors.redAccent),
              title: const Text("تسجيل الخروج", style: TextStyle(fontFamily: 'Cairo', color: Colors.redAccent, fontWeight: FontWeight.w900)),
              onTap: () async {
                await FirebaseAuth.instance.signOut();
                if (mounted) Navigator.pushReplacementNamed(context, '/login');
              },
            ),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  Widget _buildDrawerItem(IconData icon, String title, VoidCallback onTap) {
    return ListTile(leading: Icon(icon, color: Colors.blueGrey[700]), title: Text(title, style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w600, fontSize: 15)), trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey), onTap: onTap);
  }

  Widget _buildModernDashboard() {
    return SafeArea(
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 20, 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(children: [
                    IconButton(icon: const Icon(Icons.menu_rounded, size: 32), onPressed: () => _scaffoldKey.currentState?.openDrawer()),
                    const SizedBox(width: 5),
                    const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text("أهلاً بك 👋", style: TextStyle(fontSize: 14, color: Colors.blueGrey, fontFamily: 'Cairo')),
                      Text("كابتن أكسب", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, fontFamily: 'Cairo'))
                    ])
                  ]),
                  _buildStatusToggle(),
                ],
              ),
            ),
          ),
          if (_activeOrderId != null) SliverToBoxAdapter(child: _buildActiveOrderBanner()),
          _buildLiveStatsGrid(),
        ],
      ),
    );
  }

  Widget _buildLiveStatsGrid() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('specialRequests').where('driverId', isEqualTo: uid).where('status', isEqualTo: 'delivered').snapshots(),
      builder: (context, snapshot) {
        double todayEarnings = 0.0;
        int completedCount = 0;
        if (snapshot.hasData) {
          final startOfToday = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
          for (var doc in snapshot.data!.docs) {
            var d = doc.data() as Map<String, dynamic>;
            Timestamp? time = d['completedAt'] as Timestamp?;
            if (time != null && time.toDate().isAfter(startOfToday)) {
              completedCount++;
              todayEarnings += double.tryParse(d['driverNet']?.toString() ?? '0') ?? 0.0;
            }
          }
        }
        return SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 15, crossAxisSpacing: 15, childAspectRatio: 1.2),
            delegate: SliverChildListDelegate([
              _modernStatCard("أرباح اليوم", "${todayEarnings.toStringAsFixed(0)} ج.م", Icons.payments_rounded, Colors.green),
              _modernStatCard("طلباتك", "$completedCount", Icons.local_shipping_rounded, Colors.blue),
              _modernStatCard("المركبة", _vehicleConfig == 'motorcycleConfig' ? "موتوسيكل" : "سيارة", Icons.moped_rounded, Colors.orange),
              _modernStatCard("التقييم", "4.8", Icons.stars_rounded, Colors.amber),
            ]),
          ),
        );
      },
    );
  }

  Widget _modernStatCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(25), boxShadow: [BoxShadow(color: color.withOpacity(0.08), blurRadius: 15)]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(icon, color: color), const Spacer(), Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, fontFamily: 'Cairo')), Text(title, style: const TextStyle(fontSize: 12, color: Colors.grey, fontFamily: 'Cairo'))]),
    );
  }

  Widget _buildStatusToggle() {
    return GestureDetector(
      onTap: () => _toggleOnlineStatus(!isOnline),
      child: AnimatedContainer(duration: const Duration(milliseconds: 300), padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10), decoration: BoxDecoration(color: isOnline ? Colors.green[600] : Colors.red[600], borderRadius: BorderRadius.circular(15)), child: Row(children: [Icon(isOnline ? Icons.flash_on : Icons.flash_off, color: Colors.white, size: 18), const SizedBox(width: 8), Text(isOnline ? "متصل" : "أوفلاين", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontFamily: 'Cairo'))])),
    );
  }

  Widget _buildActiveOrderBanner() {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('specialRequests').doc(_activeOrderId).snapshots(),
      builder: (context, snap) {
        bool isReturning = false;
        if (snap.hasData && snap.data!.exists) {
          String status = snap.data!['status'] ?? '';
          isReturning = status.contains('returning');
        }

        return GestureDetector(
          onTap: () => setState(() => _selectedIndex = 1),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isReturning 
                  ? [Colors.red[800]!, Colors.red[600]!] 
                  : [Colors.orange[800]!, Colors.orange[600]!]
              ),
              borderRadius: BorderRadius.circular(25)
            ),
            child: Row(
              children: [
                Icon(isReturning ? Icons.assignment_return : Icons.directions_run_rounded, color: Colors.white),
                const SizedBox(width: 15),
                Expanded(
                  child: Text(
                    isReturning ? "لديك مرتجع يجب تسليمه للتاجر.. 🔄" : "لديك رحلة نشطة الآن..",
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontFamily: 'Cairo')
                  )
                ),
                const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 18)
              ]
            )
          ),
        );
      }
    );
  }

  Widget _buildOtherPages() {
    return [
      const SizedBox(), 
      _activeOrderId != null 
          ? ActiveOrderScreen(orderId: _activeOrderId!) 
          : AvailableOrdersScreen(vehicleType: _vehicleConfig), 
      const OrdersHistoryScreen(), 
      const WalletScreen()
    ][_selectedIndex];
  }

  Widget _buildBottomNav() {
    return BottomNavigationBar(
      currentIndex: _selectedIndex,
      onTap: _onItemTapped,
      selectedItemColor: Colors.orange[900],
      type: BottomNavigationBarType.fixed,
      selectedLabelStyle: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w900),
      items: [
        const BottomNavigationBarItem(icon: Icon(Icons.home_filled), label: "الرئيسية"),
        BottomNavigationBarItem(
          icon: Stack(
            children: [
              const Icon(Icons.radar),
              if (_hasNewOrders) 
                Positioned(
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                  ),
                ),
            ],
          ),
          label: "الرادار",
        ),
        const BottomNavigationBarItem(icon: Icon(Icons.assignment_rounded), label: "طلباتي"),
        const BottomNavigationBarItem(icon: Icon(Icons.account_balance_wallet_rounded), label: "المحفظة"),
      ],
    );
  }
}

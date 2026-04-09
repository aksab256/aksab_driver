import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:sizer/sizer.dart'; // ✅ تم إضافتها لحل خطأ الـ Build
import '../widgets/driver_dashboard_widgets.dart';
import '../widgets/driver_side_drawer.dart';
import '../helpers/driver_security_helper.dart';
import '../services/driver_api_service.dart';
import 'available_orders_screen.dart';
import 'active_order_screen.dart';
import 'orders_history_screen.dart';
import 'wallet_screen.dart';

class FreeDriverHomeScreen extends StatefulWidget {
  const FreeDriverHomeScreen({super.key});
  @override
  State<FreeDriverHomeScreen> createState() => _FreeDriverHomeScreenState();
}

class _FreeDriverHomeScreenState extends State<FreeDriverHomeScreen> {
  int _selectedIndex = 0;
  String _currentStatus = 'offline';
  bool _isStatusChanging = false;
  String? _activeOrderId;
  final String uid = FirebaseAuth.instance.currentUser?.uid ?? "";
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _syncStatusInstantly();
    _initListeners();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (uid.isNotEmpty) { DriverSecurityHelper.checkSecurityAndTerms(context, uid); }
    });
  }

  void _syncStatusInstantly() async {
    String localStatus = await DriverApiService.getLocalStatus();
    if (mounted) setState(() => _currentStatus = localStatus);
    try {
      var doc = await FirebaseFirestore.instance.collection('freeDrivers').doc(uid).get();
      if (doc.exists && mounted) {
        String serverStatus = doc.data()?['currentStatus'] ?? 'offline';
        if (serverStatus != _currentStatus) {
          setState(() => _currentStatus = serverStatus);
          await DriverApiService.saveLocalStatus(serverStatus);
        }
      }
    } catch (e) { debugPrint("Initial Sync Error: $e"); }
  }

  void _initListeners() {
    DriverApiService.listenToStatus(uid, (status) {
      if (mounted && status != null && status != _currentStatus) {
        setState(() { _currentStatus = status; _isStatusChanging = false; });
        DriverApiService.saveLocalStatus(status);
      }
    });
    DriverApiService.listenToActiveOrders(uid, (orderId, status) {
      if (mounted) setState(() => _activeOrderId = orderId);
    });
  }

  void _handleStatusChange(bool shouldBeOnline) async {
    if (_currentStatus == 'busy' && !shouldBeOnline) {
      DriverSecurityHelper.showErrorSnackBar(context, "لا يمكن الإغلاق أثناء وجود عهدة نشطة");
      return;
    }
    setState(() => _isStatusChanging = true);
    if (shouldBeOnline) {
      bool permissionGranted = await DriverSecurityHelper.requestLocationPermission(context);
      if (!mounted) return;
      if (permissionGranted) {
        try {
          await DriverApiService.updateStatus(uid, 'online');
          await DriverApiService.saveLocalStatus('online');
          if (mounted) { setState(() { _currentStatus = 'online'; _isStatusChanging = false; }); DriverSecurityHelper.showOnlineHint(context); }
        } catch (e) { if (mounted) setState(() => _isStatusChanging = false); }
      } else { if (mounted) setState(() => _isStatusChanging = false); }
    } else {
      try {
        await DriverApiService.updateStatus(uid, 'offline');
        await DriverApiService.saveLocalStatus('offline');
        if (mounted) { setState(() { _currentStatus = 'offline'; _isStatusChanging = false; }); }
      } catch (e) { if (mounted) setState(() => _isStatusChanging = false); }
    }
  }

  void _onStepTapped(int index) async {
    if (index == 1) {
      showDialog(context: context, barrierDismissible: false, builder: (context) => const Center(child: CircularProgressIndicator(color: Colors.orange)));
      try {
        var doc = await FirebaseFirestore.instance.collection('freeDrivers').doc(uid).get();
        if (!mounted) return;
        Navigator.pop(context);
        String serverStatus = doc.data()?['currentStatus'] ?? 'offline';
        if (serverStatus != 'online') {
          DriverSecurityHelper.showErrorSnackBar(context, "برجاء تفعيل الحالة إلى 'متصل' أولاً");
          setState(() => _currentStatus = serverStatus);
          return;
        }
      } catch (e) { if (mounted) Navigator.pop(context); return; }
    }
    setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      drawer: SafeArea(child: DriverSideDrawer(currentStatus: _currentStatus)), // ✅ حل مشكلة المساحة الآمنة
      backgroundColor: const Color(0xFFF8FAFF),
      body: Stack(
        children: [
          _buildBody(),
          if (_isStatusChanging) Container(color: Colors.black26, child: const Center(child: CircularProgressIndicator(color: Colors.orange))),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: FloatingActionButton(
        onPressed: () => _onStepTapped(1),
        backgroundColor: _selectedIndex == 1 ? Colors.orange[900] : Colors.black87,
        elevation: 8,
        shape: const CircleBorder(),
        child: Icon(Icons.radar, color: Colors.white, size: 24.sp), // ✅ الآن سيعمل بعد إضافة sizer
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildBody() {
    return IndexedStack(
      index: _selectedIndex,
      children: [
        CustomScrollView(slivers: [
          DashboardHeader(scaffoldKey: _scaffoldKey, currentStatus: _currentStatus, onStatusToggle: _handleStatusChange),
          if (_activeOrderId != null) ActiveOrderBanner(onTap: () => setState(() => _selectedIndex = 1)),
          LiveStatsGrid(uid: uid),
        ]),
        _activeOrderId != null ? ActiveOrderScreen(orderId: _activeOrderId!) : const AvailableOrdersScreen(vehicleType: 'motorcycleConfig'),
        const OrdersHistoryScreen(),
        const WalletScreen(),
      ],
    );
  }

  Widget _buildBottomNav() {
    return BottomAppBar(
      shape: const CircularNotchedRectangle(),
      notchMargin: 8.0,
      child: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onStepTapped,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: Colors.orange[900],
        unselectedItemColor: Colors.grey,
        backgroundColor: Colors.transparent,
        elevation: 0,
        selectedLabelStyle: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 11.sp),
        unselectedLabelStyle: TextStyle(fontFamily: 'Cairo', fontSize: 10.sp),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_filled), label: "الرئيسية"),
          BottomNavigationBarItem(icon: Icon(Icons.radar, color: Colors.transparent), label: "الرادار"),
          BottomNavigationBarItem(icon: Icon(Icons.history), label: "رحلاتي"),
          BottomNavigationBarItem(icon: Icon(Icons.wallet), label: "المحفظة"),
        ],
      ),
    );
  }
}


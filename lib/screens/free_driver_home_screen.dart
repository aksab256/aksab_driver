import 'package:flutter/material.dart';              import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';                                                    import 'package:sizer/sizer.dart'; 
import '../widgets/driver_dashboard_widgets.dart';   import '../widgets/driver_side_drawer.dart';
import '../helpers/driver_security_helper.dart';
import '../services/driver_api_service.dart';
import 'available_orders_screen.dart';
import 'active_order_screen.dart';
import 'orders_history_screen.dart';
import 'wallet_screen.dart';                         
import 'support_screen.dart'; // ✅ تم استيراد صفحة الدعم بناءً على مسار الدرور

class FreeDriverHomeScreen extends StatefulWidget {
  const FreeDriverHomeScreen({super.key});           
  @override
  State<FreeDriverHomeScreen> createState() => _FreeDriverHomeScreenState();
}                                                    

class _FreeDriverHomeScreenState extends State<FreeDriverHomeScreen> with SingleTickerProviderStateMixin {
  int _selectedIndex = 0;                              String _currentStatus = 'offline';
  bool _isStatusChanging = false;
  String? _activeOrderId;                              String _userName = "كابتن أكسب"; 
  final String uid = FirebaseAuth.instance.currentUser?.uid ?? "";                                          final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  late AnimationController _pulseController;
                                                       @override
  void initState() {
    super.initState();                               
    _pulseController = AnimationController(
      vsync: this,                                         duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _syncStatusInstantly();                              _initListeners();
    _fetchUserName(); 
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (uid.isNotEmpty) {
        DriverSecurityHelper.checkSecurityAndTerms(context, uid);
      }
    });
  }

  @override
  void dispose() {
    _pulseController.dispose(); 
    super.dispose();
  }

  void _fetchUserName() async {
    try {
      var doc = await FirebaseFirestore.instance.collection('freeDrivers').doc(uid).get();
      if (doc.exists && doc.data()?['fullname'] != null) {
        setState(() {
          _userName = doc.data()?['fullname'];
        });
      }
    } catch (e) {
      debugPrint("Error fetching username: $e");
    }
  }

  void _syncStatusInstantly() async {
    String localStatus = await DriverApiService.getLocalStatus();
    if (mounted) setState(() => _currentStatus = localStatus);
    try {
      var doc = await FirebaseFirestore.instance.collection('freeDrivers').doc(uid).get();
      if (doc.exists && mounted) {                           String serverStatus = doc.data()?['currentStatus'] ?? 'offline';
        if (serverStatus != _currentStatus) {
          setState(() => _currentStatus = serverStatus);
          await DriverApiService.saveLocalStatus(serverStatus);                                                   }
      }
    } catch (e) {                                          debugPrint("Initial Sync Error: $e");
    }                                                  }

  void _initListeners() {
    DriverApiService.listenToStatus(uid, (status) {
      if (mounted && status != null && status != _currentStatus) {
        setState(() {
          _currentStatus = status;                             _isStatusChanging = false;
        });                                                  DriverApiService.saveLocalStatus(status);
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
          if (mounted) {
            setState(() {
              _currentStatus = 'online';
              _isStatusChanging = false;
            });
            DriverSecurityHelper.showOnlineHint(context);
          }
        } catch (e) {
          if (mounted) setState(() => _isStatusChanging = false);
        }
      } else {
        if (mounted) setState(() => _isStatusChanging = false);
      }                                                  } else {
      try {                                                  await DriverApiService.updateStatus(uid, 'offline');
        await DriverApiService.saveLocalStatus('offline');                                                        if (mounted) {
          setState(() {                                          _currentStatus = 'offline';
            _isStatusChanging = false;
          });
        }
      } catch (e) {
        if (mounted) setState(() => _isStatusChanging = false);
      }
    }
  }                                                  

  void _onStepTapped(int index) async {
    if (index == 2) {                                      showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(child: CircularProgressIndicator(color: Colors.orange)));          try {
        var doc = await FirebaseFirestore.instance.collection('freeDrivers').doc(uid).get();
        if (!mounted) return;
        Navigator.pop(context);
        String serverStatus = doc.data()?['currentStatus'] ?? 'offline';
        if (serverStatus != 'online') {
          DriverSecurityHelper.showErrorSnackBar(context, "برجاء تفعيل الحالة إلى 'متصل' أولاً");
          setState(() => _currentStatus = serverStatus);
          return;
        }
      } catch (e) {
        if (mounted) Navigator.pop(context);
        return;
      }
    }
    setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    // ✅ حماية من الخروج المفاجئ بزر الرجوع
    return WillPopScope(
      onWillPop: () async {
        if (_selectedIndex != 0) {
          setState(() => _selectedIndex = 0);
          return false;
        }
        return true; 
      },
      child: Scaffold(
        key: _scaffoldKey,
        drawer: SafeArea(child: DriverSideDrawer(currentStatus: _currentStatus)),
        backgroundColor: const Color(0xFFF8FAFF),
        body: Stack(
          children: [
            _buildBody(),
            if (_isStatusChanging)
              Container(color: Colors.black26, child: const Center(child: CircularProgressIndicator(color: Colors.orange))),
          ],                                                 ),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
        floatingActionButton: _buildAnimatedRadarButton(), 
        bottomNavigationBar: _buildBottomNav(),
      ),
    );
  }

  Widget _buildAnimatedRadarButton() {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {                            
        double pulseValue = (_currentStatus == 'online') ? _pulseController.value : 0.0;

        return Container(                                      decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.orange.withOpacity(0.2 * (1 - pulseValue)),
                spreadRadius: 4 + (12 * pulseValue), 
                blurRadius: 10,
              ),
              BoxShadow(
                color: (_selectedIndex == 2 ? Colors.orange : Colors.grey).withOpacity(0.3),                              spreadRadius: 8,
                blurRadius: 15,
              ),                                                 ],
          ),                                                   child: FloatingActionButton(
            onPressed: () => _onStepTapped(2),
            backgroundColor: _selectedIndex == 2 ? Colors.orange[900] : Colors.black87,
            elevation: 8,
            shape: const CircleBorder(),
            child: Icon(Icons.radar, color: Colors.white, size: 24.sp),
          ),                                                 );
      },
    );
  }                                                  

  Widget _buildBody() {
    return IndexedStack(
      index: _selectedIndex,                               children: [
        // 0: الرئيسية
        CustomScrollView(slivers: [                            DashboardHeader(
            scaffoldKey: _scaffoldKey,                           currentStatus: _currentStatus,
            onStatusToggle: _handleStatusChange,
            userName: _userName,
          ),
          if (_activeOrderId != null) ActiveOrderBanner(onTap: () => setState(() => _selectedIndex = 2)),
          LiveStatsGrid(uid: uid),                           ]),
        // 1: رحلاتي (تم التبديل)
        const OrdersHistoryScreen(),
        // 2: الرادار (الوسط)
        _activeOrderId != null
            ? ActiveOrderScreen(orderId: _activeOrderId!)
            : const AvailableOrdersScreen(vehicleType: 'motorcycleConfig'),
        // 3: المحفظة
        const WalletScreen(),
        // 4: الدعم الفني (تم التعديل لتطابق صفحة الدرور)
        const SupportScreen(),                                                          
      ],
    );
  }

  Widget _buildBottomNav() {                             return BottomAppBar(
      shape: const CircularNotchedRectangle(),
      notchMargin: 8.0,
      child: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onStepTapped,                                type: BottomNavigationBarType.fixed,                 selectedItemColor: Colors.orange[900],
        unselectedItemColor: Colors.grey[700],
        backgroundColor: Colors.transparent,
        elevation: 0,
        selectedLabelStyle: TextStyle(                         fontFamily: 'Cairo',
          fontWeight: FontWeight.bold,
          fontSize: 12.sp // ✅ تكبير الخط
        ),
        unselectedLabelStyle: TextStyle(
          fontFamily: 'Cairo',                                 fontWeight: FontWeight.bold,
          fontSize: 11.sp // ✅ تكبير الخط
        ),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_filled), label: "الرئيسية"),
          BottomNavigationBarItem(icon: Icon(Icons.history), label: "رحلاتي"), // أيقونة رحلاتي
          BottomNavigationBarItem(icon: Icon(Icons.radar, color: Colors.transparent), label: "الرادار"),
          BottomNavigationBarItem(icon: Icon(Icons.wallet), label: "المحفظة"),
          // ✅ تم استخدام الأيقونة من كود الدرور المرفق help_outline_rounded
          BottomNavigationBarItem(icon: Icon(Icons.help_outline_rounded), label: "الدعم"), 
        ],                                                 ),
    );
  }
}


import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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
  bool _isStatusChanging = false; // متغير جديد للتحكم في حالة التحميل
  String? _activeOrderId;
  final String uid = FirebaseAuth.instance.currentUser?.uid ?? "";
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _syncStatusInstantly();
    _initListeners();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (uid.isNotEmpty) {
        // سيتم تعديل هذه الدالة في ملف الـ Helper لتصبح إجبارية
        DriverSecurityHelper.checkSecurityAndTerms(context, uid);
      }
    });
  }

  void _syncStatusInstantly() async {
    String localStatus = await DriverApiService.getLocalStatus();
    if (mounted) {
      setState(() => _currentStatus = localStatus);
    }

    try {
      var doc = await FirebaseFirestore.instance.collection('freeDrivers').doc(uid).get();
      if (doc.exists && mounted) {
        String serverStatus = doc.data()?['currentStatus'] ?? 'offline';
        if (serverStatus != _currentStatus) {
          setState(() => _currentStatus = serverStatus);
          await DriverApiService.saveLocalStatus(serverStatus);
        }
      }
    } catch (e) {
      debugPrint("Initial Sync Error: $e");
    }
  }

  void _initListeners() {
    DriverApiService.listenToStatus(uid, (status) {
      if (mounted && status != null && status != _currentStatus) {
        setState(() {
          _currentStatus = status;
          _isStatusChanging = false; // فك القفل بمجرد وصول التحديث من السيرفر
        });
        DriverApiService.saveLocalStatus(status);
      }
    });

    DriverApiService.listenToActiveOrders(uid, (orderId, status) {
      if (mounted) {
        setState(() => _activeOrderId = orderId);
      }
    });
  }

  // دالة تغيير الحالة المحدثة "القفل الذكي"
  void _handleStatusChange(bool shouldBeOnline) async {
    if (_currentStatus == 'busy' && !shouldBeOnline) {
      DriverSecurityHelper.showErrorSnackBar(context, "لا يمكن الإغلاق أثناء وجود عهدة نشطة");
      return;
    }

    setState(() => _isStatusChanging = true); // تفعيل حالة التحميل

    if (shouldBeOnline) {
      bool permissionGranted = await DriverSecurityHelper.requestLocationPermission(context);
      if (permissionGranted) {
        try {
          // ننتظر السيرفر أولاً قبل تغيير الحالة محلياً
          await DriverApiService.updateStatus(uid, 'online');
          await DriverApiService.saveLocalStatus('online');
          DriverSecurityHelper.showOnlineHint(context);
        } catch (e) {
          setState(() => _isStatusChanging = false);
        }
      } else {
        setState(() => _isStatusChanging = false);
      }
    } else {
      try {
        await DriverApiService.updateStatus(uid, 'offline');
        await DriverApiService.saveLocalStatus('offline');
      } catch (e) {
        setState(() => _isStatusChanging = false);
      }
    }
  }

  // التحكم في التنقل (حماية الرادار) - فحص السيرفر المباشر
  void _onStepTapped(int index) async {
    if (index == 1) {
      // إظهار مؤشر تحميل بسيط للتأكد من السيرفر
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator(color: Colors.orange)),
      );

      try {
        var doc = await FirebaseFirestore.instance.collection('freeDrivers').doc(uid).get();
        Navigator.pop(context); // إغلاق مؤشر التحميل

        String serverStatus = doc.data()?['currentStatus'] ?? 'offline';
        
        if (serverStatus != 'online') {
          DriverSecurityHelper.showErrorSnackBar(context, "حالتك على السيرفر 'غير متصل'. برجاء التفعيل أولاً");
          setState(() => _currentStatus = serverStatus);
          return;
        }
      } catch (e) {
        Navigator.pop(context);
        return;
      }
    }
    
    setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      drawer: DriverSideDrawer(currentStatus: _currentStatus),
      backgroundColor: const Color(0xFFF4F7FA),
      body: Stack(
        children: [
          _buildBody(),
          if (_isStatusChanging)
            Container(
              color: Colors.black12,
              child: const Center(child: CircularProgressIndicator(color: Colors.orange)),
            ),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildBody() {
    return IndexedStack(
      index: _selectedIndex,
      children: [
        CustomScrollView(
          slivers: [
            DashboardHeader(
              scaffoldKey: _scaffoldKey,
              currentStatus: _currentStatus,
              onStatusToggle: _handleStatusChange,
            ),
            if (_activeOrderId != null)
              ActiveOrderBanner(onTap: () => setState(() => _selectedIndex = 1)),
            LiveStatsGrid(uid: uid),
          ],
        ),
        _activeOrderId != null
            ? ActiveOrderScreen(orderId: _activeOrderId!)
            : const AvailableOrdersScreen(vehicleType: 'motorcycleConfig'),
        const OrdersHistoryScreen(),
        const WalletScreen(),
      ],
    );
  }

  Widget _buildBottomNav() {
    return BottomNavigationBar(
      currentIndex: _selectedIndex,
      onTap: _onStepTapped,
      type: BottomNavigationBarType.fixed,
      selectedItemColor: Colors.orange[900],
      unselectedItemColor: Colors.grey,
      selectedLabelStyle: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
      unselectedLabelStyle: const TextStyle(fontFamily: 'Cairo'),
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.home_filled), label: "الرئيسية"),
        BottomNavigationBarItem(icon: Icon(Icons.radar), label: "الرادار"),
        BottomNavigationBarItem(icon: Icon(Icons.history), label: "رحلاتي"),
        BottomNavigationBarItem(icon: Icon(Icons.wallet), label: "المحفظة"),
      ],
    );
  }
}


import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
// استيراد المكونات المساعدة
import '../widgets/driver_dashboard_widgets.dart';
import '../widgets/driver_side_drawer.dart';
import '../helpers/driver_security_helper.dart';
import '../services/driver_api_service.dart';
// الصفحات الفرعية
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
  // القيمة الابتدائية تأتي من الذاكرة المحلية فوراً في initState
  String _currentStatus = 'offline'; 
  String? _activeOrderId;
  final String uid = FirebaseAuth.instance.currentUser?.uid ?? "";
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _syncStatusInstantly(); // المزامنة اللحظية لمنع الـ Offline التلقائي
    _initListeners();
    
    // فحص الأمان والإشعارات عند الفتح
    WidgetsBinding.instance.addPostFrameCallback((_) {
      DriverSecurityHelper.checkSecurityAndTerms(context, uid);
    });
  }

  // دالة المزامنة الذكية: تقرأ من الموبايل أولاً ثم تتأكد من السيرفر
  void _syncStatusInstantly() async {
    // 1. جلب آخر حالة مسجلة محلياً (Zero Latency)
    String localStatus = await DriverApiService.getLocalStatus();
    if (mounted) {
      setState(() => _currentStatus = localStatus);
    }

    // 2. التحقق من الحالة الفعلية في Firestore كنسخة احتياطية
    try {
      var doc = await FirebaseFirestore.instance.collection('freeDrivers').doc(uid).get();
      if (doc.exists && mounted) {
        String serverStatus = doc.data()?['currentStatus'] ?? 'offline';
        // إذا اختلف السيرفر عن الموبايل، نحدث الشاشة
        if (serverStatus != _currentStatus) {
          setState(() => _currentStatus = serverStatus);
        }
      }
    } catch (e) {
      debugPrint("Initial Sync Error: $e");
    }
  }

  void _initListeners() {
    // الاستماع اللحظي لتغييرات الحالة (Online/Offline/Busy)
    DriverApiService.listenToStatus(uid, (status) {
      if (mounted) setState(() => _currentStatus = status);
    });
    // الاستماع للطلبات النشطة (إدارة العهدة)
    DriverApiService.listenToActiveOrders(uid, (orderId, status) {
      if (mounted) setState(() => _activeOrderId = orderId);
    });
  }

  // دالة تغيير الحالة مع رسالة الإفصاح والتحقق اللوجستي
  void _handleStatusChange(bool shouldBeOnline) async {
    if (shouldBeOnline) {
      // 1. طلب إذن الموقع مع رسالة الإفصاح القانونية
      bool permissionGranted = await DriverSecurityHelper.requestLocationPermission(context);
      if (permissionGranted) {
        await DriverApiService.updateStatus(uid, 'online');
        DriverSecurityHelper.showOnlineHint(context); // حركة التأكيد البصرية
      }
    } else {
      // منع الإغلاق إذا كان هناك عهدة (أمانات) قيد التوصيل
      if (_currentStatus == 'busy') {
        DriverSecurityHelper.showErrorSnackBar(context, "لا يمكن الإغلاق أثناء وجود عهدة نشطة");
      } else {
        await DriverApiService.updateStatus(uid, 'offline');
      }
    }
  }

  // التحكم في التنقل (حماية الرادار)
  void _onStepTapped(int index) {
    if (index == 1 && (_currentStatus == 'offline')) {
      DriverSecurityHelper.showErrorSnackBar(context, "يجب أن تكون 'متصل' أولاً لدخول الرادار");
      return;
    }
    setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      drawer: DriverSideDrawer(currentStatus: _currentStatus),
      backgroundColor: const Color(0xFFF4F7FA),
      body: _buildBody(),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildBody() {
    // استخدام IndexedStack للحفاظ على حالة الصفحات أثناء التنقل
    return IndexedStack(
      index: _selectedIndex,
      children: [
        // الصفحة الرئيسية: الداشبورد المهني
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
        // رادار الطلبات أو شاشة العهدة النشطة
        _activeOrderId != null
            ? ActiveOrderScreen(orderId: _activeOrderId!)
            : const AvailableOrdersScreen(vehicleType: 'motorcycleConfig'),
        // تاريخ الرحلات والمحفظة
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


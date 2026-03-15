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
    // 1. المزامنة الفورية من التخزين المحلي والاحتياطي من السيرفر
    _syncStatusInstantly();
    // 2. تفعيل المستمعات للحالة والطلبات
    _initListeners();

    // فحص الأمان والإشعارات عند الفتح
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (uid.isNotEmpty) {
        DriverSecurityHelper.checkSecurityAndTerms(context, uid);
      }
    });
  }

  // دالة المزامنة الذكية: تقرأ من الموبايل أولاً ثم تتأكد من السيرفر
  void _syncStatusInstantly() async {
    // جلب آخر حالة مسجلة محلياً لضمان سرعة الاستجابة (Zero Latency)
    String localStatus = await DriverApiService.getLocalStatus();
    if (mounted) {
      setState(() => _currentStatus = localStatus);
    }

    // التحقق من الحالة الفعلية في Firestore كنسخة احتياطية
    try {
      var doc = await FirebaseFirestore.instance.collection('freeDrivers').doc(uid).get();
      if (doc.exists && mounted) {
        String serverStatus = doc.data()?['currentStatus'] ?? 'offline';
        // تحديث الحالة فقط إذا كان هناك اختلاف حقيقي
        if (serverStatus != _currentStatus) {
          setState(() => _currentStatus = serverStatus);
          // تحديث التخزين المحلي ليتطابق مع السيرفر
          await DriverApiService.saveLocalStatus(serverStatus);
        }
      }
    } catch (e) {
      debugPrint("Initial Sync Error: $e");
    }
  }

  void _initListeners() {
    // الاستماع اللحظي لتغييرات الحالة (Online/Offline/Busy)
    DriverApiService.listenToStatus(uid, (status) {
      if (mounted && status != null && status != _currentStatus) {
        setState(() => _currentStatus = status);
        // حفظ الحالة محلياً عند كل تغيير قادم من السيرفر
        DriverApiService.saveLocalStatus(status);
      }
    });

    // الاستماع للطلبات النشطة (إدارة العهدة)
    DriverApiService.listenToActiveOrders(uid, (orderId, status) {
      if (mounted) {
        setState(() => _activeOrderId = orderId);
      }
    });
  }

  // دالة تغيير الحالة مع التحقق اللوجستي
  void _handleStatusChange(bool shouldBeOnline) async {
    // منع التغيير إذا كان المندوب مشغولاً بعهدة (Busy)
    if (_currentStatus == 'busy' && !shouldBeOnline) {
      DriverSecurityHelper.showErrorSnackBar(context, "لا يمكن الإغلاق أثناء وجود عهدة نشطة (بضاعة في عهدتك)");
      return;
    }

    if (shouldBeOnline) {
      // طلب إذن الموقع مع رسالة الإفصاح القانونية لـ Google Play
      bool permissionGranted = await DriverSecurityHelper.requestLocationPermission(context);
      if (permissionGranted) {
        setState(() => _currentStatus = 'online'); // تحديث بصري فوري
        await DriverApiService.updateStatus(uid, 'online');
        await DriverApiService.saveLocalStatus('online');
        DriverSecurityHelper.showOnlineHint(context);
      }
    } else {
      setState(() => _currentStatus = 'offline'); // تحديث بصري فوري
      await DriverApiService.updateStatus(uid, 'offline');
      await DriverApiService.saveLocalStatus('offline');
    }
  }

  // التحكم في التنقل (حماية الرادار)
  void _onStepTapped(int index) {
    if (index == 1 && (_currentStatus == 'offline')) {
      DriverSecurityHelper.showErrorSnackBar(context, "يجب أن تكون 'متصل' أولاً لدخول الرادار واستقبال الطلبات");
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


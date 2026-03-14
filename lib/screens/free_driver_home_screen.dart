import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// استيراد الملفات الجديدة (التي سننشئها في الخطوات القادمة)
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
  String _currentStatus = 'offline';
  String? _activeOrderId;
  final String uid = FirebaseAuth.instance.currentUser?.uid ?? "";
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _initListeners();
    // فحص الأمان والإشعارات عند الفتح
    WidgetsBinding.instance.addPostFrameCallback((_) {
      DriverSecurityHelper.checkSecurityAndTerms(context, uid);
    });
  }

  void _initListeners() {
    // الاستماع للحالة (Online/Offline/Busy)
    DriverApiService.listenToStatus(uid, (status) {
      if (mounted) setState(() => _currentStatus = status);
    });
    // الاستماع للطلبات النشطة (العهدة)
    DriverApiService.listenToActiveOrders(uid, (orderId, status) {
      if (mounted) setState(() => _activeOrderId = orderId);
    });
  }

  // دالة تغيير الحالة مع رسالة الإفصاح والحركة الشيك
  void _handleStatusChange(bool shouldBeOnline) async {
    if (shouldBeOnline) {
      // 1. طلب إذن الموقع مع رسالة الإفصاح
      bool permissionGranted = await DriverSecurityHelper.requestLocationPermission(context);
      if (permissionGranted) {
        await DriverApiService.updateStatus(uid, 'online');
        DriverSecurityHelper.showOnlineHint(context); // الحركة الشيك
      }
    } else {
      if (_currentStatus == 'busy') {
        DriverSecurityHelper.showErrorSnackBar(context, "لا يمكن الإغلاق أثناء وجود عهدة نشطة");
      } else {
        await DriverApiService.updateStatus(uid, 'offline');
      }
    }
  }

  // التحكم في التنقل (منع الدخول للرادار وهو أوفلاين)
  void _onStepTapped(int index) {
    if (index == 1 && _currentStatus == 'offline') {
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
    // استخدام IndexedStack للحفاظ على حالة الصفحات
    return IndexedStack(
      index: _selectedIndex,
      children: [
        // الصفحة الرئيسية (الداشبورد) - نمرر لها المكونات
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
        // باقي الصفحات
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
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.home_filled), label: "الرئيسية"),
        BottomNavigationBarItem(icon: Icon(Icons.radar), label: "الرادار"),
        BottomNavigationBarItem(icon: Icon(Icons.history), label: "رحلاتي"),
        BottomNavigationBarItem(icon: Icon(Icons.wallet), label: "المحفظة"),
      ],
    );
  }
}


// lib/screens/available_orders_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sizer/sizer.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'active_order_screen.dart'; 

class AvailableOrdersScreen extends StatefulWidget {
  final String vehicleType; 
  const AvailableOrdersScreen({super.key, required this.vehicleType});

  @override
  State<AvailableOrdersScreen> createState() => _AvailableOrdersScreenState();
}

class _AvailableOrdersScreenState extends State<AvailableOrdersScreen> {
  Position? _myCurrentLocation;
  bool _isGettingLocation = true;
  final String? _uid = FirebaseAuth.instance.currentUser?.uid;
  Timer? _uiTimer;

  @override
  void initState() {
    super.initState();
    _showLocationDisclosure();
    // المؤقت المسؤول عن تحديث العداد التنازلي كل ثانية في الواجهة
    _uiTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _uiTimer?.cancel();
    super.dispose();
  }

  // دالة حساب الوقت المتبقي (15 دقيقة من تاريخ الإنشاء)
  String _getTimerText(Timestamp? createdAt) {
    if (createdAt == null) return "00:00";
    DateTime expiryTime = createdAt.toDate().add(const Duration(minutes: 15));
    Duration remaining = expiryTime.difference(DateTime.now());
    
    if (remaining.isNegative) return "منتهي";
    
    String minutes = remaining.inMinutes.toString().padLeft(2, '0');
    String seconds = (remaining.inSeconds % 60).toString().padLeft(2, '0');
    return "$minutes:$seconds";
  }

  Future<void> _showLocationDisclosure() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      if (!mounted) return;
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: [
                Icon(Icons.location_on, color: Colors.blue[900], size: 22.sp),
                SizedBox(width: 10),
                Text("استخدام بيانات الموقع", style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 16.sp)),
              ],
            ),
            content: Text(
              "يقوم تطبيق (أكسب مندوب) بجمع بيانات الموقع لتمكين تتبع الرحلات وتحديث حالة الطلبات حتى عندما يكون التطبيق مغلقاً.\n\n"
              "يساعد هذا في ضمان وصول الشحنة بدقة وحماية حقوقك المالية.",
              style: TextStyle(fontFamily: 'Cairo', fontSize: 13.sp),
            ),
            actions: [
              TextButton(
                onPressed: () { Navigator.pop(context); setState(() => _isGettingLocation = false); },
                child: Text("رفض", style: TextStyle(color: Colors.grey, fontFamily: 'Cairo', fontSize: 12.sp)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue[900], shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                onPressed: () { Navigator.pop(context); _initSequence(); },
                child: Text("موافق ومتابعة", style: TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 12.sp)),
              ),
            ],
          ),
        ),
      );
    } else {
      _initSequence();
    }
  }

  Future<void> _initSequence() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) setState(() => _isGettingLocation = false);
      return;
    }
    await Geolocator.requestPermission();
    try {
      Position pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      if (mounted) setState(() { _myCurrentLocation = pos; _isGettingLocation = false; });
    } catch (e) {
      if (mounted) setState(() => _isGettingLocation = false);
    }
  }

  Future<void> _acceptOrder(String orderId) async {
    try {
      showDialog(
        context: context, 
        barrierDismissible: false, 
        builder: (c) => const Center(child: CircularProgressIndicator(color: Colors.orange))
      );
      
      DocumentSnapshot driverProfile = await FirebaseFirestore.instance.collection('freeDrivers').doc(_uid).get();
      String driverName = driverProfile.exists ? (driverProfile.get('fullname') ?? "مندوب") : "مندوب";

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        DocumentReference orderRef = FirebaseFirestore.instance.collection('specialRequests').doc(orderId);
        DocumentSnapshot orderSnap = await transaction.get(orderRef);
        
        // التعديل: القبول فقط في حالة 'pending'
        if (orderSnap.exists && orderSnap.get('status') == 'pending') {
          transaction.update(orderRef, {
            'status': 'accepted',
            'driverId': _uid,
            'driverName': driverName,
            'acceptedAt': FieldValue.serverTimestamp(),
            'moneyLocked': false,
            'serverNote': "تأكيد العهدة: جاري معالجة الطلب ماليًا...",
          });
        } else {
          throw Exception("عذراً، الطلب لم يعد متاحاً (تم إلغاؤه أو قبوله)");
        }
      });

      if (mounted) {
        Navigator.pop(context);
        Navigator.pushAndRemoveUntil(
          context, 
          MaterialPageRoute(builder: (context) => ActiveOrderScreen(orderId: orderId)), 
          (route) => false
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString().replaceAll("Exception: ", ""), style: const TextStyle(fontFamily: 'Cairo')), 
          backgroundColor: Colors.red
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isGettingLocation) return const Scaffold(body: Center(child: CircularProgressIndicator(color: Colors.orange)));
    String cleanType = widget.vehicleType.replaceAll('Config', '');

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Text("رادار الطلبات القريبة", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16.sp, fontFamily: 'Cairo', color: Colors.black)),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0.5,
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('freeDrivers').doc(_uid).snapshots(),
        builder: (context, driverSnap) {
          double walletBalance = 0.0;
          double creditLimit = 0.0;
          
          if (driverSnap.hasData && driverSnap.data!.exists) {
            var dData = driverSnap.data!.data() as Map<String, dynamic>;
            walletBalance = double.tryParse(dData['walletBalance']?.toString() ?? '0') ?? 0.0;
            creditLimit = double.tryParse(dData['creditLimit']?.toString() ?? '0') ?? 0.0;
          }

          double totalFinancialPower = walletBalance + creditLimit;

          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('specialRequests')
                .where('status', isEqualTo: 'pending') // ✅ تم حذف حالة 'no_drivers_available'
                .where('vehicleType', isEqualTo: cleanType)
                .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: Colors.orange));
              
              final nearbyOrders = snapshot.data!.docs.where((doc) {
                var data = doc.data() as Map<String, dynamic>;
                GeoPoint? pickup = data['pickupLocation'];
                if (pickup == null || _myCurrentLocation == null) return false;
                double dist = Geolocator.distanceBetween(_myCurrentLocation!.latitude, _myCurrentLocation!.longitude, pickup.latitude, pickup.longitude);
                return dist <= 15000;
              }).toList();

              if (nearbyOrders.isEmpty) {
                return Center(child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.radar, size: 60.sp, color: Colors.grey[400]),
                    SizedBox(height: 2.h),
                    Text("لا توجد طلبات متاحة حالياً", style: TextStyle(fontFamily: 'Cairo', fontSize: 14.sp, color: Colors.grey)),
                  ],
                ));
              }

              return ListView.builder(
                padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 2.h),
                itemCount: nearbyOrders.length,
                itemBuilder: (context, index) => _buildOrderCard(nearbyOrders[index], walletBalance, totalFinancialPower),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildOrderCard(DocumentSnapshot doc, double walletBalance, double totalPower) {
    var data = doc.data() as Map<String, dynamic>;
    
    double totalPrice = double.tryParse(data['totalPrice']?.toString() ?? '0') ?? 0.0;
    double driverNet = double.tryParse(data['driverNet']?.toString() ?? '0') ?? 0.0;
    double commission = double.tryParse(data['commissionAmount']?.toString() ?? '0') ?? 0.0;
    double orderFinalAmount = double.tryParse(data['orderFinalAmount']?.toString() ?? '0') ?? 0.0;

    double insuranceRequired = (orderFinalAmount > 0) ? (orderFinalAmount - driverNet) : 0.0;
    if (insuranceRequired < 0) insuranceRequired = 0;

    bool hasCashForInsurance = walletBalance >= insuranceRequired;
    bool hasTotalForCommission = totalPower >= commission;
    bool canAccept = hasCashForInsurance && hasTotalForCommission;

    bool isMerchant = data['requestSource'] == 'retailer';
    String timeLeft = _getTimerText(data['createdAt'] as Timestamp?);

    const Color goldStart = Color(0xFFFFD700);
    const Color goldEnd = Color(0xFFFFA000);
    const Color merchantContent = Color(0xFF5D4037); 

    return Card(
      elevation: 8,
      margin: EdgeInsets.only(bottom: 3.h),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
      child: Column(
        children: [
          Container(
            padding: EdgeInsets.symmetric(horizontal: 5.w, vertical: 2.h),
            decoration: BoxDecoration(
              gradient: isMerchant 
                ? const LinearGradient(colors: [goldStart, goldEnd], begin: Alignment.topLeft, end: Alignment.bottomRight)
                : null,
              color: isMerchant ? null : (canAccept ? const Color(0xFF2D9E68) : const Color(0xFFD32F2F)),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(25)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(isMerchant ? FontAwesomeIcons.crown : Icons.delivery_dining, 
                         color: isMerchant ? merchantContent : Colors.white, size: 22.sp),
                    SizedBox(width: 3.w),
                    Text("صافي ربحك: $driverNet ج.م", 
                         style: TextStyle(color: isMerchant ? merchantContent : Colors.white, 
                         fontWeight: FontWeight.w900, fontSize: 15.sp, fontFamily: 'Cairo')),
                  ],
                ),
                // ✅ العداد التنازلي الموحد لجميع أنواع الكروت
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.timer_outlined, size: 14.sp, color: isMerchant ? merchantContent : Colors.white),
                      SizedBox(width: 5),
                      Text(
                        timeLeft,
                        style: TextStyle(
                          color: isMerchant ? merchantContent : Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13.sp,
                          fontFamily: 'Cairo',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          Padding(
            padding: EdgeInsets.all(5.w),
            child: Column(
              children: [
                Row(
                  children: [
                    _buildFinanceInfo("تأمين عهدة", "${insuranceRequired.toStringAsFixed(2)} ن", Icons.security_sharp),
                    _buildFinanceInfo("قيمة التحصيل", "${orderFinalAmount.toStringAsFixed(2)} ج.م", Icons.payments_outlined),
                  ],
                ),
                Divider(height: 4.h, thickness: 1.5, color: Colors.grey[200]),
                
                _buildRouteRow(Icons.radio_button_checked, "استلام من: ${data['userName'] ?? 'الموقع'}", data['pickupAddress'] ?? "لم يتم تحديد العنوان", Colors.orange[800]!),
                SizedBox(height: 1.5.h),
                _buildRouteRow(Icons.location_on, "تسليم إلى: ${data['customerName'] ?? 'العميل'}", data['dropoffAddress'] ?? "لم يتم تحديد العنوان", Colors.red[900]!),
                
                Divider(height: 4.h, thickness: 1.5, color: Colors.grey[200]),
                
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("إجمالي قيمة الطلب:", style: TextStyle(fontSize: 13.sp, color: Colors.grey[800], fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                    Text("$totalPrice ج.م", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18.sp, color: Colors.black)),
                  ],
                ),
                SizedBox(height: 3.h),
                
                InkWell(
                  onTap: canAccept ? () => _acceptOrder(doc.id) : null,
                  child: Container(
                    width: double.infinity,
                    height: 8.h,
                    decoration: BoxDecoration(
                      gradient: (canAccept && isMerchant)
                        ? const LinearGradient(colors: [goldStart, goldEnd])
                        : null,
                      color: canAccept 
                        ? (isMerchant ? null : Colors.green[800]) 
                        : Colors.grey[400],
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: canAccept ? [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 5))] : [],
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      canAccept 
                        ? "تأكيد العهدة وقبول الطلب" 
                        : "الرصيد لا يغطي الطلب",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: canAccept ? (isMerchant ? merchantContent : Colors.white) : Colors.grey[700], 
                        fontWeight: FontWeight.w900, 
                        fontSize: 13.5.sp, 
                        fontFamily: 'Cairo'
                      ),
                    ),
                  ),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildFinanceInfo(String title, String value, IconData icon) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 20.sp, color: Colors.blueGrey[700]),
          SizedBox(height: 0.5.h),
          Text(title, style: TextStyle(fontFamily: 'Cairo', fontSize: 11.sp, color: Colors.grey[600], fontWeight: FontWeight.bold)),
          Text(value, style: TextStyle(fontFamily: 'Cairo', fontSize: 14.sp, fontWeight: FontWeight.w900, color: const Color(0xFF0D47A1))),
        ],
      ),
    );
  }

  Widget _buildRouteRow(IconData icon, String label, String addr, Color color) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 22.sp),
        SizedBox(width: 4.w),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 11.sp, color: Colors.grey[700], fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
              Text(addr, style: TextStyle(fontSize: 13.sp, color: Colors.black, fontFamily: 'Cairo', fontWeight: FontWeight.w500), maxLines: 2, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ],
    );
  }
}

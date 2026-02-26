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
    _initSequence();
    _uiTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _uiTimer?.cancel();
    super.dispose();
  }

  Future<void> _initSequence() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) setState(() => _isGettingLocation = false);
      return;
    }
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    try {
      Position pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      if (mounted) setState(() { _myCurrentLocation = pos; _isGettingLocation = false; });
    } catch (e) {
      if (mounted) setState(() => _isGettingLocation = false);
    }
  }

  Future<void> _acceptOrder(String orderId) async {
    try {
      showDialog(context: context, barrierDismissible: false, builder: (c) => const Center(child: CircularProgressIndicator(color: Colors.orange)));
      
      // هنا التطبيق يغير الحالة فقط، والسيرفر سيتولى عملية حجز (totalPrice - driverNet) تلقائياً
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        DocumentReference orderRef = FirebaseFirestore.instance.collection('specialRequests').doc(orderId);
        DocumentSnapshot orderSnap = await transaction.get(orderRef);
        
        if (orderSnap.exists && orderSnap.get('status') == 'pending') {
          transaction.update(orderRef, {
            'status': 'accepted',
            'driverId': _uid,
            'acceptedAt': FieldValue.serverTimestamp(),
          });
        } else {
          throw Exception("عذراً، الطلب تم قبوله من كابتن آخر");
        }
      });

      if (mounted) {
        Navigator.pop(context);
        Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => ActiveOrderScreen(orderId: orderId)), (route) => false);
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString(), style: const TextStyle(fontFamily: 'Cairo')), backgroundColor: Colors.red));
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
        title: Text("رادار الطلبات القريبة", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.sp, fontFamily: 'Cairo', color: Colors.black)),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0.5,
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('freeDrivers').doc(_uid).snapshots(),
        builder: (context, driverSnap) {
          double cashBalance = 0;
          double creditLimit = 0;
          if (driverSnap.hasData && driverSnap.data!.exists) {
            var dData = driverSnap.data!.data() as Map<String, dynamic>;
            cashBalance = double.tryParse(dData['walletBalance']?.toString() ?? '0') ?? 0.0;
            creditLimit = double.tryParse(dData['creditLimit']?.toString() ?? '0') ?? 0.0;
          }

          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('specialRequests')
                .where('status', isEqualTo: 'pending')
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
                return Center(child: Text("لا توجد طلبات متاحة حالياً", style: TextStyle(fontFamily: 'Cairo', fontSize: 12.sp)));
              }

              return ListView.builder(
                padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 2.h),
                itemCount: nearbyOrders.length,
                itemBuilder: (context, index) => _buildOrderCard(nearbyOrders[index], cashBalance, creditLimit),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildOrderCard(DocumentSnapshot doc, double cashBalance, double creditLimit) {
    var data = doc.data() as Map<String, dynamic>;
    bool isMerchant = data['requestSource'] == 'retailer';
    
    // الأرقام من الداتابيز
    double totalPrice = double.tryParse(data['totalPrice']?.toString() ?? '0') ?? 0.0; // الـ 250
    double driverNet = double.tryParse(data['driverNet']?.toString() ?? '0') ?? 0.0;    // الـ 20
    double commission = double.tryParse(data['commissionAmount']?.toString() ?? '0') ?? 0.0; // الـ 3

    // الحسبة اللوجستية المطلوبة: المبلغ الذي سيتم حظره من المندوب لضمان العهدة
    // المندوب يحصل 250 كاش، والسيرفر يحجز (250 - 20) = 230
    double insuranceRequired = totalPrice - driverNet; 

    // فحص القدرة المالية: هل رصيد الكاش يغطي مبلغ التأمين (الـ 230)؟
    bool canAccept = cashBalance >= insuranceRequired;

    // الألوان الذهبية
    Color goldPrimary = const Color(0xFFFFD700); 
    Color themeColor = isMerchant ? goldPrimary : (canAccept ? const Color(0xFF2D9E68) : const Color(0xFFD32F2F));
    Color contentColor = isMerchant ? const Color(0xFF5D4037) : Colors.white;

    return Card(
      elevation: 6,
      margin: EdgeInsets.only(bottom: 2.5.h),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Column(
        children: [
          Container(
            padding: EdgeInsets.symmetric(horizontal: 5.w, vertical: 1.5.h),
            decoration: BoxDecoration(
              color: themeColor,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(isMerchant ? FontAwesomeIcons.crown : Icons.delivery_dining, color: contentColor, size: 20),
                    SizedBox(width: 2.w),
                    Text(
                      "ربحك الصافي: $driverNet ج.م",
                      style: TextStyle(color: contentColor, fontWeight: FontWeight.w900, fontSize: 14.sp, fontFamily: 'Cairo'),
                    ),
                  ],
                ),
                if (!canAccept) const Icon(Icons.warning_amber_rounded, color: Colors.white),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.all(4.w),
            child: Column(
              children: [
                Row(
                  children: [
                    // عرض "تأمين العهدة" وهو المبلغ الذي سيُحجز فعلياً
                    _buildFinanceInfo("تأمين العهدة", "$insuranceRequired ن", Icons.lock_outline),
                    // عرض عمولة المنصة (للعلم فقط)
                    _buildFinanceInfo("رسوم الخدمة", "$commission ن", Icons.receipt_long_outlined),
                  ],
                ),
                Divider(height: 4.h, thickness: 1),
                _buildRouteRow(Icons.store_mall_directory_rounded, "استلام من:", data['pickupAddress'] ?? "الموقع", isMerchant ? Colors.orange[900]! : Colors.orange),
                _buildRouteRow(Icons.location_on_rounded, "تسليم إلى:", data['dropoffAddress'] ?? "العميل", Colors.red),
                const Divider(height: 30),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("إجمالي فاتورة العميل:", style: TextStyle(fontSize: 12.sp, color: Colors.grey[800], fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                    Text("$totalPrice ج.م", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16.sp, color: Colors.black)),
                  ],
                ),
                SizedBox(height: 2.h),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: canAccept ? themeColor : Colors.grey[400],
                    minimumSize: Size(100.w, 7.5.h),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                    elevation: 3,
                  ),
                  onPressed: canAccept ? () => _acceptOrder(doc.id) : null,
                  child: Text(
                    canAccept 
                      ? (isMerchant ? "قبول وتأمين عهدة" : "قبول الطلب") 
                      : "رصيدك لا يغطي التأمين ($insuranceRequired ن)",
                    style: TextStyle(color: isMerchant ? contentColor : Colors.white, fontWeight: FontWeight.w900, fontSize: 13.sp, fontFamily: 'Cairo'),
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
          Icon(icon, size: 18, color: Colors.blueGrey),
          Text(title, style: TextStyle(fontFamily: 'Cairo', fontSize: 10.sp, color: Colors.grey[600])),
          Text(value, style: TextStyle(fontFamily: 'Cairo', fontSize: 12.sp, fontWeight: FontWeight.bold, color: const Color(0xFF0D47A1))),
        ],
      ),
    );
  }

  Widget _buildRouteRow(IconData icon, String label, String addr, Color color) {
    return Padding(
      padding: EdgeInsets.only(bottom: 1.5.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          SizedBox(width: 3.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 10.sp, color: Colors.grey[700], fontFamily: 'Cairo')),
                Text(addr, style: TextStyle(fontSize: 11.5.sp, fontWeight: FontWeight.bold, color: Colors.black87, fontFamily: 'Cairo'), maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

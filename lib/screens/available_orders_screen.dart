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
    _uiTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _uiTimer?.cancel();
    super.dispose();
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
            title: const Row(
              children: [
                Icon(Icons.location_on, color: Colors.blue),
                SizedBox(width: 10),
                Text("استخدام بيانات الموقع", style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
              ],
            ),
            content: const Text(
              "يقوم تطبيق (أكسب مندوب) بجمع بيانات الموقع لتمكين تتبع الرحلات وتحديث حالة الطلبات حتى عندما يكون التطبيق مغلقاً.\n\n"
              "يساعد هذا في ضمان وصول الشحنة بدقة وحماية حقوقك المالية (نقاط التأمين).",
              style: TextStyle(fontFamily: 'Cairo', fontSize: 14),
            ),
            actions: [
              TextButton(
                onPressed: () { Navigator.pop(context); setState(() => _isGettingLocation = false); },
                child: const Text("رفض", style: TextStyle(color: Colors.grey, fontFamily: 'Cairo')),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue[900], shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                onPressed: () { Navigator.pop(context); _initSequence(); },
                child: const Text("موافق ومتابعة", style: TextStyle(color: Colors.white, fontFamily: 'Cairo')),
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
      showDialog(context: context, barrierDismissible: false, builder: (c) => const Center(child: CircularProgressIndicator(color: Colors.orange)));
      
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        DocumentReference orderRef = FirebaseFirestore.instance.collection('specialRequests').doc(orderId);
        DocumentSnapshot orderSnap = await transaction.get(orderRef);
        
        if (orderSnap.exists && (orderSnap.get('status') == 'pending' || orderSnap.get('status') == 'no_drivers_available')) {
          transaction.update(orderRef, {
            'status': 'accepted',
            'driverId': _uid,
            'acceptedAt': FieldValue.serverTimestamp(),
          });
        } else {
          throw Exception("عذراً، الطلب لم يعد متاحاً");
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
          if (driverSnap.hasData && driverSnap.data!.exists) {
            var dData = driverSnap.data!.data() as Map<String, dynamic>;
            cashBalance = double.tryParse(dData['walletBalance']?.toString() ?? '0') ?? 0.0;
          }

          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('specialRequests')
                .where('status', whereIn: ['pending', 'no_drivers_available'])
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
                itemBuilder: (context, index) => _buildOrderCard(nearbyOrders[index], cashBalance),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildOrderCard(DocumentSnapshot doc, double cashBalance) {
    var data = doc.data() as Map<String, dynamic>;
    
    // ✅ القراءة من الحقول الصحيحة حسب بيانات Firebase المرسلة
    double totalPrice = double.tryParse(data['totalPrice']?.toString() ?? '0') ?? 0.0;
    double driverNet = double.tryParse(data['driverNet']?.toString() ?? '0') ?? 0.0;
    double commission = double.tryParse(data['commissionAmount']?.toString() ?? '0') ?? 0.0;
    double orderFinalAmount = double.tryParse(data['orderFinalAmount']?.toString() ?? '0') ?? 0.0;

    // ⚖️ حسبة تأمين العهدة (المبلغ المراد خصمه من المحفظة مؤقتاً)
    // العهدة = المبلغ الذي سيحصله المندوب - ربحه الصافي من التوصيلة
    double insuranceRequired = (orderFinalAmount > 0) ? (orderFinalAmount - driverNet) : totalPrice;
    if (insuranceRequired < 0) insuranceRequired = 0;

    bool canAccept = cashBalance >= insuranceRequired;
    bool isMerchant = data['requestSource'] == 'retailer';

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
            decoration: BoxDecoration(color: themeColor, borderRadius: const BorderRadius.vertical(top: Radius.circular(20))),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(isMerchant ? FontAwesomeIcons.crown : Icons.delivery_dining, color: contentColor, size: 20),
                    SizedBox(width: 2.w),
                    Text("صافي ربحك: $driverNet ج.م", style: TextStyle(color: contentColor, fontWeight: FontWeight.w900, fontSize: 13.sp, fontFamily: 'Cairo')),
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
                    _buildFinanceInfo("تأمين عهدة", "${insuranceRequired.toStringAsFixed(2)} ن", Icons.lock_outline),
                    _buildFinanceInfo("قيمة التحصيل", "${orderFinalAmount.toStringAsFixed(2)} ج.م", Icons.payments_outlined),
                  ],
                ),
                Divider(height: 4.h, thickness: 1),
                _buildRouteRow(Icons.store_mall_directory_rounded, "استلام من: ${data['userName'] ?? 'الموقع'}", data['pickupAddress'] ?? "", Colors.orange),
                _buildRouteRow(Icons.location_on_rounded, "تسليم إلى: ${data['customerName'] ?? 'العميل'}", data['dropoffAddress'] ?? "", Colors.red),
                const Divider(height: 30),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("إجمالي تكلفة الشحن:", style: TextStyle(fontSize: 11.sp, color: Colors.grey[800], fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                    Text("$totalPrice ج.م", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15.sp, color: Colors.black)),
                  ],
                ),
                SizedBox(height: 2.h),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: canAccept ? (isMerchant ? goldPrimary : Colors.green[800]) : Colors.grey[400],
                    minimumSize: Size(100.w, 7.5.h),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  ),
                  onPressed: canAccept ? () => _acceptOrder(doc.id) : null,
                  child: Text(
                    canAccept ? "تأكيد العهدة وقبول الطلب" : "رصيدك لا يغطي التأمين ($insuranceRequired ن)",
                    style: TextStyle(color: isMerchant ? contentColor : Colors.white, fontWeight: FontWeight.w900, fontSize: 12.sp, fontFamily: 'Cairo'),
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
          Icon(icon, size: 16, color: Colors.blueGrey),
          Text(title, style: TextStyle(fontFamily: 'Cairo', fontSize: 9.sp, color: Colors.grey[600])),
          Text(value, style: TextStyle(fontFamily: 'Cairo', fontSize: 11.sp, fontWeight: FontWeight.bold, color: const Color(0xFF0D47A1))),
        ],
      ),
    );
  }

  Widget _buildRouteRow(IconData icon, String label, String addr, Color color) {
    return Padding(
      padding: EdgeInsets.only(bottom: 1.2.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          SizedBox(width: 3.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 9.sp, color: Colors.grey[700], fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                Text(addr, style: TextStyle(fontSize: 10.5.sp, color: Colors.black87, fontFamily: 'Cairo'), maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

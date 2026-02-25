// lib/screens/available_orders_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sizer/sizer.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart'; // تأكد من وجودها للأيقونات
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

  double _calculateFullTripDistance(GeoPoint pickup, GeoPoint dropoff) {
    if (_myCurrentLocation == null) return 0.0;
    double toPickup = Geolocator.distanceBetween(
      _myCurrentLocation!.latitude, _myCurrentLocation!.longitude,
      pickup.latitude, pickup.longitude,
    );
    double toCustomer = Geolocator.distanceBetween(
      pickup.latitude, pickup.longitude,
      dropoff.latitude, dropoff.longitude,
    );
    return (toPickup + toCustomer) / 1000;
  }

  // ... (نفس دوال _showLocationDisclosure و _initSequence بدون تغيير)

  Future<void> _acceptOrder(String orderId, double commission, String customerId) async {
    // (نفس منطق قبول الطلب والترانزاكشن)
    try {
      showDialog(context: context, barrierDismissible: false, builder: (c) => const Center(child: CircularProgressIndicator(color: Colors.orange)));
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: Colors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isGettingLocation) return const Scaffold(body: Center(child: CircularProgressIndicator(color: Colors.orange)));
    if (_myCurrentLocation == null) { /* ... نفس واجهة الموقع المعطل ... */ return const SizedBox(); }

    String cleanType = widget.vehicleType.replaceAll('Config', '');

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Text("رادار الطلبات ($cleanType)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.sp, fontFamily: 'Cairo', color: Colors.black)),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0.5,
      ),
      body: SafeArea(
        child: StreamBuilder<DocumentSnapshot>(
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
                  if (pickup == null) return false;
                  double dist = Geolocator.distanceBetween(_myCurrentLocation!.latitude, _myCurrentLocation!.longitude, pickup.latitude, pickup.longitude);
                  return dist <= 15000;
                }).toList();

                return ListView.builder(
                  padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 2.h),
                  itemCount: nearbyOrders.length,
                  itemBuilder: (context, index) => _buildOrderCard(nearbyOrders[index], cashBalance, creditLimit),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildOrderCard(DocumentSnapshot doc, double cashBalance, double creditLimit) {
    var data = doc.data() as Map<String, dynamic>;
    
    // البيانات المالية
    double orderValue = double.tryParse(data['orderValue']?.toString() ?? '0') ?? 0.0; // قيمة البضاعة/الطلب
    double deliveryFee = double.tryParse(data['totalPrice']?.toString() ?? '0') ?? 0.0; // ما سيتم تحصيله (بضاعة + توصيل)
    double driverNet = double.tryParse(data['driverNet']?.toString() ?? '0') ?? 0.0; // ربح المندوب
    double commission = double.tryParse(data['commissionAmount']?.toString() ?? '0') ?? 0.0; // عمولة المنصة
    
    bool isMerchant = data['isMerchant'] == true; // علامة التاجر

    // 🎯 منطق قبول العهدة الجديد:
    // 1. العمولة لازم تتغطى من (كاش + كريديت)
    // 2. قيمة الطلب (orderValue) لازم تتغطى من (الكاش) فقط
    bool canCoverCommission = (cashBalance + creditLimit) >= commission;
    bool canCoverOrderValue = cashBalance >= orderValue;
    bool canAccept = canCoverCommission && canCoverOrderValue;

    // توقيت الطلب
    Timestamp? createdAt = data['createdAt'] as Timestamp?;
    String timeLeft = "15:00";
    if (createdAt != null) {
      DateTime expiryTime = createdAt.toDate().add(const Duration(minutes: 15));
      Duration diff = expiryTime.difference(DateTime.now());
      if (diff.isNegative) return const SizedBox.shrink();
      timeLeft = "${diff.inMinutes}:${(diff.inSeconds % 60).toString().padLeft(2, '0')}";
    }

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      margin: EdgeInsets.only(bottom: 2.5.h),
      child: Column(
        children: [
          // شريط الحالة العلوي
          Container(
            padding: EdgeInsets.symmetric(horizontal: 5.w, vertical: 1.5.h),
            decoration: BoxDecoration(
              // ذهبي للتجار، أخضر للطلبات العادية، أحمر لو الرصيد غير كافٍ
              color: !canAccept 
                  ? Colors.red[600] 
                  : (isMerchant ? const Color(0xFFFFD700) : const Color(0xFF2D9E68)),
              borderRadius: const BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    if (isMerchant) ...[
                      const Icon(FontAwesomeIcons.crown, color: Color(0xFF8B4513), size: 18),
                      SizedBox(width: 2.w),
                    ],
                    Text(
                      "ربحك الصافي: $driverNet ج.م",
                      style: TextStyle(
                        color: isMerchant ? const Color(0xFF8B4513) : Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12.sp, // تكبير الخط
                        fontFamily: 'Cairo'
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(8)),
                  child: Text("⏳ $timeLeft", style: TextStyle(color: isMerchant ? const Color(0xFF8B4513) : Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
          
          Padding(
            padding: EdgeInsets.all(4.w),
            child: Column(
              children: [
                // تفاصيل العهدة والطلب
                Row(
                  children: [
                    _buildFinanceInfo("قيمة العهدة", "$orderValue ج.م", Icons.inventory_2_outlined),
                    const VerticalDivider(),
                    _buildFinanceInfo("تأمين العمولة", "$commission ج.م", Icons.account_balance_wallet_outlined),
                  ],
                ),
                const Divider(height: 3.h),
                
                _buildRouteRow(Icons.store_mall_directory_rounded, "نقطة استلام العهدة:", data['pickupAddress'] ?? "المتجر", isMerchant ? Colors.orange[800]! : Colors.orange),
                _buildRouteRow(Icons.location_on_rounded, "تسليم الأمانات إلى:", data['dropoffAddress'] ?? "العميل", Colors.red),
                
                const Divider(height: 30),
                
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text("إجمالي التحصيل من العميل:", style: TextStyle(fontSize: 11.sp, color: Colors.grey.shade700, fontFamily: 'Cairo')),
                  Text("$deliveryFee ج.م", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14.sp, color: Colors.black)),
                ]),
                
                SizedBox(height: 2.h),
                
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: canAccept ? (isMerchant ? const Color(0xFFFFD700) : const Color(0xFF2D9E68)) : Colors.grey.shade400,
                    minimumSize: Size(100.w, 7.h),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  ),
                  onPressed: canAccept ? () => _acceptOrder(doc.id, commission, data['userId'] ?? "") : null,
                  child: Text(
                    canAccept ? "تأكيد استلام العهدة والتحرك" : "رصيد الكاش لا يغطي العهدة",
                    style: TextStyle(
                      color: isMerchant ? const Color(0xFF8B4513) : Colors.white,
                      fontWeight: FontWeight.bold, 
                      fontSize: 12.sp, 
                      fontFamily: 'Cairo'
                    )
                  ),
                )
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
          Icon(icon, size: 16, color: Colors.grey[600]),
          Text(title, style: TextStyle(fontFamily: 'Cairo', fontSize: 9.sp, color: Colors.grey[600])),
          Text(value, style: TextStyle(fontFamily: 'Cairo', fontSize: 11.sp, fontWeight: FontWeight.bold, color: Colors.blue[900])),
        ],
      ),
    );
  }

  Widget _buildRouteRow(IconData icon, String label, String addr, Color color) {
    return Padding(
      padding: EdgeInsets.only(bottom: 1.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          SizedBox(width: 3.w),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 9.sp, color: Colors.grey[600], fontFamily: 'Cairo')),
              Text(addr, style: TextStyle(fontSize: 10.5.sp, fontWeight: FontWeight.bold, color: Colors.black87, fontFamily: 'Cairo'), maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          )),
        ],
      ),
    );
  }
}

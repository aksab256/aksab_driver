import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class OrdersHeatmapScreen extends StatefulWidget {
  final String vehicleType; // هنمرر نوع المركبة من الشاشة اللي فاتت
  const OrdersHeatmapScreen({super.key, required this.vehicleType});

  @override
  State<OrdersHeatmapScreen> createState() => _OrdersHeatmapScreenState();
}

class _OrdersHeatmapScreenState extends State<OrdersHeatmapScreen> {
  GoogleMapController? _mapController;
  
  // تنظيف نوع المركبة ليتطابق مع ما يكتبه الـ EC2
  String get _targetDoc => "heatmap_${widget.vehicleType.replaceAll('Config', '')}";

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("رادار كثافة الطلبات", style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0.5,
      ),
      body: StreamBuilder<DocumentSnapshot>(
        // المستند اللي الـ EC2 بيحدثه لحظياً
        stream: FirebaseFirestore.instance.collection('app_settings').doc(_targetDoc).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Colors.orange));
          }

          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(child: Text("لا توجد بيانات كثافة حالياً", style: TextStyle(fontFamily: 'Cairo')));
          }

          var data = snapshot.data!.data() as Map<String, dynamic>;
          List points = data['points'] ?? [];

          // تحويل الإحداثيات إلى Markers (دبابيس) على الخريطة
          Set<Marker> markers = points.map((p) {
            return Marker(
              markerId: MarkerId("${p['lat']}_${p['lng']}"),
              position: LatLng(p['lat'], p['lng']),
              icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
              infoWindow: const InfoWindow(title: "منطقة طلبات نشطة"),
            );
          }).toSet();

          return GoogleMap(
            initialCameraPosition: const CameraPosition(
              target: LatLng(31.2001, 29.9187), // الإسكندرية كبداية
              zoom: 11,
            ),
            onMapCreated: (controller) => _mapController = controller,
            markers: markers,
            myLocationEnabled: true, // يوري المندوب هو فين بالنسبة للزحمة
            zoomControlsEnabled: false,
            mapType: MapType.normal,
          );
        },
      ),
    );
  }
}


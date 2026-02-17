import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:sizer/sizer.dart';

class ManagerGeoDistScreen extends StatefulWidget {
  const ManagerGeoDistScreen({super.key});

  @override
  State<ManagerGeoDistScreen> createState() => _ManagerGeoDistScreenState();
}

class _ManagerGeoDistScreenState extends State<ManagerGeoDistScreen> {
  final MapController _mapController = MapController();
  String? selectedSupervisorId;
  List<String> selectedAreas = [];
  List<Map<String, dynamic>> mySupervisors = [];
  Map<String, dynamic>? geoJsonData;
  List<String> allAvailableAreaNames = [];
  bool isLoading = true;

  final String mapboxToken = "pk.eyJ1IjoiYW1yc2hpcGwiLCJhIjoiY21lajRweGdjMDB0eDJsczdiemdzdXV6biJ9.E--si9vOB93NGcAq7uVgGw";

  @override
  void initState() {
    super.initState();
    // تأخير التنفيذ لضمان جاهزية الإطار
    WidgetsBinding.instance.addPostFrameCallback((_) => _initializeData());
  }

  Future<void> _initializeData() async {
    try {
      debugPrint("🚀 بدأت عملية تهيئة البيانات...");
      await _loadGeoJson();
      await _loadSupervisors();
    } catch (e) {
      debugPrint("❌ خطأ عام في التهيئة: $e");
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _loadGeoJson() async {
    try {
      final String response = await rootBundle.loadString(
          'assets/OSMB-bc319d822a17aa9ad1089fc05e7d4e752460f877.geojson');
      
      final data = json.decode(response);
      
      if (data != null && data['features'] != null) {
        geoJsonData = data;
        List<String> names = [];
        for (var f in data['features']) {
          String? name = f['properties']['name']?.toString();
          if (name != null && name.isNotEmpty) names.add(name);
        }
        names.sort();
        
        setState(() {
          allAvailableAreaNames = names;
        });
        debugPrint("✅ تم تحميل ${names.length} منطقة من ملف GeoJSON");
      }
    } catch (e) {
      debugPrint("❌ فشل تحميل ملف GeoJSON: $e (تأكد من وجود الملف في assets وتعريفه في pubspec)");
    }
  }

  Future<void> _loadSupervisors() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        debugPrint("⚠️ لا يوجد مدير مسجل دخول");
        return;
      }

      debugPrint("🔍 جاري البحث عن مشرفين للمدير: ${user.uid}");

      final supervisorsSnap = await FirebaseFirestore.instance
          .collection('managers')
          .where('role', isEqualTo: 'delivery_supervisor')
          .where('managerId', isEqualTo: user.uid)
          .get();

      debugPrint("📊 عدد المستندات المستلمة من فايربيز: ${supervisorsSnap.docs.length}");

      if (mounted) {
        setState(() {
          mySupervisors = supervisorsSnap.docs.map((doc) {
            var data = doc.data();
            return {
              'id': doc.id,
              'fullname': data['fullname'] ?? 'مشرف بدون اسم',
              'areas': List<String>.from(data['geographicArea'] ?? [])
            };
          }).toList();
        });
      }
    } catch (e) {
      debugPrint("❌ فشل تحميل المشرفين: $e");
    }
  }

  // دالة الحفظ مع رسالة تنبيه احترافية
  Future<void> _saveAreas() async {
    if (selectedSupervisorId == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('managers')
          .doc(selectedSupervisorId)
          .update({'geographicArea': selectedAreas});

      _showTopToast("تم حفظ التوزيع بنجاح ✨");
    } catch (e) {
      _showTopToast("حدث خطأ أثناء الحفظ ❌");
    }
  }

  void _showTopToast(String message) {
    OverlayEntry entry = OverlayEntry(
      builder: (context) => Positioned(
        top: 10.h,
        left: 20.w,
        right: 20.w,
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF2F3542),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(entry);
    Future.delayed(const Duration(seconds: 2), () => entry.remove());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("توزيع مناطق المشرفين"),
        backgroundColor: const Color(0xFF2F3542),
        actions: [
          if (selectedSupervisorId != null)
            IconButton(icon: const Icon(Icons.save, color: Colors.greenAccent), onPressed: _saveAreas)
        ],
      ),
      body: isLoading 
        ? const Center(child: CircularProgressIndicator()) 
        : Column(
            children: [
              _buildSelector(),
              _buildMap(),
              _buildAreaList(),
            ],
          ),
    );
  }

  Widget _buildSelector() {
    return Padding(
      padding: EdgeInsets.all(12.sp),
      child: DropdownButtonFormField<String>(
        decoration: InputDecoration(
          labelText: "المشرف المسؤول",
          prefixIcon: const Icon(Icons.person),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
        value: selectedSupervisorId,
        hint: const Text("اختر مشرفاً من القائمة"),
        items: mySupervisors.map((sup) => DropdownMenuItem(
          value: sup['id'] as String,
          child: Text(sup['fullname']),
        )).toList(),
        onChanged: (val) {
          setState(() {
            selectedSupervisorId = val;
            selectedAreas = List<String>.from(mySupervisors.firstWhere((s) => s['id'] == val)['areas']);
          });
        },
      ),
    );
  }

  Widget _buildMap() {
    return Expanded(
      flex: 2,
      child: FlutterMap(
        mapController: _mapController,
        options: const MapOptions(initialCenter: LatLng(31.2001, 29.9187), initialZoom: 11),
        children: [
          TileLayer(
            urlTemplate: "https://api.mapbox.com/styles/v1/mapbox/streets-v11/tiles/{z}/{x}/{y}?access_token=$mapboxToken",
            additionalOptions: {'accessToken': mapboxToken},
          ),
          if (selectedAreas.isNotEmpty && geoJsonData != null)
            PolygonLayer(polygons: _buildPolygons()),
        ],
      ),
    );
  }

  Widget _buildAreaList() {
    return Expanded(
      child: allAvailableAreaNames.isEmpty 
        ? const Center(child: Text("لم يتم العثور على مناطق في الملف"))
        : ListView.builder(
            itemCount: allAvailableAreaNames.length,
            itemBuilder: (context, index) {
              final area = allAvailableAreaNames[index];
              return CheckboxListTile(
                title: Text(area),
                value: selectedAreas.contains(area),
                onChanged: (val) {
                  setState(() {
                    val == true ? selectedAreas.add(area) : selectedAreas.remove(area);
                  });
                },
              );
            },
          ),
    );
  }

  List<Polygon> _buildPolygons() {
    List<Polygon> polygons = [];
    for (var areaName in selectedAreas) {
      try {
        var feature = geoJsonData!['features'].firstWhere((f) => f['properties']['name'] == areaName);
        var geometry = feature['geometry'];
        
        if (geometry['type'] == 'Polygon') {
          _processCoords(polygons, geometry['coordinates']);
        } else if (geometry['type'] == 'MultiPolygon') {
          for (var poly in geometry['coordinates']) {
            _processCoords(polygons, poly);
          }
        }
      } catch (e) { continue; }
    }
    return polygons;
  }

  void _processCoords(List<Polygon> polygons, List coords) {
    // دعم مستويات مختلفة من التعشيش
    var targetList = coords[0] is List && coords[0][0] is List ? coords[0] : coords;
    
    List<LatLng> points = (targetList as List).map<LatLng>((c) {
      return LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble());
    }).toList();

    polygons.add(Polygon(
      points: points,
      color: Colors.teal.withOpacity(0.3),
      borderStrokeWidth: 2,
      borderColor: Colors.teal,
    ));
  }
}


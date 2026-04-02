// المسار: lib/screens/manager_geo_dist_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
// ✅ استبدال المكتبات القديمة بمكتبة جوجل مابس
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:sizer/sizer.dart';

class ManagerGeoDistScreen extends StatefulWidget {
  const ManagerGeoDistScreen({super.key});

  @override
  State<ManagerGeoDistScreen> createState() => _ManagerGeoDistScreenState();
}

class _ManagerGeoDistScreenState extends State<ManagerGeoDistScreen> {
  // ✅ تغيير الـ Controller ليتوافق مع جوجل مابس
  GoogleMapController? _mapController;
  String? selectedSupervisorId;
  List<String> selectedAreas = [];
  List<Map<String, dynamic>> mySupervisors = [];
  Map<String, dynamic>? geoJsonData;
  List<String> allAvailableAreaNames = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
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
      debugPrint("❌ فشل تحميل ملف GeoJSON: $e");
    }
  }

  Future<void> _loadSupervisors() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final supervisorsSnap = await FirebaseFirestore.instance
          .collection('managers')
          .where('role', isEqualTo: 'delivery_supervisor')
          .where('managerId', isEqualTo: user.uid)
          .get();

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
        title: const Text("توزيع مناطق المشرفين", style: TextStyle(color: Colors.white)),
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
        items: mySupervisors
            .map((sup) => DropdownMenuItem(
                  value: sup['id'] as String,
                  child: Text(sup['fullname']),
                ))
            .toList(),
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
      child: GoogleMap(
        initialCameraPosition: const CameraPosition(
          target: LatLng(31.2001, 29.9187),
          zoom: 11,
        ),
        onMapCreated: (controller) => _mapController = controller,
        // ✅ تحويل الـ Polygons لنظام جوجل مابس
        polygons: _buildPolygons(),
        myLocationButtonEnabled: false,
        zoomControlsEnabled: true,
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

  // ✅ تعديل دالة بناء المضلعات لتتوافق مع Set<Polygon> الخاص بجوجل
  Set<Polygon> _buildPolygons() {
    Set<Polygon> polygons = {};
    if (geoJsonData == null) return polygons;

    for (var areaName in selectedAreas) {
      try {
        var feature = geoJsonData!['features'].firstWhere((f) => f['properties']['name'] == areaName);
        var geometry = feature['geometry'];

        if (geometry['type'] == 'Polygon') {
          _processCoords(polygons, geometry['coordinates'], areaName);
        } else if (geometry['type'] == 'MultiPolygon') {
          int i = 0;
          for (var poly in geometry['coordinates']) {
            _processCoords(polygons, poly, "${areaName}_$i");
            i++;
          }
        }
      } catch (e) {
        continue;
      }
    }
    return polygons;
  }

  void _processCoords(Set<Polygon> polygons, List coords, String areaId) {
    var targetList = coords[0] is List && coords[0][0] is List ? coords[0] : coords;

    List<LatLng> points = (targetList as List).map<LatLng>((c) {
      return LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble());
    }).toList();

    polygons.add(Polygon(
      polygonId: PolygonId(areaId),
      points: points,
      fillColor: Colors.teal.withOpacity(0.3),
      strokeWidth: 2,
      strokeColor: Colors.teal,
    ));
  }
}


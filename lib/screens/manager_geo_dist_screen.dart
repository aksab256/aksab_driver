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
    _initializeData();
  }

  Future<void> _initializeData() async {
    try {
      await _loadGeoJson();
      await _loadSupervisors();
    } catch (e) {
      debugPrint("Initialization Error: $e");
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _loadGeoJson() async {
    final String response = await rootBundle.loadString(
        'assets/OSMB-bc319d822a17aa9ad1089fc05e7d4e752460f877.geojson');
    geoJsonData = json.decode(response);

    if (geoJsonData != null) {
      allAvailableAreaNames = geoJsonData!['features']
          .map<String>((f) => f['properties']['name']?.toString() ?? "")
          .where((name) => name.isNotEmpty)
          .toList();
      allAvailableAreaNames.sort();
    }
  }

  Future<void> _loadSupervisors() async {
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
  }

  Future<void> _saveAreas() async {
    if (selectedSupervisorId == null) return;

    await FirebaseFirestore.instance
        .collection('managers')
        .doc(selectedSupervisorId)
        .update({'geographicArea': selectedAreas});

    _showStyledBanner("تم تحديث مناطق المشرف بنجاح ✅");
  }

  void _showStyledBanner(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF2F3542),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("توزيع مناطق المشرفين"),
        backgroundColor: const Color(0xFF2F3542),
        actions: [
          IconButton(
            icon: const Icon(Icons.save, color: Colors.greenAccent),
            onPressed: selectedSupervisorId != null ? _saveAreas : null,
          )
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildSupervisorSelector(),
                _buildMapSection(),
                _buildAreaListSection(),
              ],
            ),
    );
  }

  Widget _buildSupervisorSelector() {
    return Container(
      padding: EdgeInsets.all(12.sp),
      decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 5)]),
      child: DropdownButtonFormField<String>(
        decoration: InputDecoration(
          labelText: "المشرف المسؤول",
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          prefixIcon: const Icon(Icons.person_pin_circle),
        ),
        value: selectedSupervisorId,
        items: mySupervisors.map((sup) {
          return DropdownMenuItem(value: sup['id'] as String, child: Text(sup['fullname']));
        }).toList(),
        onChanged: (val) {
          setState(() {
            selectedSupervisorId = val;
            selectedAreas = List<String>.from(mySupervisors.firstWhere((s) => s['id'] == val)['areas']);
          });
        },
      ),
    );
  }

  Widget _buildMapSection() {
    return Expanded(
      flex: 2,
      child: FlutterMap(
        mapController: _mapController,
        options: const MapOptions(
          initialCenter: LatLng(31.2001, 29.9187), // سنتر الإسكندرية
          initialZoom: 11,
        ),
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

  Widget _buildAreaListSection() {
    return Expanded(
      child: Container(
        color: Colors.grey[50],
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              width: double.infinity,
              color: Colors.blueGrey[800],
              child: const Text("المناطق المتاحة في ملف الـ GeoJSON", textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
            Expanded(
              child: ListView.separated(
                itemCount: allAvailableAreaNames.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final area = allAvailableAreaNames[index];
                  final isSelected = selectedAreas.contains(area);
                  return CheckboxListTile(
                    title: Text(area, style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                    value: isSelected,
                    activeColor: Colors.teal,
                    onChanged: (bool? value) {
                      setState(() {
                        if (value == true) {
                          selectedAreas.add(area);
                        } else {
                          selectedAreas.remove(area);
                        }
                      });
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Polygon> _buildPolygons() {
    List<Polygon> polygons = [];
    if (geoJsonData == null) return polygons;

    for (var areaName in selectedAreas) {
      var feature = geoJsonData!['features'].firstWhere(
          (f) => f['properties']['name'] == areaName,
          orElse: () => null);

      if (feature != null) {
        var geometry = feature['geometry'];
        var type = geometry['type'];

        if (type == 'Polygon') {
          _addPolygonFromCoords(polygons, geometry['coordinates']);
        } else if (type == 'MultiPolygon') {
          for (var polyCoords in geometry['coordinates']) {
            _addPolygonFromCoords(polygons, polyCoords);
          }
        }
      }
    }
    return polygons;
  }

  void _addPolygonFromCoords(List<Polygon> polygons, List coords) {
    // نأخذ أول قائمة إحداثيات (الحدود الخارجية)
    List<LatLng> points = (coords[0] as List)
        .map<LatLng>((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
        .toList();

    polygons.add(Polygon(
      points: points,
      color: Colors.teal.withOpacity(0.3),
      borderStrokeWidth: 2,
      borderColor: Colors.teal,
      isFilled: true,
    ));
  }
}


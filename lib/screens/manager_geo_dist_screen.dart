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

  // مفتاح Mapbox الخاص بك
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

  // الدالة المصححة لجلب المشرفين بناءً على managerId (UID)
  Future<void> _loadSupervisors() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // البحث عن كل من يحمل managerId يطابق UID المدير الحالي (مثل mmm)
    final supervisorsSnap = await FirebaseFirestore.instance
        .collection('managers')
        .where('role', isEqualTo: 'delivery_supervisor')
        .where('managerId', isEqualTo: user.uid) // التعديل الجوهري هنا
        .get();

    if (supervisorsSnap.docs.isNotEmpty) {
      mySupervisors = supervisorsSnap.docs.map((doc) {
        var data = doc.data();
        return {
          'id': doc.id, // 6KntgoeXb8YyRtGwrwLxqHCuFyc2 (ahmed)
          'fullname': data['fullname'] ?? 'مشرف بدون اسم',
          'areas': List<String>.from(data['geographicArea'] ?? [])
        };
      }).toList();
    }
  }

  Future<void> _saveAreas() async {
    if (selectedSupervisorId == null) return;

    await FirebaseFirestore.instance
        .collection('managers')
        .doc(selectedSupervisorId)
        .update({'geographicArea': selectedAreas});

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("تم تحديث مناطق المشرف بنجاح ✅")),
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
            icon: const Icon(Icons.save),
            onPressed: selectedSupervisorId != null ? _saveAreas : null,
          )
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: EdgeInsets.all(10.sp),
                  child: DropdownButtonFormField<String>(
                    decoration: const InputDecoration(labelText: "اختر المشرف"),
                    value: selectedSupervisorId,
                    items: mySupervisors.map((sup) {
                      return DropdownMenuItem(
                        value: sup['id'] as String,
                        child: Text(sup['fullname']),
                      );
                    }).toList(),
                    onChanged: (val) {
                      setState(() {
                        selectedSupervisorId = val;
                        selectedAreas = List<String>.from(
                            mySupervisors.firstWhere((s) => s['id'] == val)['areas']);
                      });
                    },
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: FlutterMap(
                    mapController: _mapController,
                    options: const MapOptions(
                      initialCenter: LatLng(30.0444, 31.2357),
                      initialZoom: 10,
                    ),
                    children: [
                      // استخدام Mapbox TileLayer بدلاً من OSM
                      TileLayer(
                        urlTemplate: "https://api.mapbox.com/styles/v1/mapbox/streets-v11/tiles/{z}/{x}/{y}?access_token=$mapboxToken",
                        additionalOptions: {
                          'accessToken': mapboxToken,
                        },
                      ),
                      if (selectedAreas.isNotEmpty && geoJsonData != null)
                        PolygonLayer(
                          polygons: _buildPolygons(),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: Container(
                    color: Colors.white,
                    child: Column(
                      children: [
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8.0),
                          child: Text("اختر المناطق الإدارية:",
                              style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                        Expanded(
                          child: ListView(
                            children: allAvailableAreaNames.map((area) {
                              return CheckboxListTile(
                                title: Text(area),
                                value: selectedAreas.contains(area),
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
                            }).toList(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  List<Polygon> _buildPolygons() {
    List<Polygon> polygons = [];
    for (var areaName in selectedAreas) {
      var feature = geoJsonData!['features'].firstWhere(
          (f) => f['properties']['name'] == areaName,
          orElse: () => null);

      if (feature != null) {
        var geometry = feature['geometry'];
        List coords = geometry['coordinates'][0];
        List<LatLng> points = coords
            .map<LatLng>((c) =>
                LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
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
    return polygons;
  }
}


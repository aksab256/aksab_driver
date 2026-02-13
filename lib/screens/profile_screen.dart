// lib/screens/profile_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:sizer/sizer.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final String uid = FirebaseAuth.instance.currentUser?.uid ?? "";

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FA),
      appBar: AppBar(
        title: const Text("حسابي", style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black,
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('freeDrivers').doc(uid).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Colors.orange));
          }
          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(child: Text("لم يتم العثور على بيانات", style: TextStyle(fontFamily: 'Cairo')));
          }

          var userData = snapshot.data!.data() as Map<String, dynamic>;
          
          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Center(
                  child: Column(
                    children: [
                      CircleAvatar(
                        radius: 50,
                        backgroundColor: Colors.orange[100],
                        child: const Icon(Icons.person, size: 60, color: Colors.orange),
                      ),
                      const SizedBox(height: 15),
                      Text(
                        userData['name'] ?? "كابتن أكسب",
                        style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
                      ),
                      Text(
                        userData['email'] ?? "",
                        style: const TextStyle(color: Colors.grey, fontFamily: 'Cairo'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 30),
                _buildInfoCard(
                  title: "بيانات المركبة",
                  icon: Icons.delivery_dining_rounded,
                  content: userData['vehicleType'] == 'motorcycle' ? "موتوسيكل" : "سيارة",
                  color: Colors.blue,
                ),
                const SizedBox(height: 15),
                _buildInfoCard(
                  title: "رقم الهاتف",
                  icon: Icons.phone_android_rounded,
                  content: userData['phone'] ?? "غير مسجل",
                  color: Colors.orange,
                ),
                const SizedBox(height: 15),
                _buildInfoCard(
                  title: "المنطقة النشطة",
                  icon: Icons.map_rounded,
                  content: userData['city'] ?? "الإسكندرية",
                  color: Colors.teal,
                ),
                const SizedBox(height: 30),
                ElevatedButton.icon(
                  onPressed: () {
                    // ✅ تم إصلاح الخطأ هنا (وضع الـ TextStyle داخل الـ Text)
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          "ميزة تعديل البيانات ستتوفر قريباً", 
                          style: TextStyle(fontFamily: 'Cairo'),
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.edit_note_rounded),
                  label: const Text("تعديل البيانات", style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    minimumSize: Size(100.w, 6.h),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: BorderSide(color: Colors.grey[300]!)),
                    elevation: 0,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildInfoCard({required String title, required IconData icon, required String content, required Color color}) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 5))],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 15),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(color: Colors.grey, fontSize: 12, fontFamily: 'Cairo')),
              Text(content, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, fontFamily: 'Cairo')),
            ],
          )
        ],
      ),
    );
  }
}

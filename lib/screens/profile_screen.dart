import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:sizer/sizer.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  // دالة مساعدة لتحويل كود المركبة إلى نص عربي
  String _getVehicleName(String? config) {
    switch (config) {
      case 'motorcycleConfig':
        return "موتوسيكل";
      case 'pickupConfig':
        return "سيارة بيك أب (ربع نقل)";
      case 'jumboConfig':
        return "سيارة جامبو";
      default:
        return "مركبة نقل";
    }
  }

  // دالة مساعدة لاختيار الأيقونة المناسبة
  IconData _getVehicleIcon(String? config) {
    if (config == 'motorcycleConfig') return Icons.motorcycle_rounded;
    return Icons.local_shipping_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final String uid = FirebaseAuth.instance.currentUser?.uid ?? "";

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FA),
      appBar: AppBar(
        title: const Text("حسابي الشخصي", 
          style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 18)),
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

          // جلب البيانات بناءً على أسماء الحقول في الداتابيز الخاصة بك
          var userData = snapshot.data!.data() as Map<String, dynamic>;
          String vehicleConfig = userData['vehicleConfig'] ?? "";
          
          return SingleChildScrollView(
            padding: EdgeInsets.symmetric(horizontal: 5.w, vertical: 2.h),
            child: Column(
              children: [
                // رأس الصفحة (الصورة والاسم)
                Center(
                  child: Column(
                    children: [
                      CircleAvatar(
                        radius: 45.sp,
                        backgroundColor: Colors.orange[50],
                        child: Icon(Icons.person, size: 50.sp, color: Colors.orange[800]),
                      ),
                      SizedBox(height: 2.h),
                      Text(
                        userData['fullname'] ?? "كابتن أكسب", // استخدام fullname
                        style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
                      ),
                      Text(
                        userData['email'] ?? "",
                        style: TextStyle(color: Colors.grey, fontSize: 11.sp, fontFamily: 'Cairo'),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 4.h),

                // كروت البيانات
                _buildInfoCard(
                  title: "نوع المركبة المسجلة",
                  icon: _getVehicleIcon(vehicleConfig),
                  content: _getVehicleName(vehicleConfig),
                  color: Colors.blue,
                ),
                SizedBox(height: 2.h),

                _buildInfoCard(
                  title: "رقم الهاتف",
                  icon: Icons.phone_android_rounded,
                  content: userData['phone'] ?? "غير مسجل",
                  color: Colors.green,
                ),
                SizedBox(height: 2.h),

                _buildInfoCard(
                  title: "رصيد المحفظة",
                  icon: Icons.account_balance_wallet_rounded,
                  content: "${userData['walletBalance'] ?? 0} ج.م",
                  color: (userData['walletBalance'] ?? 0) < 0 ? Colors.red : Colors.orange,
                ),
                SizedBox(height: 2.h),

                _buildInfoCard(
                  title: "العنوان / المنطقة",
                  icon: Icons.location_on_rounded,
                  content: userData['address'] ?? "غير محدد", // استخدام address
                  color: Colors.teal,
                ),

                SizedBox(height: 4.h),

                // زر تعديل البيانات
                ElevatedButton.icon(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("برجاء التواصل مع الإدارة لتعديل البيانات الأساسية", 
                          style: TextStyle(fontFamily: 'Cairo')),
                        backgroundColor: Color(0xFF2C3E50),
                      ),
                    );
                  },
                  icon: const Icon(Icons.support_agent_rounded),
                  label: const Text("طلب تعديل بيانات", 
                    style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF2C3E50),
                    minimumSize: Size(100.w, 7.h),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15), 
                      side: BorderSide(color: Colors.grey[300]!)
                    ),
                    elevation: 0,
                  ),
                ),
                SizedBox(height: 2.h),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildInfoCard({required String title, required IconData icon, required String content, required Color color}) {
    return Container(
      padding: EdgeInsets.all(12.sp),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(8.sp),
            decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: color, size: 20.sp),
          ),
          SizedBox(width: 4.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(color: Colors.grey, fontSize: 10.sp, fontFamily: 'Cairo')),
                Text(content, 
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.sp, fontFamily: 'Cairo', color: Colors.black87)),
              ],
            ),
          )
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:sizer/sizer.dart';
import 'package:url_launcher/url_launcher.dart'; // مهم لفتح الروابط

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  String _getVehicleName(String? config) {
    switch (config) {
      case 'motorcycleConfig': return "موتوسيكل";
      case 'pickupConfig': return "سيارة بيك أب";
      case 'jumboConfig': return "سيارة جامبو";
      default: return "مركبة نقل";
    }
  }

  @override
  Widget build(BuildContext context) {
    final String uid = FirebaseAuth.instance.currentUser?.uid ?? "";

    return Drawer( // تحويلها لـ Drawer بدل Scaffold
      width: 85.w,
      child: Column(
        children: [
          // رأس القائمة (Header)
          StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance.collection('freeDrivers').doc(uid).snapshots(),
            builder: (context, snapshot) {
              var name = "كابتن أكسب";
              var phone = "جارٍ التحميل...";
              if (snapshot.hasData && snapshot.data!.exists) {
                var data = snapshot.data!.data() as Map<String, dynamic>;
                name = data['fullname'] ?? name;
                phone = data['phone'] ?? "";
              }
              return Container(
                padding: EdgeInsets.only(top: 6.h, bottom: 3.h, left: 5.w, right: 5.w),
                color: const Color(0xFF2C3E50),
                width: double.infinity,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 35.sp,
                      backgroundColor: Colors.white24,
                      child: Icon(Icons.person, size: 40.sp, color: Colors.white),
                    ),
                    SizedBox(height: 2.h),
                    Text(name, style: TextStyle(color: Colors.white, fontSize: 14.sp, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
                    Text(phone, style: TextStyle(color: Colors.white70, fontSize: 10.sp, fontFamily: 'Cairo')),
                  ],
                ),
              );
            },
          ),

          // القائمة (Menu Items)
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                _buildDrawerItem(
                  icon: Icons.privacy_tip_outlined,
                  title: "سياسة الخصوصية",
                  onTap: () {
                    // هنا نضع رابط سياسة الخصوصية الخاص بك
                    _launchURL("https://aksabeg.com/privacy-policy");
                  },
                ),
                _buildDrawerItem(
                  icon: Icons.support_agent_rounded,
                  title: "الدعم الفني",
                  onTap: () {
                    // فتح واتساب الدعم مثلاً
                    _launchURL("https://wa.me/201234567890");
                  },
                ),
                _buildDrawerItem(
                  icon: Icons.info_outline_rounded,
                  title: "عن التطبيق",
                  onTap: () {},
                ),
                const Divider(),
                _buildDrawerItem(
                  icon: Icons.logout_rounded,
                  title: "تسجيل الخروج",
                  color: Colors.red,
                  onTap: () async {
                    await FirebaseAuth.instance.signOut();
                    if (context.mounted) Navigator.of(context).pushReplacementNamed('/login');
                  },
                ),
              ],
            ),
          ),
          
          // الإصدار في الأسفل
          Padding(
            padding: EdgeInsets.all(15.sp),
            child: Text("إصدار التجربة 1.0.2", style: TextStyle(color: Colors.grey, fontSize: 9.sp)),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawerItem({required IconData icon, required String title, required VoidCallback onTap, Color? color}) {
    return ListTile(
      leading: Icon(icon, color: color ?? Colors.black87),
      title: Text(title, style: TextStyle(fontFamily: 'Cairo', fontSize: 11.sp, fontWeight: FontWeight.w500, color: color)),
      onTap: onTap,
    );
  }

  Future<void> _launchURL(String url) async {
    final Uri uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      debugPrint("Could not launch $url");
    }
  }
}

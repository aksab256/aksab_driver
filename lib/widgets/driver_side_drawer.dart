import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:sizer/sizer.dart';
import '../screens/profile_screen.dart';
import '../screens/support_screen.dart';
import '../helpers/driver_security_helper.dart';
import 'package:url_launcher/url_launcher.dart';

class DriverSideDrawer extends StatelessWidget {
  final String currentStatus;

  const DriverSideDrawer({super.key, required this.currentStatus});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      width: 75.w,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(35), 
          bottomLeft: Radius.circular(35)
        )
      ),
      child: Column(
        children: [
          // 👤 هيدر البروفايل (تصميم لوجستي جذاب)
          _buildDrawerHeader(),
          
          // 📋 قائمة الخيارات
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
              children: [
                _buildDrawerItem(
                  context, 
                  Icons.account_circle_outlined, 
                  "حسابي الشخصي", 
                  () => Navigator.push(context, MaterialPageRoute(builder: (context) => const ProfileScreen()))
                ),
                _buildDrawerItem(
                  context, 
                  Icons.privacy_tip_outlined, 
                  "سياسة الخصوصية", 
                  _launchPrivacyPolicy
                ),
                _buildDrawerItem(
                  context, 
                  Icons.help_outline_rounded, 
                  "الدعم الفني", 
                  () => Navigator.push(context, MaterialPageRoute(builder: (context) => const SupportScreen()))
                ),
              ],
            ),
          ),

          // 🚪 زر تسجيل الخروج
          const Divider(indent: 20, endIndent: 20),
          _buildLogoutTile(context),
          const SizedBox(height: 15),
        ],
      ),
    );
  }

  Widget _buildDrawerHeader() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [Colors.orange[900]!, Colors.orange[700]!]),
        borderRadius: const BorderRadius.only(bottomRight: Radius.circular(30)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const CircleAvatar(
                radius: 35, 
                backgroundColor: Colors.white, 
                child: Icon(Icons.person, size: 45, color: Colors.orange)
              ),
              const SizedBox(height: 15),
              const Text(
                "كابتن أكسب", 
                style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w900, fontSize: 18, color: Colors.white)
              ),
              Text(
                FirebaseAuth.instance.currentUser?.email ?? "driver@aksab.shop", 
                style: const TextStyle(fontFamily: 'Cairo', color: Colors.white70, fontSize: 12)
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDrawerItem(BuildContext context, IconData icon, String title, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: Colors.blueGrey[700]),
      title: Text(title, style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w600, fontSize: 14)),
      trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
      onTap: onTap,
    );
  }

  Widget _buildLogoutTile(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.logout_rounded, color: Colors.redAccent),
      title: const Text(
        "تسجيل الخروج", 
        style: TextStyle(fontFamily: 'Cairo', color: Colors.redAccent, fontWeight: FontWeight.bold)
      ),
      onTap: () async {
        if (currentStatus == 'busy') {
          DriverSecurityHelper.showErrorSnackBar(context, "لا يمكن تسجيل الخروج أثناء وجود عهدة نشطة");
          return;
        }
        await FirebaseAuth.instance.signOut();
        if (context.mounted) Navigator.pushReplacementNamed(context, '/login');
      },
    );
  }

  Future<void> _launchPrivacyPolicy() async {
    final Uri url = Uri.parse('https://aksab.shop/');
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      debugPrint("Could not launch privacy policy URL");
    }
  }
}


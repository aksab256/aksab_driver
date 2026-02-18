import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:sizer/sizer.dart';

class SupportScreen extends StatelessWidget {
  const SupportScreen({super.key});

  // دالة موحدة لفتح الروابط
  Future<void> _handleSupportAction(BuildContext context, String url) async {
    final Uri uri = Uri.parse(url);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        throw 'Could not launch $url';
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("عذراً، لا يمكن فتح الرابط حالياً")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FA),
      appBar: AppBar(
        title: const Text("مركز الدعم والمساعدة", 
          style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, color: Colors.white)),
        centerTitle: true,
        backgroundColor: const Color(0xFF2C3E50), // لون احترافي متناسق مع تطبيقاتك
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // رأس الصفحة بتصميم جذاب
            Container(
              width: 100.w,
              padding: EdgeInsets.all(20.sp),
              decoration: const BoxDecoration(
                color: Color(0xFF2C3E50),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(30),
                  bottomRight: Radius.circular(30),
                ),
              ),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 40.sp,
                    backgroundColor: Colors.white.withOpacity(0.2),
                    child: Icon(Icons.support_agent_rounded, size: 50.sp, color: Colors.white),
                  ),
                  SizedBox(height: 2.h),
                  const Text("كيف يمكننا مساعدتك يا كابتن؟",
                    style: TextStyle(fontFamily: 'Cairo', fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                ],
              ),
            ),
            
            Padding(
              padding: EdgeInsets.all(15.sp),
              child: Column(
                children: [
                  _buildSupportCard(
                    context,
                    title: "محادثة واتساب مباشرة",
                    subtitle: "لحل مشاكل التحصيل والتوصيل السريعة",
                    icon: Icons.chat_outlined,
                    color: Colors.green,
                    onTap: () => _handleSupportAction(context, "https://wa.me/201021070462"), // استبدل بالرقم
                  ),
                  
                  _buildSupportCard(
                    context,
                    title: "اتصال هاتفي",
                    subtitle: "للطوارئ والأعطال الفنية",
                    icon: Icons.phone_in_talk_rounded,
                    color: Colors.blue,
                    onTap: () => _handleSupportAction(context, "tel:201128887752"), // استبدل بالرقم
                  ),

                  _buildSupportCard(
                    context,
                    title: "الشات الذكي (Smart Chat)",
                    subtitle: "تواصل مع الإدارة عبر الرسائل الداخلية",
                    icon: Icons.auto_awesome_rounded,
                    color: Colors.purple,
                    onTap: () {
                      // هنا يمكنك فتح صفحة الشات التي برمجناها سابقاً
                    },
                  ),

                  _buildSupportCard(
                    context,
                    title: "سياسة المنصة وقواعد العمل",
                    subtitle: "دليلك للعمل بكفاءة مع أكسب",
                    icon: Icons.rule_rounded,
                    color: Colors.orange,
                    onTap: () => _handleSupportAction(context, "https://aksab.shop/terms"), 
                  ),

                  SizedBox(height: 3.h),
                  const Text("نسخة التطبيق: 1.0.10 (Build 10)", 
                    style: TextStyle(fontFamily: 'Cairo', fontSize: 10, color: Colors.grey)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSupportCard(BuildContext context, {required String title, required String subtitle, required IconData icon, required Color color, required VoidCallback onTap}) {
    return Container(
      margin: EdgeInsets.only(bottom: 12.sp),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: ListTile(
        contentPadding: EdgeInsets.symmetric(horizontal: 15.sp, vertical: 8.sp),
        leading: Container(
          padding: EdgeInsets.all(8.sp),
          decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
          child: Icon(icon, color: color),
        ),
        title: Text(title, style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 15)),
        subtitle: Text(subtitle, style: const TextStyle(fontFamily: 'Cairo', fontSize: 11, color: Colors.grey)),
        trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
        onTap: onTap,
      ),
    );
  }
}

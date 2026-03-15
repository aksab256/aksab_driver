import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:sizer/sizer.dart';
import 'package:flutter/services.dart'; // للنسخ إلى الحافظة
import 'package:share_plus/share_plus.dart'; // للمشاركة عبر الواتساب وغيره

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final String? _uid = FirebaseAuth.instance.currentUser?.uid;

  // دالة الحذف الناعم (Soft Delete)
  Future<void> _handleSoftDelete() async {
    bool confirm = await showDialog(
          context: context,
          builder: (ctx) => Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: const Text("تأكيد حذف الحساب ⚠️",
                  style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, color: Colors.red)),
              content: const Text("هل أنت متأكد من حذف حسابك نهائياً؟ سيتم إيقاف الخدمة وفقدان جميع بياناتك الحالية."),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text("تراجع", style: TextStyle(fontFamily: 'Cairo'))),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text("تأكيد الحذف", style: TextStyle(fontFamily: 'Cairo', color: Colors.white)),
                ),
              ],
            ),
          ),
        ) ??
        false;

    if (confirm && _uid != null) {
      await FirebaseFirestore.instance.collection('freeDrivers').doc(_uid).update({
        'status': 'deleted_by_user',
        'lastSeen': FieldValue.serverTimestamp(),
      });

      await FirebaseAuth.instance.signOut();
      if (mounted) Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
    }
  }

  // دالة مشاركة الكود
  void _shareReferralCode(String code) {
    String message = """
انضم إليّ في فريق مناديب أكسب! 🚚
استخدم كود الإحالة الخاص بي: ($code) عند التسجيل وابدأ في إدارة عهدتك وزيادة أرباحك.
حمل التطبيق الآن من هنا: https://aksab.shop/
""";
    Share.share(message);
  }

  // دالة نسخ الكود
  void _copyToClipboard(String code) {
    Clipboard.setData(ClipboardData(text: code));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("تم نسخ كود الإحالة بنجاح ✅", textAlign: TextAlign.center, style: TextStyle(fontFamily: 'Cairo')),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text("حسابي الشخصي", style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('freeDrivers').doc(_uid).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          if (!snapshot.data!.exists) return const Center(child: Text("المستند غير موجود"));

          var data = snapshot.data!.data() as Map<String, dynamic>;
          String myCode = data['myReferralCode'] ?? "سيظهر قريباً";

          return SingleChildScrollView(
            padding: EdgeInsets.all(15.sp),
            child: Column(
              children: [
                // كارت دعوة الأصدقاء (Referral Card) الجديد المطور
                _buildReferralCard(myCode),
                SizedBox(height: 15.sp),
                // كارت المعلومات المالية (الرصيد والعهد)
                _buildInfoCard(
                  title: "الوضع اللوجستي (العهدة)",
                  icon: Icons.account_balance_wallet,
                  color: Colors.green[700]!,
                  children: [
                    _buildDataRow("نقاط التأمين (الرصيد)", "${data['walletBalance'] ?? 0}"),
                    _buildDataRow("حد الأمان للعهدة", "${data['creditLimit'] ?? 0}"),
                    _buildDataRow("إجمالي الإحالات الناجحة", "${data['totalReferralsCount'] ?? 0}"),
                  ],
                ),
                SizedBox(height: 15.sp),
                // كارت بيانات المركبة والهوية
                _buildInfoCard(
                  title: "بيانات التسجيل",
                  icon: Icons.delivery_dining,
                  color: Colors.blue[800]!,
                  children: [
                    _buildDataRow("الاسم", data['fullname'] ?? "غير مسجل"),
                    _buildDataRow("رقم الهاتف", data['phone'] ?? ""),
                    _buildDataRow("نوع المركبة", _getVehicleName(data['vehicleConfig'])),
                    _buildDataRow("الحالة", data['status'] == 'approved' ? "نشط ومفعل ✅" : "قيد المراجعة"),
                  ],
                ),
                SizedBox(height: 30.sp),
                // زر حذف الحساب
                TextButton.icon(
                  onPressed: _handleSoftDelete,
                  icon: const Icon(Icons.delete_forever, color: Colors.red),
                  label: const Text("حذف الحساب نهائياً",
                      style: TextStyle(color: Colors.red, fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                ),
                Text("الإصدار 1.0.0", style: TextStyle(color: Colors.grey, fontSize: 10.sp)),
              ],
            ),
          );
        },
      ),
    );
  }

  // ويدجت كارت دعوة الأصدقاء - معدل لعرض رسالة الإغراء وتوضيح نقاط الأمان
  Widget _buildReferralCard(String code) {
    return StreamBuilder<DocumentSnapshot>(
      // نجلب معرف الحملة النشطة أولاً
      stream: FirebaseFirestore.instance.collection('appSettings').doc('referralConfig').snapshots(),
      builder: (context, configSnap) {
        String activeId = "default_launch";
        if (configSnap.hasData && configSnap.data!.exists) {
          activeId = configSnap.data!.get('activeCampaignId') ?? "default_launch";
        }

        return Container(
          padding: EdgeInsets.all(15.sp),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Colors.orange[900]!, Colors.orange[700]!],
            ),
            borderRadius: BorderRadius.circular(25),
            boxShadow: [BoxShadow(color: Colors.orange.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 5))],
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.stars, color: Colors.yellowAccent),
                      SizedBox(width: 8.sp),
                      Text("برنامج مكافآت الداعي",
                          style: TextStyle(
                              fontFamily: 'Cairo',
                              fontWeight: FontWeight.bold,
                              fontSize: 13.sp,
                              color: Colors.white)),
                    ],
                  ),
                  const Icon(Icons.share_arrival_time, color: Colors.white54),
                ],
              ),
              const Divider(color: Colors.white24),
              SizedBox(height: 10.sp),

              // --- عرض رسالة الإغراء (campaignName) من الفايربيز ---
              StreamBuilder<DocumentSnapshot>(
                stream: FirebaseFirestore.instance.collection('referralCampaigns').doc(activeId).snapshots(),
                builder: (context, campSnap) {
                  String campaignMsg = "شارك كودك مع زملائك المناديب وابدأ في جني مكافآت التشغيل فوراً!";
                  Map<String, dynamic> milestones = {};

                  if (campSnap.hasData && campSnap.data!.exists) {
                    var campData = campSnap.data!.data() as Map<String, dynamic>;
                    campaignMsg = campData['campaignName'] ?? campaignMsg;
                    milestones = campData['milestones'] as Map<String, dynamic>? ?? {};
                  }

                  return Column(
                    children: [
                      Text(
                        campaignMsg,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: Colors.white, fontSize: 11.sp, fontFamily: 'Cairo', fontWeight: FontWeight.w500),
                      ),
                      SizedBox(height: 15.sp),
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 12.sp, vertical: 8.sp),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15)),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(code,
                                style: TextStyle(
                                    fontSize: 18.sp,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 2,
                                    color: Colors.orange[900])),
                            Row(
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.copy, color: Colors.grey),
                                  onPressed: () => _copyToClipboard(code),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.share, color: Colors.green),
                                  onPressed: () => _shareReferralCode(code),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: 15.sp),

                      // عرض الأهداف (Milestones) بشكل جذاب
                      if (milestones.isNotEmpty)
                        Container(
                          padding: EdgeInsets.all(10.sp),
                          decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(15)),
                          child: Column(
                            children: [
                              Text("خطة مكافآتك عن كل زميل جديد 🎁",
                                  style: TextStyle(
                                      color: Colors.yellowAccent,
                                      fontWeight: FontWeight.bold,
                                      fontFamily: 'Cairo',
                                      fontSize: 10.sp)),
                              SizedBox(height: 8.sp),
                              ...milestones.entries.map((e) {
                                String num = e.key.split('_').last;
                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 2),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.check_circle_outline, color: Colors.white70, size: 14),
                                      const SizedBox(width: 5),
                                      Text("أوردر رقم $num: مكافأة ${e.value} ج.م",
                                          style: const TextStyle(
                                              color: Colors.white, fontSize: 10, fontFamily: 'Cairo')),
                                    ],
                                  ),
                                );
                              }).toList(),
                              const Divider(color: Colors.white10),
                              const Text(
                                "💡 المكافآت تُضاف كـ (نقاط أمان) لرفع حد عهدتك ومساعدتك في قبول طلبيات أكبر.",
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.white70, fontSize: 9, fontFamily: 'Cairo'),
                              ),
                            ],
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildInfoCard(
      {required String title, required IconData icon, required Color color, required List<Widget> children}) {
    return Container(
      padding: EdgeInsets.all(15.sp),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 5))],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(icon, color: color),
              SizedBox(width: 10.sp),
              Text(title,
                  style:
                      TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 13.sp, color: color)),
            ],
          ),
          const Divider(),
          ...children,
        ],
      ),
    );
  }

  Widget _buildDataRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8.sp),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontFamily: 'Cairo', color: Colors.grey)),
          Text(value, style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 11.sp)),
        ],
      ),
    );
  }

  String _getVehicleName(String? config) {
    switch (config) {
      case 'motorcycleConfig':
        return "موتوسيكل";
      case 'pickupConfig':
        return "بيك أب (دبابة)";
      case 'jumboConfig':
        return "جامبو / نقل";
      default:
        return "مركبة توصيل";
    }
  }
}


import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:sizer/sizer.dart';

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
          title: const Text("تأكيد حذف الحساب ⚠️", style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, color: Colors.red)),
          content: const Text("هل أنت متأكد من حذف حسابك نهائياً؟ سيتم إيقاف الخدمة وفقدان جميع بياناتك الحالية."),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("تراجع", style: TextStyle(fontFamily: 'Cairo'))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text("تأكيد الحذف", style: TextStyle(fontFamily: 'Cairo', color: Colors.white)),
            ),
          ],
        ),
      ),
    ) ?? false;

    if (confirm && _uid != null) {
      // تنفيذ الحذف الناعم في Firestore
      await FirebaseFirestore.instance.collection('freeDrivers').doc(_uid).update({
        'status': 'deleted_by_user', // تغيير الحالة بدلاً من حذف المستند
        'lastSeen': FieldValue.serverTimestamp(),
      });
      
      // تسجيل الخروج والعودة للبداية
      await FirebaseAuth.instance.signOut();
      if (mounted) Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: () => Navigator.pop(context), // رجوع خطوة واحدة فقط
        ),
        title: const Text("حسابي الشخصي", style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('freeDrivers').doc(_uid).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          var data = snapshot.data!.data() as Map<String, dynamic>;

          return SingleChildScrollView(
            padding: EdgeInsets.all(15.sp),
            child: Column(
              children: [
                // كارت المعلومات المالية (الرصيد والعهد)
                _buildInfoCard(
                  title: "الوضع المالي",
                  icon: Icons.account_balance_wallet,
                  color: Colors.green[700]!,
                  children: [
                    _buildDataRow("رصيد المحفظة", "${data['walletBalance'] ?? 0} ج.م"),
                    _buildDataRow("حد الائتمان", "${data['creditLimit'] ?? 0} ج.م"),
                    _buildDataRow("الطلبات المكتملة", "${data['totalOrders'] ?? 0}"),
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
                  label: const Text("حذف الحساب نهائياً", style: TextStyle(color: Colors.red, fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                ),
                Text("الإصدار 1.0.0", style: TextStyle(color: Colors.grey, fontSize: 10.sp)),
              ],
            ),
          );
        },
      ),
    );
  }

  // ويدجت لبناء الكروت بشكل موحد
  Widget _buildInfoCard({required String title, required IconData icon, required Color color, required List<Widget> children}) {
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
              Text(title, style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 13.sp, color: color)),
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
      case 'motorcycleConfig': return "موتوسيكل";
      case 'pickupConfig': return "بيك أب (دبابة)";
      case 'jumboConfig': return "جامبو / نقل";
      default: return "مركبة توصيل";
    }
  }
}

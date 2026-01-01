import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:sizer/sizer.dart';
import 'package:intl/intl.dart';

class DeliveryFleetScreen extends StatefulWidget {
  const DeliveryFleetScreen({super.key});

  @override
  State<DeliveryFleetScreen> createState() => _DeliveryFleetScreenState();
}

class _DeliveryFleetScreenState extends State<DeliveryFleetScreen> {
  final String currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F2F6),
      appBar: AppBar(
        title: const Text("إدارة أسطول التوصيل",
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF2F3542),
        elevation: 0,
        centerTitle: true,
      ),
      body: StreamBuilder<QuerySnapshot>(
        // الفلتر الذكي المعتمد على managerId وتجاهل المبيعات
        stream: _firestore
            .collection('managers')
            .where('managerId', isEqualTo: currentUserId)
            .where('role', isEqualTo: 'delivery_supervisor')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
                child: CircularProgressIndicator(color: Color(0xFF1ABC9C)));
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return _buildEmptyState();
          }

          return ListView.builder(
            padding: EdgeInsets.symmetric(horizontal: 10.sp, vertical: 15.sp),
            itemCount: snapshot.data!.docs.length,
            itemBuilder: (context, index) {
              var doc = snapshot.data!.docs[index];
              var data = doc.data() as Map<String, dynamic>;
              return _buildSupervisorCard(doc.id, data);
            },
          );
        },
      ),
    );
  }

  Widget _buildSupervisorCard(String docId, Map<String, dynamic> data) {
    List areas = data['geographicArea'] ?? [];
    String currentMonth = DateFormat('yyyy-MM').format(DateTime.now());
    bool hasTarget =
        data['targets'] != null && data['targets'][currentMonth] != null;

    return Container(
      // التصحيح التقني هنا: استخدام .only بدلًا من .bottom
      margin: EdgeInsets.only(bottom: 12.sp),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 5))
        ],
      ),
      child: Column(
        children: [
          ListTile(
            contentPadding: EdgeInsets.all(12.sp),
            leading: CircleAvatar(
              radius: 25,
              backgroundColor: const Color(0xFF1ABC9C).withOpacity(0.1),
              child: const Icon(Icons.delivery_dining,
                  color: Color(0xFF1ABC9C), size: 30),
            ),
            title: Text(data['fullname'] ?? 'مشرف غير مسمى',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13.sp,
                    color: const Color(0xFF2F3542))),
            subtitle: Text(data['phone'] ?? 'بدون رقم هاتف',
                style: TextStyle(fontSize: 10.sp)),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: hasTarget
                    ? Colors.green.withOpacity(0.1)
                    : Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(
                hasTarget ? "تم تعيين الهدف" : "بدون هدف",
                style: TextStyle(
                    color: hasTarget ? Colors.green : Colors.orange,
                    fontSize: 8.sp,
                    fontWeight: FontWeight.bold),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 15.sp),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildInfoItem(Icons.map_outlined, "المناطق", "${areas.length}"),
                _buildInfoItem(
                    Icons.calendar_month_outlined,
                    "تاريخ البدء",
                    data['approvedAt'] != null
                        ? DateFormat('yyyy/MM/dd').format(
                            (data['approvedAt'] as Timestamp).toDate())
                        : "قيد المراجعة"),
              ],
            ),
          ),
          SizedBox(height: 10.sp),
          Container(
            padding: EdgeInsets.all(8.sp),
            decoration: const BoxDecoration(
              color: Color(0xFFF8F9FA),
              borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(15),
                  bottomRight: Radius.circular(15)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextButton.icon(
                    onPressed: () {
                      debugPrint("الانتقال لتوزيع مناطق المشرف: $docId");
                      // يمكنك هنا إضافة التوجيه لصفحة الخريطة إذا أردت
                    },
                    icon: const Icon(Icons.location_on,
                        size: 18, color: Colors.teal),
                    label: const Text("توزيع المناطق",
                        style: TextStyle(color: Colors.teal)),
                  ),
                ),
                const VerticalDivider(),
                Expanded(
                  child: TextButton.icon(
                    onPressed: () =>
                        _showSetTargetDialog(docId, data['fullname'] ?? ""),
                    icon: const Icon(Icons.ads_click,
                        size: 18, color: Colors.blueAccent),
                    label: const Text("تحديد الهدف",
                        style: TextStyle(color: Colors.blueAccent)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoItem(IconData icon, String label, String value) {
    return Column(
      children: [
        Icon(icon, size: 16, color: Colors.grey),
        SizedBox(height: 4.sp),
        Text(label, style: TextStyle(color: Colors.grey, fontSize: 9.sp)),
        Text(value,
            style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 10.sp,
                color: const Color(0xFF2F3542))),
      ],
    );
  }

  void _showSetTargetDialog(String docId, String name) {
    final TextEditingController financialController = TextEditingController();
    final TextEditingController visitsController = TextEditingController();
    final TextEditingController hoursController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: Text("تعيين هدف لـ $name",
            textAlign: TextAlign.center, style: TextStyle(fontSize: 14.sp)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDialogField(
                  financialController, "الهدف المالي الشهري (ج.م)", Icons.money),
              _buildDialogField(
                  visitsController, "هدف عدد الطلبات/الزيارات", Icons.shopping_bag),
              _buildDialogField(
                  hoursController, "ساعات العمل المطلوبة", Icons.timer),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("إلغاء")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1ABC9C)),
            onPressed: () async {
              String month = DateFormat('yyyy-MM').format(DateTime.now());
              await _firestore.collection('managers').doc(docId).update({
                'targets.$month': {
                  'financialTarget': financialController.text,
                  'visitsTarget': visitsController.text,
                  'hoursTarget': hoursController.text,
                  'dateSet': DateTime.now(),
                }
              });
              if (mounted) Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("تم حفظ الأهداف بنجاح ✅")));
            },
            child:
                const Text("حفظ الهدف", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildDialogField(
      TextEditingController ctrl, String label, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: ctrl,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          prefixIcon: Icon(icon, size: 20),
          labelText: label,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.people_outline, size: 60.sp, color: Colors.grey[400]),
          SizedBox(height: 10.sp),
          Text("لا يوجد مشرفو توصيل مسجلين تحت إدارتك",
              style: TextStyle(color: Colors.grey, fontSize: 12.sp)),
        ],
      ),
    );
  }
}


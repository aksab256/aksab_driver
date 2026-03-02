import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:sizer/sizer.dart';
import 'package:intl/intl.dart';

// استيراد الشاشات المطلوبة للربط
import 'DeliveryPerformanceScreen.dart';
import 'manager_geo_dist_screen.dart';

class DeliveryFleetScreen extends StatefulWidget {
  const DeliveryFleetScreen({super.key});

  @override
  State<DeliveryFleetScreen> createState() => _DeliveryFleetScreenState();
}

class _DeliveryFleetScreenState extends State<DeliveryFleetScreen> {
  final String currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String? userRole;
  String? userDocId;
  bool isLoadingRole = true;

  @override
  void initState() {
    super.initState();
    _checkRole();
  }

  Future<void> _checkRole() async {
    try {
      final snap = await _firestore
          .collection('managers')
          .where('uid', isEqualTo: currentUserId)
          .get();

      if (snap.docs.isNotEmpty) {
        setState(() {
          userRole = snap.docs.first.data()['role'];
          userDocId = snap.docs.first.id;
          isLoadingRole = false;
        });
      } else {
        setState(() => isLoadingRole = false);
      }
    } catch (e) {
      setState(() => isLoadingRole = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoadingRole) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    Query query;
    if (userRole == 'delivery_manager') {
      query = _firestore.collection('managers')
          .where('managerId', isEqualTo: currentUserId)
          .where('role', isEqualTo: 'delivery_supervisor');
    } else {
      query = _firestore.collection('deliveryReps')
          .where('supervisorId', isEqualTo: userDocId);
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF1F2F6),
      appBar: AppBar(
        title: Text(
          userRole == 'delivery_manager' ? "إدارة المشرفين" : "فريق المناديب التابع لي",
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF2F3542),
        elevation: 0,
        centerTitle: true,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: query.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Color(0xFF1ABC9C)));
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

              return _buildFleetCard(doc.id, data);
            },
          );
        },
      ),
    );
  }

  Widget _buildFleetCard(String docId, Map<String, dynamic> data) {
    String currentMonth = DateFormat('yyyy-MM').format(DateTime.now());
    bool hasTarget = data['targets'] != null && data['targets'][currentMonth] != null;

    return Container(
      margin: EdgeInsets.only(bottom: 12.sp),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 5),
          )
        ],
      ),
      child: Column(
        children: [
          ListTile(
            onTap: () {
              // الربط الصحيح مع الشاشة الجديدة مع تمرير كافة المتغيرات المطلوبة
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => DeliveryPerformanceScreen(
                    repId: docId,
                    repCode: data['repCode'] ?? docId,
                    repName: data['fullname'] ?? 'غير مسمى',
                  ),
                ),
              );
            },
            contentPadding: EdgeInsets.all(12.sp),
            leading: CircleAvatar(
              radius: 25,
              backgroundColor: const Color(0xFF1ABC9C).withOpacity(0.1),
              child: Icon(
                userRole == 'delivery_manager' ? Icons.badge : Icons.delivery_dining,
                color: const Color(0xFF1ABC9C),
                size: 30,
              ),
            ),
            title: Text(
              data['fullname'] ?? 'غير مسمى',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13.sp,
                color: const Color(0xFF2F3542),
              ),
            ),
            subtitle: Text(
              data['phone'] ?? 'بدون رقم هاتف',
              style: TextStyle(fontSize: 10.sp),
            ),
            trailing: _buildStatusBadge(hasTarget),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 15.sp),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                if (userRole == 'delivery_manager')
                  _buildInfoItem(Icons.map_outlined, "المناطق", "${(data['geographicArea'] as List?)?.length ?? 0}"),
                if (userRole == 'delivery_supervisor')
                  _buildInfoItem(Icons.qr_code, "كود المندوب", "${data['repCode'] ?? '---'}"),
                _buildInfoItem(
                  Icons.calendar_month_outlined,
                  "تاريخ البدء",
                  data['approvedAt'] != null
                      ? DateFormat('yyyy/MM/dd').format((data['approvedAt'] as Timestamp).toDate())
                      : "جديد",
                ),
              ],
            ),
          ),
          SizedBox(height: 10.sp),
          _buildActionButtons(docId, data),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(bool hasTarget) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: hasTarget ? Colors.green.withOpacity(0.1) : Colors.orange.withOpacity(0.1),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        hasTarget ? "تم تعيين الهدف" : "بدون هدف",
        style: TextStyle(
          color: hasTarget ? Colors.green : Colors.orange,
          fontSize: 8.sp,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildActionButtons(String docId, Map<String, dynamic> data) {
    return Container(
      padding: EdgeInsets.all(8.sp),
      decoration: const BoxDecoration(
        color: Color(0xFFF8F9FA),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(15),
          bottomRight: Radius.circular(15),
        ),
      ),
      child: Row(
        children: [
          if (userRole == 'delivery_manager')
            Expanded(
              child: TextButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const ManagerGeoDistScreen(),
                    ),
                  );
                },
                icon: const Icon(Icons.location_on, size: 18, color: Colors.teal),
                label: const Text("توزيع المناطق", style: TextStyle(color: Colors.teal)),
              ),
            ),
          if (userRole == 'delivery_manager') const VerticalDivider(),
          Expanded(
            child: TextButton.icon(
              onPressed: () => _showSetTargetDialog(docId, data['fullname'] ?? ""),
              icon: const Icon(Icons.ads_click, size: 18, color: Colors.blueAccent),
              label: const Text("تحديد الهدف", style: TextStyle(color: Colors.blueAccent)),
            ),
          ),
        ],
      ),
    );
  }

  void _showSetTargetDialog(String docId, String name) {
    final TextEditingController financialController = TextEditingController();
    final TextEditingController visitsController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("تعيين هدف لـ $name", textAlign: TextAlign.center),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildDialogField(financialController, "الهدف المالي (ج.م)", Icons.money),
            _buildDialogField(visitsController, "هدف عدد الطلبات", Icons.shopping_bag),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("إلغاء")),
          ElevatedButton(
            onPressed: () async {
              String month = DateFormat('yyyy-MM').format(DateTime.now());
              String collectionName = userRole == 'delivery_manager' ? 'managers' : 'deliveryReps';

              await _firestore.collection(collectionName).doc(docId).update({
                'targets.$month': {
                  'financialTarget': double.tryParse(financialController.text) ?? 0.0,
                  'invoiceTarget': int.tryParse(visitsController.text) ?? 0,
                  'dateSet': DateTime.now(),
                }
              });
              if (mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("تم حفظ الهدف بنجاح ✅")),
                );
              }
            },
            child: const Text("حفظ"),
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
        Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10.sp)),
      ],
    );
  }

  Widget _buildDialogField(TextEditingController ctrl, String label, IconData icon) {
    return TextField(
      controller: ctrl,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Text(
        userRole == 'delivery_manager' ? "لا يوجد مشرفين" : "لا يوجد مناديب تابعين لك",
      ),
    );
  }
}

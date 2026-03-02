import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:sizer/sizer.dart';
import 'package:intl/intl.dart';

class RepPerformanceSupervisorScreen extends StatefulWidget {
  final String repCode;
  final String repName;

  const RepPerformanceSupervisorScreen({
    super.key, 
    required this.repCode, 
    required this.repName
  });

  @override
  State<RepPerformanceSupervisorScreen> createState() => _RepPerformanceSupervisorScreenState();
}

class _RepPerformanceSupervisorScreenState extends State<RepPerformanceSupervisorScreen> {
  // الفلترة التلقائية لآخر 48 ساعة
  DateTime startDate = DateTime.now().subtract(const Duration(hours: 48));
  DateTime endDate = DateTime.now();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F6),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1B5E20),
        elevation: 0,
        title: Column(
          children: [
            Text("متابعة أداء المندوب", style: TextStyle(fontSize: 10.sp, color: Colors.white70)),
            Text(widget.repName, style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.bold, color: Colors.white)),
          ],
        ),
        centerTitle: true,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('waitingdelivery')
            .where('repCode', isEqualTo: widget.repCode)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Color(0xFF1B5E20)));
          }

          final docs = snapshot.data?.docs ?? [];
          
          // --- الحسابات المنطقية ---
          int pendingCount = 0;
          int deliveredCount = 0;
          int failedCount = 0;
          double currentEscrow = 0.0; // العهدة اللي لسه موردهاش

          for (var doc in docs) {
            final data = doc.data() as Map<String, dynamic>;
            final status = data['deliveryTaskStatus'] ?? 'pending';
            final amount = (data['netTotal'] ?? data['total'] ?? 0.0).toDouble();

            if (status == 'pending') {
              pendingCount++;
            } else {
              // فلترة زمنية للعمليات المنتهية (48 ساعة)
              Timestamp? ts = data['completedAt'] as Timestamp?;
              if (ts != null) {
                DateTime date = ts.toDate();
                if (date.isAfter(startDate) && date.isBefore(endDate.add(const Duration(days: 1)))) {
                  if (status == 'delivered') {
                    deliveredCount++;
                    // لو لسه موردهاش للمحاسب، نزودها في العهدة الحالية
                    if (data['isSettled'] == false) {
                      currentEscrow += amount;
                    }
                  } else if (status == 'failed') {
                    failedCount++;
                  }
                }
              }
            }
          }

          return Column(
            children: [
              _buildHeaderStats(pendingCount, deliveredCount, failedCount, currentEscrow),
              Expanded(
                child: _buildOperationList(docs),
              ),
            ],
          );
        },
      ),
    );
  }

  // الجزء العلوي: عدادات المشرف
  Widget _buildHeaderStats(int p, int d, int f, double escrow) {
    return Container(
      padding: EdgeInsets.all(15.sp),
      decoration: const BoxDecoration(
        color: Color(0xFF1B5E20),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(25)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _statItem("قيد التنفيذ", "$p", Icons.hourglass_empty, Colors.amber),
              _statItem("تم التسليم", "$d", Icons.check_circle, Colors.greenAccent),
              _statItem("مرتجع", "$f", Icons.error, Colors.orangeAccent),
            ],
          ),
          SizedBox(height: 15.sp),
          Container(
            padding: EdgeInsets.all(12.sp),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: Colors.white24),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.payments, color: Colors.white, size: 20.sp),
                SizedBox(width: 10.sp),
                Text("العهدة الحالية بالشارع: ", style: TextStyle(color: Colors.white70, fontSize: 11.sp)),
                Text("${escrow.toStringAsFixed(2)} ج.م", 
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.black, fontSize: 15.sp)),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _statItem(String label, String value, IconData icon, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 18.sp),
        SizedBox(height: 5.sp),
        Text(value, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14.sp)),
        Text(label, style: TextStyle(color: Colors.white60, fontSize: 9.sp)),
      ],
    );
  }

  // الجزء السفلي: قائمة العمليات (الرادار)
  Widget _buildOperationList(List<QueryDocumentSnapshot> allDocs) {
    // ترتيب الأوردرات (الأحدث فوق)
    allDocs.sort((a, b) {
      var dateA = (a['completedAt'] ?? a['assignedAt']) as Timestamp;
      var dateB = (b['completedAt'] ?? b['assignedAt']) as Timestamp;
      return dateB.compareTo(dateA);
    });

    return ListView.builder(
      padding: EdgeInsets.all(12.sp),
      itemCount: allDocs.length,
      itemBuilder: (context, index) {
        final data = allDocs[index].data() as Map<String, dynamic>;
        final status = data['deliveryTaskStatus'];
        final isSettled = data['isSettled'] ?? false;
        
        return Card(
          elevation: 0,
          margin: EdgeInsets.only(bottom: 8.sp),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade200)),
          child: ListTile(
            leading: _getStatusIcon(status),
            title: Text("طلب #${allDocs[index].id.substring(0, 8)}", style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(status == 'delivered' 
              ? (isSettled ? "تم التوريد للمركز ✅" : "لم يورد بعد ⏳") 
              : "حالة الطلب: $status"),
            trailing: Text("${data['netTotal'] ?? 0} ج.م", 
              style: TextStyle(fontWeight: FontWeight.w900, color: status == 'delivered' ? Colors.green[800] : Colors.black)),
          ),
        );
      },
    );
  }

  Widget _getStatusIcon(String status) {
    switch (status) {
      case 'delivered': return const Icon(Icons.check_circle, color: Colors.green);
      case 'failed': return const Icon(Icons.cancel, color: Colors.red);
      default: return const Icon(Icons.radio_button_checked, color: Colors.amber);
    }
  }
}

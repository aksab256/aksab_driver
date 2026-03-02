import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:sizer/sizer.dart';
import 'package:intl/intl.dart';

class DeliveryPerformanceScreen extends StatefulWidget {
  final String repId;    
  final String repCode;  
  final String repName;  

  const DeliveryPerformanceScreen({
    super.key,
    required this.repId,
    required this.repCode,
    required this.repName,
  });

  @override
  State<DeliveryPerformanceScreen> createState() => _DeliveryPerformanceScreenState();
}

class _DeliveryPerformanceScreenState extends State<DeliveryPerformanceScreen> {
  // نطاق زمني افتراضي للعرض (آخر 48 ساعة)
  DateTime limitDate = DateTime.now().subtract(const Duration(hours: 48));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: AppBar(
        title: Column(
          children: [
            Text("متابعة أداء المندوب", style: TextStyle(fontSize: 10.sp, color: Colors.white70)),
            Text(widget.repName, style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.bold, color: Colors.white)),
          ],
        ),
        centerTitle: true,
        backgroundColor: const Color(0xFF1B5E20),
        elevation: 0,
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

          var allDocs = snapshot.data?.docs ?? [];
          
          double totalInHand = 0;           // العهدة المالية التي لم تورد بعد
          double totalSettledInPeriod = 0;  // ما تم توريده للمركز خلال 48 ساعة
          int pendingTasks = 0;             // مهام لم تنته بعد
          List<QueryDocumentSnapshot> listForDisplay = [];

          for (var doc in allDocs) {
            final data = doc.data() as Map<String, dynamic>;
            
            // معالجة المبالغ المالية (إدارة نقاط الأمان)
            double amount = 0.0;
            if (data['netTotal'] != null) {
              amount = (data['netTotal']).toDouble();
            } else if (data['total'] != null) {
              amount = (data['total']).toDouble();
            }

            String status = data['deliveryTaskStatus'] ?? 'pending';
            bool isSettled = data['isSettled'] ?? false;
            
            // تحديد وقت العملية (إما وقت الإتمام أو وقت الإسناد)
            Timestamp? ts = data['completedAt'] as Timestamp? ?? data['assignedAt'] as Timestamp?;
            DateTime actionDate = ts != null ? ts.toDate() : DateTime.now();

            // 1. منطق حساب "العهدة بالشارع": أي طلب تم تسليمه ولم يورده المحاسب (بغض النظر عن تاريخه)
            if (status == 'delivered' && !isSettled) {
              totalInHand += amount;
            }

            // 2. حساب المهام المعلقة حالياً
            if (status == 'pending') {
              pendingTasks++;
            }

            // 3. حساب "ما تم توريده" في آخر 48 ساعة فقط
            if (isSettled && actionDate.isAfter(limitDate)) {
              if (status == 'delivered') totalSettledInPeriod += amount;
            }

            // 4. فلترة القائمة للعرض: نعرض أوردرات آخر 48 ساعة + أي أوردر لم يُصفَّ بعد
            if (actionDate.isAfter(limitDate) || !isSettled || status == 'pending') {
              listForDisplay.add(doc);
            }
          }

          // ترتيب القائمة: الأحدث في الأعلى دائماً
          listForDisplay.sort((a, b) {
            var tA = (a.data() as Map)['completedAt'] ?? (a.data() as Map)['assignedAt'] ?? Timestamp.now();
            var tB = (b.data() as Map)['completedAt'] ?? (b.data() as Map)['assignedAt'] ?? Timestamp.now();
            return tB.compareTo(tA);
          });

          return ListView(
            padding: EdgeInsets.all(12.sp),
            children: [
              _buildDateHeader(),
              SizedBox(height: 12.sp),
              
              Row(
                children: [
                  _finCard("العهدة بالشارع", totalInHand, Colors.orange[800]!, Icons.moped),
                  SizedBox(width: 8.sp),
                  _finCard("تم توريده (48س)", totalSettledInPeriod, Colors.blue[800]!, Icons.account_balance_wallet),
                ],
              ),
              
              SizedBox(height: 12.sp),
              _buildStatusBanner(pendingTasks),
              
              SizedBox(height: 20.sp),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("سجل العمليات الأخير", style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.bold, color: Colors.blueGrey[900])),
                  Icon(Icons.history, color: Colors.blueGrey, size: 18.sp),
                ],
              ),
              const Divider(),

              _buildDetailedList(listForDisplay),
            ],
          );
        },
      ),
    );
  }

  Widget _finCard(String title, double amount, Color color, IconData icon) {
    return Expanded(
      child: Container(
        padding: EdgeInsets.all(12.sp),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
          boxShadow: [BoxShadow(color: color.withOpacity(0.1), blurRadius: 8, offset: const Offset(0, 4))],
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22.sp),
            SizedBox(height: 6.sp),
            Text(title, style: TextStyle(fontSize: 9.sp, color: Colors.grey[600])),
            Text("${amount.toStringAsFixed(1)} ج.م", 
              style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w900, color: color)),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBanner(int pending) {
    bool hasWork = pending > 0;
    return Container(
      padding: EdgeInsets.all(12.sp),
      decoration: BoxDecoration(
        color: hasWork ? Colors.amber[50] : Colors.green[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: hasWork ? Colors.amber.shade200 : Colors.green.shade200),
      ),
      child: Row(
        children: [
          Icon(hasWork ? Icons.pending_actions : Icons.verified, 
              color: hasWork ? Colors.orange[800] : Colors.green[800], size: 18.sp),
          SizedBox(width: 10.sp),
          Text(
            hasWork ? "يوجد $pending مهمة لم تنتهِ بعد" : "جميع المهام المسندة مكتملة",
            style: TextStyle(fontSize: 11.sp, fontWeight: FontWeight.bold, color: hasWork ? Colors.orange[900] : Colors.green[900]),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailedList(List<QueryDocumentSnapshot> docs) {
    if (docs.isEmpty) {
      return Padding(
        padding: EdgeInsets.only(top: 50.sp),
        child: const Center(child: Text("لا توجد عمليات مسجلة في هذه الفترة")),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: docs.length,
      itemBuilder: (context, index) {
        var data = docs[index].data() as Map<String, dynamic>;
        bool isSettled = data['isSettled'] ?? false;
        String status = data['deliveryTaskStatus'] ?? 'pending';
        bool isDelivered = status == 'delivered';

        String price = (data['netTotal'] ?? data['total'] ?? 0).toString();

        return Card(
          elevation: 0,
          margin: EdgeInsets.symmetric(vertical: 5.sp),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade100)),
          child: ListTile(
            leading: _getStatusIcon(status, isSettled),
            title: Text("طلب #${docs[index].id.substring(0, 6)}", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.sp)),
            subtitle: Text(
              isSettled ? "تم التوريد للمركز ✅" : (isDelivered ? "كاش مع المندوب ⏳" : "حالة الطلب: $status"),
              style: TextStyle(fontSize: 9.sp),
            ),
            trailing: Text("$price ج.م", style: TextStyle(fontWeight: FontWeight.w900, color: isDelivered ? Colors.green[800] : Colors.black)),
          ),
        );
      },
    );
  }

  Widget _getStatusIcon(String status, bool isSettled) {
    if (status == 'delivered') {
      return CircleAvatar(backgroundColor: isSettled ? Colors.green[50] : Colors.orange[50], 
            child: Icon(isSettled ? Icons.done_all : Icons.payments, color: isSettled ? Colors.green : Colors.orange, size: 18.sp));
    } else if (status == 'failed') {
      return CircleAvatar(backgroundColor: Colors.red[50], child: Icon(Icons.close, color: Colors.red, size: 18.sp));
    } else {
      return CircleAvatar(backgroundColor: Colors.blue[50], child: Icon(Icons.more_horiz, color: Colors.blue, size: 18.sp));
    }
  }

  Widget _buildDateHeader() {
    return Row(
      children: [
        Icon(Icons.calendar_today, size: 10.sp, color: Colors.grey),
        SizedBox(width: 5.sp),
        Text(
          "التقرير يعرض آخر 48 ساعة من النشاط الميداني",
          style: TextStyle(fontSize: 9.sp, color: Colors.grey[600], fontWeight: FontWeight.w500),
        ),
      ],
    );
  }
}

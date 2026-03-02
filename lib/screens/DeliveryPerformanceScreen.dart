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
  // تصحيح نطاق التاريخ ليكون 48 ساعة من بداية يوم الأمس وحتى نهاية اليوم
  late DateTime startDate;
  late DateTime endDate;

  @override
  void initState() {
    super.initState();
    DateTime now = DateTime.now();
    // بداية يوم أمس (00:00:00)
    startDate = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 1));
    // نهاية يومنا الحالي (23:59:59)
    endDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: AppBar(
        title: Column(
          children: [
            const Text("متابعة أداء المندوب", style: TextStyle(fontSize: 12, color: Colors.white70)),
            Text(widget.repName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
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
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());

          var allDocs = snapshot.data?.docs ?? [];
          
          double totalInHand = 0;    
          double totalSettled = 0;   
          int pendingTasks = 0;      

          // تصفية البيانات برمجياً لضمان الدقة
          List<QueryDocumentSnapshot> filteredList = [];

          for (var doc in allDocs) {
            final data = doc.data() as Map<String, dynamic>;
            // معالجة مشكلة الـ Null في المبلغ
            double amount = 0.0;
            if (data['netTotal'] != null) amount = (data['netTotal']).toDouble();
            else if (data['total'] != null) amount = (data['total']).toDouble();

            if (data['deliveryTaskStatus'] == 'pending') {
              pendingTasks++;
              filteredList.add(doc); // إضافة المهام المعلقة للرؤية
            } else {
              Timestamp? ts = data['completedAt'] as Timestamp?;
              if (ts != null) {
                DateTime completedDate = ts.toDate();
                // التأكد أن العملية تقع ضمن الـ 48 ساعة
                if (completedDate.isAfter(startDate) && completedDate.isBefore(endDate)) {
                  filteredList.add(doc);
                  if (data['deliveryTaskStatus'] == 'delivered') {
                    if (data['isSettled'] == true) {
                      totalSettled += amount;
                    } else {
                      totalInHand += amount;
                    }
                  }
                }
              }
            }
          }

          return ListView(
            padding: EdgeInsets.all(12.sp),
            children: [
              _buildDateFilter(),
              SizedBox(height: 15.sp),
              
              Row(
                children: [
                  _finCard("العهدة الحالية", totalInHand, Colors.orange[800]!, Icons.moped),
                  SizedBox(width: 8.sp),
                  _finCard("تم توريده", totalSettled, Colors.blue[800]!, Icons.account_balance),
                ],
              ),
              
              SizedBox(height: 12.sp),
              _buildStatusBanner(pendingTasks),
              
              SizedBox(height: 20.sp),
              const Text("سجل عمليات العهدة (التفاصيل)", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const Divider(),

              _buildDetailedList(filteredList),
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
          boxShadow: [BoxShadow(color: color.withOpacity(0.1), blurRadius: 10)],
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 25),
            const SizedBox(height: 5),
            Text(title, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            Text("${amount.toStringAsFixed(1)} ج.م", 
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: color)),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBanner(int pending) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: pending > 0 ? Colors.amber[50] : Colors.green[50],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.hourglass_bottom, color: pending > 0 ? Colors.orange : Colors.green),
          const SizedBox(width: 10),
          Text("متبقي $pending مهمة قيد التوصيل", style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildDetailedList(List<QueryDocumentSnapshot> docs) {
    // ترتيب العمليات من الأحدث للأقدم
    docs.sort((a, b) {
      Timestamp tA = (a.data() as Map)['completedAt'] ?? (a.data() as Map)['assignedAt'] ?? Timestamp.now();
      Timestamp tB = (b.data() as Map)['completedAt'] ?? (b.data() as Map)['assignedAt'] ?? Timestamp.now();
      return tB.compareTo(tA);
    });

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: docs.length,
      itemBuilder: (context, index) {
        var data = docs[index].data() as Map<String, dynamic>;
        bool isSettled = data['isSettled'] ?? false;
        bool isDelivered = data['deliveryTaskStatus'] == 'delivered';
        
        // معالجة الـ Null في السعر داخل القائمة
        String price = "0";
        if (data['netTotal'] != null) price = data['netTotal'].toString();
        else if (data['total'] != null) price = data['total'].toString();

        return Card(
          elevation: 0,
          margin: const EdgeInsets.symmetric(vertical: 6),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade200)),
          child: ListTile(
            leading: Icon(isDelivered ? Icons.check_circle : Icons.error, color: isDelivered ? Colors.green : Colors.red),
            title: Text("طلب #${docs[index].id.substring(0, 6)}", style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(isSettled ? "تم التوريد ✅" : "عهدة مع المندوب ⏳"),
            trailing: Text("$price ج.م", style: const TextStyle(fontWeight: FontWeight.w900)),
          ),
        );
      },
    );
  }

  Widget _buildDateFilter() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        "نطاق التقرير: ${DateFormat('dd/MM').format(startDate)} - ${DateFormat('dd/MM').format(endDate)}",
        style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold),
      ),
    );
  }
}

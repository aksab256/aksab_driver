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
  DateTime startDate = DateTime.now().subtract(const Duration(hours: 48));
  DateTime endDate = DateTime.now();

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
          
          double totalInHand = 0;    
          double totalSettled = 0;   
          int pendingTasks = 0;      

          for (var doc in allDocs) {
            final data = doc.data() as Map<String, dynamic>;
            double amount = (data['netTotal'] ?? data['total'] ?? 0.0).toDouble();

            if (data['deliveryTaskStatus'] == 'pending') {
              pendingTasks++;
            } else {
              Timestamp? ts = data['completedAt'] as Timestamp?;
              if (ts != null) {
                DateTime date = ts.toDate();
                if (date.isAfter(startDate) && date.isBefore(endDate.add(const Duration(days: 1)))) {
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
              Text("سجل عمليات العهدة (التفاصيل)", 
                style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.bold)),
              const Divider(),

              _buildDetailedList(allDocs),
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
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 20.sp),
            SizedBox(height: 5.sp),
            Text(title, style: TextStyle(fontSize: 10.sp, color: Colors.grey[600])),
            Text("${amount.toStringAsFixed(1)} ج.م", 
              style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w900, color: color)),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBanner(int pending) {
    bool isWorking = pending > 0;
    return Container(
      padding: EdgeInsets.all(12.sp),
      decoration: BoxDecoration(
        color: isWorking ? Colors.amber[50] : Colors.green[50],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(isWorking ? Icons.hourglass_top : Icons.check_circle, 
              color: isWorking ? Colors.orange[800] : Colors.green[800], size: 16.sp),
          SizedBox(width: 10.sp),
          Text(
            isWorking ? "متبقي $pending مهمة قيد التوصيل" : "تم إنهاء كافة المهام بنجاح",
            style: TextStyle(fontSize: 11.sp, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailedList(List<QueryDocumentSnapshot> docs) {
    var displayDocs = docs.where((d) => d['deliveryTaskStatus'] != 'pending').toList();
    
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: displayDocs.length,
      itemBuilder: (context, index) {
        var data = displayDocs[index].data() as Map<String, dynamic>;
        bool isSettled = data['isSettled'] ?? false;
        bool isDelivered = data['deliveryTaskStatus'] == 'delivered';

        return Card(
          margin: EdgeInsets.symmetric(vertical: 5.sp),
          child: ListTile(
            leading: Icon(isDelivered ? Icons.check_circle : Icons.cancel, 
                        color: isDelivered ? Colors.green : Colors.red),
            title: Text("طلب #${displayDocs[index].id.substring(0,6)}"),
            subtitle: Text(isSettled ? "تم التوريد ✅" : "عهدة مع المندوب ⏳"),
            trailing: Text("${data['netTotal']} ج.م", 
                          style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        );
      },
    );
  }

  Widget _buildDateFilter() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10.sp, vertical: 5.sp),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text("نطاق التقرير:", style: TextStyle(fontSize: 10.sp, fontWeight: FontWeight.bold)),
          Text("${DateFormat('dd/MM').format(startDate)} - ${DateFormat('dd/MM').format(endDate)}"),
        ],
      ),
    );
  }
}

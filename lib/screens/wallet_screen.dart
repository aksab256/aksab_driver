import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:sizer/sizer.dart';
import 'package:url_launcher/url_launcher.dart';

class WalletScreen extends StatelessWidget {
  const WalletScreen({super.key});

  double _toDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is int) return value.toDouble();
    if (value is double) return value;
    return 0.0;
  }

  // --- 💸 1. طلب شحن نقاط الأمان ---
  Future<void> _processCharge(BuildContext context, double amount) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    _showLoading(context);
    try {
      await FirebaseFirestore.instance.collection('pendingInvoices').add({
        'driverId': uid,
        'amount': amount,
        'status': 'pay_now',
        'type': 'OPERATIONAL_FEES',
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (context.mounted) Navigator.pop(context);
      _showInfoSheet(context, "تم استلام طلبك", "جاري تجهيز رابط سداد آمن لتعبئة (نقاط الأمان)، ستظهر في سجل العمليات فور جاهزيتها.");
    } catch (e) {
      if (context.mounted) Navigator.pop(context);
      _showInfoSheet(context, "خطأ", "فشل الاتصال بالخادم، يرجى المحاولة لاحقاً.");
    }
  }

  // --- 💰 2. طلب تسوية أرباح مطور (إرسال الحقول الجديدة) ---
  Future<void> _executeWithdrawal(BuildContext context, double amount, String name, String phone, String method, String account) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    _showLoading(context);
    try {
      await FirebaseFirestore.instance.collection('withdrawRequests').add({
        'driverId': uid,
        'driverName': name,
        'driverPhone': phone,
        'amount': amount,
        'methodType': method,
        'accountNumber': account,
        'status': 'pending',
        'type': 'EARNINGS_SETTLEMENT',
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (context.mounted) {
        Navigator.pop(context);
        _showInfoSheet(context, "طلب التسوية قيد المراجعة", "تم إرسال بيانات التحويل للإدارة. سيتم مراجعة سجل العهدة وتحويل المبلغ خلال 24 ساعة.");
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context);
        _showInfoSheet(context, "خطأ", "فشل إرسال الطلب، حاول مجدداً.");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: () => Navigator.of(context).canPop() ? Navigator.of(context).pop() : Navigator.of(context).pushReplacementNamed('/free_home'),
        ),
        title: const Text("إدارة العهدة ونقاط الأمان", style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Cairo', fontSize: 18)),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black,
      ),
      body: SafeArea(
        child: StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance.collection('freeDrivers').doc(uid).snapshots(),
          builder: (context, driverSnap) {
            if (!driverSnap.hasData) return const Center(child: CircularProgressIndicator(color: Colors.orange));
            var userData = driverSnap.data!.data() as Map<String, dynamic>?;
            
            double walletBalance = _toDouble(userData?['walletBalance']);
            double creditLimit = _toDouble(userData?['creditLimit']);
            double lockedInsurance = _toDouble(userData?['insurance_points']);
            String driverName = userData?['fullName'] ?? "مندوب اكسب";
            String driverPhone = userData?['phone'] ?? "";

            return SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child: Column(
                children: [
                  _buildMainAssetCard(walletBalance, creditLimit, lockedInsurance),
                  
                  // شريط إجمالي الأمانات
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 10),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(color: Colors.blueGrey[50], borderRadius: BorderRadius.circular(20)),
                    child: Text("إجمالي الأمانات بالذمة: ${(walletBalance + lockedInsurance).toStringAsFixed(2)} ج.م",
                        style: TextStyle(fontSize: 11.sp, fontWeight: FontWeight.bold, fontFamily: 'Cairo', color: Colors.blueGrey[800])),
                  ),

                  // أزرار العمليات
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    child: Row(
                      children: [
                        Expanded(child: _actionBtn(Icons.add_moderator_outlined, "تعبئة نقاط", Colors.green[700]!, () => _showChargePicker(context))),
                        const SizedBox(width: 15),
                        Expanded(child: _actionBtn(Icons.account_balance_outlined, "طلب تسوية", Colors.blueGrey[800]!, () => _showWithdrawDialog(context, walletBalance, driverName, driverPhone))),
                      ],
                    ),
                  ),

                  // ✅ جزء جديد: طلبات السحب تحت المراجعة (فلترة داخلية)
                  _buildPendingWithdrawalsSection(uid),

                  _sectionHeader("سجل تأمين العهدة والعمليات"),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _buildCombinedHistory(uid),
                  ),
                  _buildLegalDisclaimer(),
                  const SizedBox(height: 40),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  // --- فلترة الطلبات المعلقة يدوياً بدون إندكس ---
  Widget _buildPendingWithdrawalsSection(String? uid) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('withdrawRequests').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox();
        
        // فلترة الطلبات الخاصة بهذا المندوب وحالتها pending يدوياً
        final pendingRequests = snapshot.data!.docs.where((doc) {
          var d = doc.data() as Map<String, dynamic>;
          return d['driverId'] == uid && d['status'] == 'pending';
        }).toList();

        if (pendingRequests.isEmpty) return const SizedBox();

        return Column(
          children: [
            _sectionHeader("طلبات قيد المراجعة ⏳"),
            ...pendingRequests.map((doc) {
              var d = doc.data() as Map<String, dynamic>;
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: Colors.orange.withOpacity(0.3))
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text("طلب سحب أرباح", style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 12.sp)),
                      Text("وسيلة التحويل: ${d['methodType']}", style: const TextStyle(fontFamily: 'Cairo', fontSize: 10, color: Colors.blueGrey)),
                    ]),
                    Text("${d['amount']} ج.م", style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w900, fontSize: 14.sp, color: Colors.orange[900])),
                  ],
                ),
              );
            }).toList(),
          ],
        );
      },
    );
  }

  // --- كارت الأرصدة الرئيسي ---
  Widget _buildMainAssetCard(double available, double limit, double locked) => Container(
      margin: const EdgeInsets.all(20),
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFF1A1C1E), Color(0xFF373B3E)], begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(30),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 15, offset: const Offset(0, 8))]),
      child: Column(children: [
        const Text("نقاط الأمان المتاحة", style: TextStyle(color: Colors.white70, fontFamily: 'Cairo', fontSize: 14)),
        const SizedBox(height: 10),
        Text(available.toStringAsFixed(2), style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w900)),
        const Padding(padding: EdgeInsets.symmetric(vertical: 20), child: Divider(color: Colors.white24, height: 1, thickness: 1)),
        Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
          _miniInfo("تأمين عهدة", locked.toStringAsFixed(1), Colors.orangeAccent),
          _miniInfo("سقف المديونية", limit.toStringAsFixed(1), Colors.cyanAccent),
        ])
      ]),
    );

  Widget _miniInfo(String label, String value, Color valColor) => Column(children: [
        Text(label, style: const TextStyle(color: Colors.white60, fontSize: 11, fontFamily: 'Cairo')),
        const SizedBox(height: 5),
        Text(value, style: TextStyle(color: valColor, fontWeight: FontWeight.w900, fontSize: 18)),
      ]);

  // --- ديالوج سحب الأرباح المطور ---
  void _showWithdrawDialog(BuildContext context, double current, String name, String phone) {
    final amountCtrl = TextEditingController();
    final accountCtrl = TextEditingController();
    String selectedMethod = 'فودافون كاش';

    showDialog(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
          title: const Text("طلب تسوية رصيد", style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text("المتاح: ${current.toStringAsFixed(2)} ج.م", style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
              const SizedBox(height: 20),
              TextField(
                controller: amountCtrl,
                keyboardType: TextInputType.number,
                decoration: _inputStyle("المبلغ المراد سحبه"),
              ),
              const SizedBox(height: 15),
              DropdownButtonFormField<String>(
                value: selectedMethod,
                decoration: _inputStyle("وسيلة التحويل"),
                items: ['فودافون كاش', 'انستا باي', 'تحويل بنكي'].map((m) => DropdownMenuItem(value: m, child: Text(m, style: const TextStyle(fontFamily: 'Cairo')))).toList(),
                onChanged: (val) => setState(() => selectedMethod = val!),
              ),
              const SizedBox(height: 15),
              TextField(
                controller: accountCtrl,
                keyboardType: TextInputType.text,
                decoration: _inputStyle("رقم الحساب / المحفظة / العنوان"),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("إلغاء", style: TextStyle(color: Colors.red, fontFamily: 'Cairo'))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey[800], shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              onPressed: () {
                double? amt = double.tryParse(amountCtrl.text);
                if (amt != null && amt > 0 && amt <= current && accountCtrl.text.isNotEmpty) {
                  Navigator.pop(context);
                  _executeWithdrawal(context, amt, name, phone, selectedMethod, accountCtrl.text);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("برجاء التأكد من المبلغ وصحة البيانات")));
                }
              },
              child: const Text("تأكيد الطلب", style: TextStyle(color: Colors.white, fontFamily: 'Cairo')),
            )
          ],
        ),
      ),
    );
  }

  InputDecoration _inputStyle(String hint) => InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(fontSize: 12, fontFamily: 'Cairo'),
      filled: true,
      fillColor: Colors.grey[100],
      contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none));

  // --- بقية الدوال المساعدة (History, Disclaimer, etc) ---
  Widget _buildCombinedHistory(String? uid) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('pendingInvoices').where('driverId', isEqualTo: uid).where('status', isEqualTo: 'ready_for_payment').snapshots(),
      builder: (context, pendingSnap) {
        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('walletLogs').where('driverId', isEqualTo: uid).orderBy('timestamp', descending: true).limit(15).snapshots(),
          builder: (context, logSnap) {
            List<Map<String, dynamic>> allItems = [];
            DateTime now = DateTime.now();
            if (pendingSnap.hasData) {
              for (var doc in pendingSnap.data!.docs) {
                var d = doc.data() as Map<String, dynamic>;
                if (d['createdAt'] != null) {
                  DateTime createdAt = (d['createdAt'] as Timestamp).toDate();
                  if (now.difference(createdAt).inHours < 6) {
                    d['isInvoice'] = true;
                    allItems.add(d);
                  }
                }
              }
            }
            if (logSnap.hasData) {
              for (var doc in logSnap.data!.docs) {
                var d = doc.data() as Map<String, dynamic>;
                d['isInvoice'] = false;
                allItems.add(d);
              }
            }
            if (allItems.isEmpty) return Container(height: 100, alignment: Alignment.center, child: Text("السجل فارغ", style: TextStyle(fontFamily: 'Cairo', color: Colors.grey[400])));
            return ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: allItems.length,
              itemBuilder: (context, index) {
                var item = allItems[index];
                bool isInvoice = item['isInvoice'] ?? false;
                double amount = _toDouble(item['amount']);
                return Card(
                  elevation: 0, margin: const EdgeInsets.only(bottom: 8),
                  shape: RoundedRectangleBorder(
  borderRadius: BorderRadius.circular(12),
  side: BorderSide(color: Colors.grey[100]!, width: 1), // التعديل الصحيح
),

                  child: ListTile(
                    leading: Icon(isInvoice ? Icons.payment : Icons.history, color: isInvoice ? Colors.orange : Colors.blueGrey),
                    title: Text(isInvoice ? "رابط شحن متاح" : _getLogTitle(item['type'], amount), style: const TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.bold)),
                    trailing: Text("${amount > 0 ? '+' : ''}$amount", style: TextStyle(color: amount > 0 ? Colors.green : Colors.red, fontWeight: FontWeight.bold)),
                    onTap: isInvoice ? () => _launchPaymentUrl(item['paymentUrl']) : null,
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  String _getLogTitle(String? type, double amount) {
    if (type == 'ORDER_REVENUE') return "تسوية أرباح شحنة";
    if (type == 'insurance_lock') return "حجز تأمين عهدة";
    if (type == 'operational_fee') return "شحن نقاط أمان";
    return amount > 0 ? "إيداع نقاط" : "تخصيص عهدة";
  }

  Widget _actionBtn(IconData icon, String label, Color color, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 20),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.grey[200]!), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10)]),
          child: Column(children: [Icon(icon, color: color, size: 24.sp), const SizedBox(height: 8), Text(label, style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w900, fontSize: 12))]),
        ),
      );

  Widget _sectionHeader(String title) => Padding(padding: const EdgeInsets.fromLTRB(20, 25, 20, 15), child: Align(alignment: Alignment.centerRight, child: Text(title, style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w900, fontSize: 16))));

  Widget _buildLegalDisclaimer() => Padding(padding: const EdgeInsets.all(20), child: Text("إدارة العهدة: يتم تخصيص نقاط أمان تعادل قيمة الشحنة لضمان النقل الآمن، وتُعاد فور تأكيد الاستلام.", textAlign: TextAlign.center, style: TextStyle(fontFamily: 'Cairo', fontSize: 9.sp, color: Colors.grey)));

  void _showLoading(BuildContext context) => showDialog(context: context, barrierDismissible: false, builder: (c) => const Center(child: CircularProgressIndicator(color: Colors.orange)));

  void _showInfoSheet(BuildContext context, String t, String m) => showModalBottomSheet(context: context, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(30))), builder: (c) => Padding(padding: const EdgeInsets.all(30), child: Column(mainAxisSize: MainAxisSize.min, children: [Text(t, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, fontFamily: 'Cairo')), const SizedBox(height: 10), Text(m, textAlign: TextAlign.center, style: const TextStyle(fontFamily: 'Cairo', color: Colors.grey)), const SizedBox(height: 20), SizedBox(width: double.infinity, child: ElevatedButton(onPressed: () => Navigator.pop(context), child: const Text("فهمت")))])));

  void _launchPaymentUrl(String? url) async { if (url != null) await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication); }

  void _showChargePicker(BuildContext context) {
    showModalBottomSheet(context: context, builder: (c) => Container(padding: const EdgeInsets.all(25), child: Column(mainAxisSize: MainAxisSize.min, children: [const Text("تعبئة نقاط الأمان", style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)), const SizedBox(height: 20), Wrap(spacing: 10, children: [100, 200, 500].map((a) => ActionChip(label: Text("$a"), onPressed: () { Navigator.pop(context); _processCharge(context, a.toDouble()); })).toList())])));
  }
}


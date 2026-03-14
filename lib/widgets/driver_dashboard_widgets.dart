import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:sizer/sizer.dart';

// --- 1. الهيدر وزر تبديل الحالة ---
class DashboardHeader extends StatelessWidget {
  final GlobalKey<ScaffoldState> scaffoldKey;
  final String currentStatus;
  final Function(bool) onStatusToggle;

  const DashboardHeader({
    super.key,
    required this.scaffoldKey,
    required this.currentStatus,
    required this.onStatusToggle,
  });

  @override
  Widget build(BuildContext context) {
    bool isActive = (currentStatus == 'online' || currentStatus == 'busy');

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(children: [
              IconButton(
                icon: const Icon(Icons.menu_rounded, size: 32),
                onPressed: () => scaffoldKey.currentState?.openDrawer(),
              ),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("أهلاً بك 👋", style: TextStyle(fontSize: 12, color: Colors.grey, fontFamily: 'Cairo')),
                  Text("كابتن أكسب", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, fontFamily: 'Cairo'))
                ],
              )
            ]),
            // زر تبديل الحالة (متصل / أوفلاين)
            GestureDetector(
              onTap: () => onStatusToggle(!isActive),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
                decoration: BoxDecoration(
                  color: isActive ? Colors.green[600] : Colors.red[600],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(children: [
                  Icon(isActive ? Icons.flash_on : Icons.flash_off, color: Colors.white, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    isActive ? "متصل" : "أوفلاين",
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
                  )
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- 2. بانر العهدة النشطة ---
class ActiveOrderBanner extends StatelessWidget {
  final VoidCallback onTap;
  const ActiveOrderBanner({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: Colors.orange[900],
            borderRadius: BorderRadius.circular(15),
          ),
          child: const Row(children: [
            Icon(Icons.delivery_dining, color: Colors.white),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                "لديك عهدة نشطة، اضغط للمتابعة",
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
              ),
            ),
            Icon(Icons.arrow_forward_ios, color: Colors.white, size: 14)
          ]),
        ),
      ),
    );
  }
}

// --- 3. شبكة الإحصائيات الحية ---
class LiveStatsGrid extends StatelessWidget {
  final String uid;
  const LiveStatsGrid({super.key, required this.uid});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('freeDrivers').doc(uid).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || !snapshot.data!.exists) {
          return const SliverToBoxAdapter(child: Center(child: CircularProgressIndicator()));
        }
        var data = snapshot.data!.data() as Map<String, dynamic>;

        return SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 15,
              mainAxisSpacing: 15,
              childAspectRatio: 1.1,
            ),
            delegate: SliverChildListDelegate([
              _StatCard("نقاط التأمين", "${data['insurance_points'] ?? 0}", Icons.security, Colors.blue),
              _StatCard("أمانات مُسلمة اليوم", "${data['completed_today'] ?? 0}", Icons.task_alt, Colors.orange),
              _StatCard("التقييم المهني", _calculateRating(data), Icons.star_border_rounded, Colors.amber),
              _StatCard("المحفظة (ج.م)", "${(data['walletBalance'] ?? 0.0).toStringAsFixed(2)}", Icons.account_balance_wallet_outlined, Colors.green),
            ]),
          ),
        );
      },
    );
  }

  String _calculateRating(Map<String, dynamic> data) {
    double totalStars = (data['totalStars'] ?? 0.0).toDouble();
    int reviewsCount = data['reviewsCount'] ?? 0;
    if (reviewsCount == 0) return "5.0";
    return (totalStars / reviewsCount).toStringAsFixed(1);
  }
}

// --- 4. تصميم الكارت الصغير للإحصائيات ---
class _StatCard extends StatelessWidget {
  final String title, value;
  final IconData icon;
  final Color color;

  const _StatCard(this.title, this.value, this.icon, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: color, size: 24),
          ),
          const Spacer(),
          Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          Text(title, style: const TextStyle(color: Colors.grey, fontFamily: 'Cairo', fontSize: 10)),
        ],
      ),
    );
  }
}


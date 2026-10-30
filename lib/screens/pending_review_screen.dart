import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:sizer/sizer.dart';

/// Shown when a signed-in account exists but is NOT approved yet
/// (e.g. status == 'pending'), instead of silently bouncing to login.
/// Used both on first sign-in and on every app reopen (AuthWrapper).
class PendingReviewScreen extends StatelessWidget {
  final String userType;
  final String status;

  const PendingReviewScreen({
    super.key,
    required this.userType,
    required this.status,
  });

  String get _typeLabel {
    switch (userType) {
      case 'deliveryRep':
        return 'مندوب شركة';
      case 'freeDriver':
        return 'مندوب حر';
      default:
        return 'حساب';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 8.w),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.hourglass_top_rounded,
                  size: 70.sp, color: Colors.orange[800]),
              SizedBox(height: 3.h),
              Text(
                'حسابك قيد المراجعة',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 22.sp,
                  fontWeight: FontWeight.w900,
                ),
              ),
              SizedBox(height: 1.5.h),
              Text(
                'طلب انضمامك كـ$_typeLabel مسجل لدينا وحالته الحالية: "$status". '
                'سيتم تفعيل حسابك خلال 24 ساعة، وستصلك صلاحية الدخول فور الموافقة.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 13.5.sp,
                  color: Colors.grey[700],
                ),
              ),
              SizedBox(height: 4.h),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black87,
                    padding: EdgeInsets.symmetric(vertical: 2.h),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: () async {
                    await FirebaseAuth.instance.signOut();
                    if (context.mounted) {
                      Navigator.pushReplacementNamed(context, '/login');
                    }
                  },
                  child: Text(
                    'تسجيل الخروج',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      color: Colors.white,
                      fontSize: 15.sp,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

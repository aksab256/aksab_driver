import 'package:flutter/material.dart';
import 'package:sizer/sizer.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ProfileScreen extends StatefulWidget {
  final Map<String, dynamic>? repData;
  const ProfileScreen({super.key, this.repData});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _isDeleting = false;

  // دالة حذف الحساب
  Future<void> _deleteAccount() async {
    bool confirm = await _showDeleteConfirmation();
    if (confirm) {
      setState(() => _isDeleting = true);
      try {
        final user = FirebaseAuth.instance.currentUser;
        final String uid = user?.uid ?? "";

        // 1. حذف البيانات من Firestore أولاً
        await FirebaseFirestore.instance.collection('deliveryReps').doc(uid).delete();
        
        // 2. حذف الحساب من Firebase Authentication
        await user?.delete();

        if (mounted) {
          Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
          _showSnackBar("تم حذف الحساب نهائياً بنجاح");
        }
      } on FirebaseAuthException catch (e) {
        if (e.code == 'requires-recent-login') {
          _showSnackBar("يرجى تسجيل الخروج والدخول مرة أخرى لإتمام هذه العملية الحساسة");
        } else {
          _showSnackBar("خطأ: ${e.message}");
        }
      } finally {
        if (mounted) setState(() => _isDeleting = false);
      }
    }
  }

  Future<bool> _showDeleteConfirmation() async {
    return await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("حذف الحساب نهائياً؟", textAlign: TextAlign.right),
        content: const Text("هل أنت متأكد؟ سيؤدي هذا الإجراء إلى حذف كافة بياناتك ولا يمكن التراجع عنه.", textAlign: TextAlign.right),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("إلغاء")),
          TextButton(
            onPressed: () => Navigator.pop(context, true), 
            child: const Text("نعم، احذف الحساب", style: TextStyle(color: Colors.red))
          ),
        ],
      ),
    ) ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.repData ?? {};
    return Scaffold(
      appBar: AppBar(
        title: const Text("ملفي الشخصي"),
        backgroundColor: const Color(0xFF2C3E50),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(20.sp),
        child: Column(
          children: [
            const CircleAvatar(
              radius: 50,
              backgroundColor: Color(0xFF3498DB),
              child: Icon(Icons.person, size: 60, color: Colors.white),
            ),
            SizedBox(height: 15.sp),
            Text(data['fullname'] ?? "اسم المندوب", style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold)),
            Text("كود الموظف: ${data['repCode'] ?? '---'}", style: TextStyle(color: Colors.grey[600])),
            const Divider(height: 40),
            
            _buildInfoTile(Icons.email, "البريد الإلكتروني", data['email'] ?? "---"),
            _buildInfoTile(Icons.phone, "رقم الهاتف", data['phone'] ?? "---"),
            
            SizedBox(height: 10.h),
            
            _isDeleting 
            ? const CircularProgressIndicator(color: Colors.red)
            : SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _deleteAccount,
                  icon: const Icon(Icons.delete_forever),
                  label: const Text("حذف الحساب نهائياً"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red[50],
                    foregroundColor: Colors.red,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    side: const BorderSide(color: Colors.red),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                  ),
                ),
              ),
            SizedBox(height: 15.sp),
            const Text(
              "عند طلب حذف الحساب، سيتم إزالة كافة بياناتك الشخصية من سيرفراتنا فوراً.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 10),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildInfoTile(IconData icon, String title, String value) {
    return ListTile(
      leading: Icon(icon, color: const Color(0xFF2C3E50)),
      title: Text(title, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      subtitle: Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.black87)),
    );
  }

  void _showSnackBar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}

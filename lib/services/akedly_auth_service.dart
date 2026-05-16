// lib/services/akedly_auth_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart'; // للعمليات الحسابية وحل التحدي محلياً

class AkedlyAuthService {
  // المفاتيح والمعرفات الثابتة الخاصة بخط الإنتاج لمنظومة رابية أحلى
  final String _apiKey = "f032dc4687c452cb7c340a91df69ed419e6a5330c3bb9b2f826828bf381e3624";
  final String _pipelineId = "6a02edb9dc826dd83e860ad1";

  // دالة حل التحدي يدوياً (Proof of Work) لمنع السبام والـ Bots
  int _solveChallenge(String challenge, int difficulty) {
    int nonce = 0;
    String target = '0' * difficulty;
    while (true) {
      String input = "$challenge:$nonce";
      String hash = sha256.convert(utf8.encode(input)).toString();
      if (hash.startsWith(target)) {
        return nonce;
      }
      nonce++;
    }
  }

  // دالة إرسال كود التفعيل المكونة من 3 خطوات مترابطة
  Future<AuthResult> sendOtpDetailed(String phoneNumber) async {
    try {
      // الخطوة 1: طلب التحدي من خوادم أكيدلي لضمان أمان العملية
      final challengeRes = await http.get(
        Uri.parse('https://api.akedly.io/api/v1.2/transactions/challenge?APIKey=$_apiKey&pipelineID=$_pipelineId'),
      );
      
      if (challengeRes.statusCode != 200) {
        return AuthResult.failure(message: 'فشل في الاتصال الأولي بخادم التحقق');
      }

      final challengeData = jsonDecode(challengeRes.body)['data'];
      
      // الخطوة 2: حل التحدي حسابياً محلياً على جهاز المندوب لإنتاج الـ nonce
      final nonce = _solveChallenge(
        challengeData['challenge'], 
        challengeData['difficulty']
      );

      // الخطوة 3: إرسال الـ OTP الفعلي إلى رقم هاتف المندوب
      final response = await http.post(
        Uri.parse('https://api.akedly.io/api/v1.2/transactions/send'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'APIKey': _apiKey,
          'pipelineID': _pipelineId,
          'verificationAddress': {'phoneNumber': phoneNumber},
          'powSolution': {
            'challengeToken': challengeData['challengeToken'],
            'nonce': nonce,
          },
        }),
      );

      final resData = jsonDecode(response.body);
      if (response.statusCode == 200) {
        // نرجع بمعرف العملية الناجحة (transactionReqID) لاستخدامه في دالة التأكيد
        return AuthResult.success(data: resData['data']['transactionReqID']);
      } else {
        return AuthResult.failure(message: resData['message'] ?? 'فشل إرسال كود التفعيل');
      }
    } catch (e) {
      return AuthResult.failure(message: 'خطأ تقني في شبكة الاتصال: $e');
    }
  }

  // دالة مطابقة الكود المدخل بواسطة المندوب مع السيرفر
  Future<bool> verifyOtp(String transactionReqID, String otp) async {
    try {
      final response = await http.post(
        Uri.parse('https://api.akedly.io/api/v1.2/transactions/verify'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'transactionReqID': transactionReqID, 
          'otp': otp
        }),
      );
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }
}

// كلاس تأطير النتائج وتمريرها لواجهة المستخدم بشكل نظيف وآمن
class AuthResult {
  final bool isSuccess;
  final String? message;
  final String? data;

  AuthResult.success({this.data}) : isSuccess = true, message = null;
  AuthResult.failure({required this.message}) : isSuccess = false, data = null;
}
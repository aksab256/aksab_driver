// lib/services/akedly_auth_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;

// F3: OTP goes through the backend proxy only. No Akedly keys live in the
// client, no direct Akedly calls, no anonymous sessions. Identity comes from
// a server-minted Firebase Custom Token after server-side OTP verification.
class AkedlyAuthService {
  static const String _baseUrl =
      'https://us-central1-aksab-erp.cloudfunctions.net/akedly';

  // إرسال كود التفعيل عبر البروكسي الخلفي (driver flow).
  Future<AuthResult> sendOtpDetailed(String phoneNumber) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/send'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'phoneNumber': phoneNumber, 'flow': 'driver'}),
      );

      final resData =
          response.body.isNotEmpty ? jsonDecode(response.body) : null;
      if (response.statusCode == 200) {
        final data = resData is Map ? resData['data'] : null;
        String? transactionReqID;
        if (data is Map && data['transactionReqID'] != null) {
          transactionReqID = data['transactionReqID'].toString();
        }
        return AuthResult.success(data: transactionReqID ?? '');
      } else {
        String? message;
        if (resData is Map && resData['message'] != null) {
          message = resData['message'].toString();
        }
        return AuthResult.failure(message: message ?? 'فشل إرسال كود التفعيل');
      }
    } catch (e) {
      return AuthResult.failure(message: 'خطأ تقني في شبكة الاتصال: $e');
    }
  }

  /// F3 registration: step 1 — backend OTP-proves an UNKNOWN phone for [role]
  /// (free_driver/delivery_rep/delivery_supervisor/delivery_manager).
  /// Known numbers -> 409; role+collection bound server-side in the tx.
  Future<AuthResult> registerSend(String phoneNumber, String role) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'phoneNumber': phoneNumber, 'role': role}),
      );
      final resData =
          response.body.isNotEmpty ? jsonDecode(response.body) : null;
      if (response.statusCode == 200) {
        final data = resData is Map ? resData['data'] : null;
        String? transactionReqID;
        if (data is Map && data['transactionReqID'] != null) {
          transactionReqID = data['transactionReqID'].toString();
        }
        return AuthResult.success(data: transactionReqID ?? '');
      }
      String? message;
      if (resData is Map && resData['message'] != null) {
        message = resData['message'].toString();
      }
      return AuthResult.failure(message: message ?? 'فشل بدء التسجيل');
    } catch (e) {
      return AuthResult.failure(message: 'خطأ تقني في شبكة الاتصال: $e');
    }
  }

  /// F3 registration: step 2 — server verifies OTP then creates the
  /// passwordless Auth identity + role doc in the bound collection.
  /// Throws [RegisterException] with the backend status (400/403/404/409/410/429).
  Future<RegisterResult> registerVerify({
    required String transactionReqID,
    required String otp,
    required String phoneNumber,
    required Map<String, dynamic> profile,
  }) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/register-verify'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'transactionReqID': transactionReqID,
        'otp': otp,
        'phoneNumber': phoneNumber,
        'profile': profile,
      }),
    );
    if (response.statusCode == 200) {
      final resData =
          response.body.isNotEmpty ? jsonDecode(response.body) : null;
      if (resData is Map && resData['customToken'] is String) {
        return RegisterResult(
          customToken: resData['customToken'] as String,
          role: resData['role']?.toString() ?? '',
          collection: resData['collection']?.toString() ?? '',
          status: resData['status']?.toString() ?? '',
        );
      }
    }
    throw RegisterException(response.statusCode, response.body);
  }

  static const String _settleUrl =
      'https://us-central1-aksab-erp.cloudfunctions.net/settle';
  static const String _handoverUrl =
      'https://us-central1-aksab-erp.cloudfunctions.net/verifyHandover';

  /// Server-side custody-handover proof: the server compares the submitted
  /// code against the creator-bound vault and flips the status atomically.
  /// Returns the new status. Throws [HandoverException] with backend status.
  Future<String> verifyHandover({
    required String orderId,
    required String otp,
    required String idToken,
  }) async {
    final response = await http.post(
      Uri.parse(_handoverUrl),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $idToken',
      },
      body: jsonEncode({'orderId': orderId, 'otp': otp}),
    );
    if (response.statusCode == 200) {
      final resData =
          response.body.isNotEmpty ? jsonDecode(response.body) : null;
      if (resData is Map && resData['status'] is String) {
        return resData['status'] as String;
      }
    }
    throw HandoverException(response.statusCode, response.body);
  }

  /// Settlement with a server-side cap: the server recomputes the owed total
  /// from the rep's delivered tasks (orders truth) and rejects any received
  /// amount above it. Less-than-owed is allowed (shortage goes to review).
  /// Throws [SettleException] carrying the backend status code.
  Future<SettleResult> settleDelivery({
    required double received,
    required String idToken,
  }) async {
    final response = await http.post(
      Uri.parse(_settleUrl),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $idToken',
      },
      body: jsonEncode({'received': received}),
    );
    if (response.statusCode == 200) {
      final resData =
          response.body.isNotEmpty ? jsonDecode(response.body) : null;
      if (resData is Map) {
        return SettleResult(
          settlementId: resData['settlementId']?.toString() ?? '',
          expected: (resData['expected'] as num?)?.toDouble() ?? 0,
          received: (resData['received'] as num?)?.toDouble() ?? 0,
          count: (resData['count'] as num?)?.toInt() ?? 0,
        );
      }
    }
    throw SettleException(response.statusCode, response.body);
  }

  /// F3: backend-mediated mint — server verifies OTP and issues a Firebase
  /// Custom Token. Returns the token, or throws [MintException] with the
  /// backend status code (400 wrong code, 403 pending, 404 unknown,
  /// 410 expired/used, 429 rate-limited).
  Future<String> mintTransaction({
    required String transactionReqID,
    required String otp,
  }) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/mint'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'transactionReqID': transactionReqID, 'otp': otp}),
    );
    if (response.statusCode == 200) {
      final resData =
          response.body.isNotEmpty ? jsonDecode(response.body) : null;
      final token = resData is Map ? resData['customToken'] : null;
      if (token is String && token.isNotEmpty) return token;
    }
    throw MintException(response.statusCode, response.body);
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

/// F3: mint failure carrying the backend status code for UI mapping.
class MintException implements Exception {
  final int statusCode;
  final String body;
  MintException(this.statusCode, this.body);
}

/// Settlement failure carrying the backend status code for UI mapping
/// (400 over-cap/invalid, 401 unauthenticated, 403 no settlement account,
/// 409 tasks changed mid-settlement, 429 rate-limited).
class SettleException implements Exception {
  final int statusCode;
  final String body;
  SettleException(this.statusCode, this.body);
}

/// Handover-proof failure carrying the backend status code for UI mapping
/// (400 wrong code, 401 unauthenticated, 403 not the assigned driver,
/// 409 wrong state/changed mid-verify, 429 rate-limited).
class HandoverException implements Exception {
  final int statusCode;
  final String body;
  HandoverException(this.statusCode, this.body);
}

/// Server-side settlement result: expected is recomputed server-side from
/// the rep's delivered tasks; received is the entered actual amount.
class SettleResult {
  final String settlementId;
  final double expected;
  final double received;
  final int count;
  SettleResult({
    required this.settlementId,
    required this.expected,
    required this.received,
    required this.count,
  });
}

/// F3 registration failure carrying the backend status code for UI mapping.
class RegisterException implements Exception {
  final int statusCode;
  final String body;
  RegisterException(this.statusCode, this.body);
}

/// F3 registration success — identity created server-side in [collection]
/// with [status] (pending = admin review before login).
class RegisterResult {
  final String customToken;
  final String role;
  final String collection;
  final String status;
  RegisterResult({
    required this.customToken,
    required this.role,
    required this.collection,
    required this.status,
  });
}

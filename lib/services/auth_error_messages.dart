// lib/services/auth_error_messages.dart
//
// Pure, testable Arabic user-facing messages for backend auth/handover
// failures. Maps HTTP status codes only — never echoes server bodies,
// tokens, or internal details to the UI.

class AuthErrorMessages {
  AuthErrorMessages._();

  /// User-facing message for POST /akedly/mint failures.
  static String mintMessage(int statusCode) {
    switch (statusCode) {
      case 400:
        return 'رمز التحقق غير صحيح، يرجى المحاولة مرة أخرى';
      case 403:
        return 'هذا الحساب قيد المراجعة أو غير مفعل حالياً';
      case 404:
        return 'هذا الرقم غير مسجل، يرجى تقديم طلب انضمام أولاً';
      case 409:
        return 'تم استخدام هذا الكود من قبل، اطلب كوداً جديداً';
      case 410:
        return 'انتهت صلاحية الكود، اطلب كوداً جديداً وحاول مجدداً';
      case 429:
        return 'محاولات كثيرة في وقت قصير، انتظر قليلاً ثم حاول مجدداً';
      default:
        return 'تعذر تأكيد رمز التحقق، حاول مجدداً';
    }
  }

  /// User-facing message for POST /akedly/register-verify failures.
  static String registerMessage(int statusCode) {
    switch (statusCode) {
      case 400:
        return 'بيانات التسجيل غير مكتملة، راجع الحقول وحاول مجدداً';
      case 403:
        return 'غير مصرح بإتمام هذا التسجيل حالياً';
      case 404:
        return 'انتهت صلاحية الجلسة، أعد بدء التسجيل';
      case 409:
        return 'هذا الرقم مسجل مسبقاً، سجل الدخول';
      case 410:
        return 'انتهت صلاحية الكود، أعد بدء التسجيل';
      case 429:
        return 'محاولات كثيرة في وقت قصير، انتظر قليلاً ثم حاول مجدداً';
      default:
        return 'تعذر إتمام التسجيل، حاول مجدداً';
    }
  }

  /// User-facing message for POST /verifyHandover failures.
  /// Never includes the raw server body.
  static String handoverMessage(int statusCode) {
    switch (statusCode) {
      case 400:
        return 'كود التحقق غير صحيح، تحقق من الكود وحاول مجدداً';
      case 401:
        return 'انتهت الجلسة، سجل الدخول مجدداً وحاول';
      case 403:
        return 'غير مصرح لك بتأكيد هذا الطلب';
      case 404:
        return 'الطلب غير موجود أو تم إغلاقه';
      case 409:
        return 'تغيرت حالة الطلب، حدّث الصفحة وحاول مجدداً';
      case 429:
        return 'محاولات كثيرة في وقت قصير، انتظر قليلاً ثم حاول مجدداً';
      default:
        return 'تعذر التأكيد، حاول مجدداً';
    }
  }
}

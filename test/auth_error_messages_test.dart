import 'package:flutter_test/flutter_test.dart';
import 'package:aksab_driver/services/auth_error_messages.dart';

void main() {
  group('mintMessage', () {
    test('distinguishes real /mint response codes', () {
      expect(AuthErrorMessages.mintMessage(400), contains('رمز التحقق'));
      expect(AuthErrorMessages.mintMessage(403), contains('المراجعة'));
      expect(AuthErrorMessages.mintMessage(404), contains('غير مسجل'));
      expect(AuthErrorMessages.mintMessage(409), contains('من قبل'));
      expect(AuthErrorMessages.mintMessage(410), contains('صلاحية الكود'));
      expect(AuthErrorMessages.mintMessage(429), contains('محاولات'));
      expect(AuthErrorMessages.mintMessage(500), contains('حاول مجدد'));
    });

    test('never leaks server internals', () {
      for (final code in [400, 403, 404, 409, 410, 429, 500, -1]) {
        final msg = AuthErrorMessages.mintMessage(code);
        expect(msg, isNot(contains('Exception')));
        expect(msg, isNot(contains('statusCode')));
        expect(msg.length, greaterThan(5));
      }
    });
  });

  group('registerMessage', () {
    test('distinguishes real register-verify response codes', () {
      expect(AuthErrorMessages.registerMessage(409), contains('مسجل مسبق'));
      expect(AuthErrorMessages.registerMessage(410), contains('صلاحية الكود'));
      expect(AuthErrorMessages.registerMessage(403), isNot(contains('403')));
      expect(AuthErrorMessages.registerMessage(500), contains('حاول مجدد'));
    });

    test('never echoes the raw status code or body', () {
      for (final code in [400, 403, 404, 409, 410, 429, 500]) {
        final msg = AuthErrorMessages.registerMessage(code);
        expect(msg, isNot(contains('$code')));
      }
    });
  });

  group('handoverMessage', () {
    test('distinguishes handover response codes without raw body', () {
      expect(AuthErrorMessages.handoverMessage(400), contains('الكود'));
      expect(AuthErrorMessages.handoverMessage(409), contains('تغيرت حالة الطلب'));
      expect(AuthErrorMessages.handoverMessage(999), contains('حاول مجدد'));
      for (final code in [400, 401, 403, 404, 409, 429]) {
        expect(AuthErrorMessages.handoverMessage(code), isNot(contains('$code')));
      }
    });

    test('splits 400s by backend code without leaking internals', () {
      String msg(String code) => AuthErrorMessages.handoverMessageFor(
          400, '{"message":"x","code":"$code"}');
      expect(msg('CODE_MISMATCH'), contains('غير صحيح'));
      expect(msg('INVALID_FORMAT'), contains('إنجليزية'));
      expect(msg('VAULT_MISSING'), contains('لا يوجد إثبات'));
      expect(msg('VAULT_UNTRUSTED'), contains('لا يوجد إثبات'));
      expect(msg('CODE_NOT_ISSUED'), contains('لم يصدر'));
      expect(msg('INVALID_ORDER_ID'), contains('غير صالح'));
      // Unknown/garbage bodies fall back to the generic 400 line.
      expect(AuthErrorMessages.handoverMessageFor(400, 'not-json'),
          contains('الكود'));
      expect(AuthErrorMessages.handoverMessageFor(400, '{}'), contains('الكود'));
      for (final code in [
        'VAULT_MISSING',
        'VAULT_UNTRUSTED',
        'CODE_NOT_ISSUED',
        'CODE_MISMATCH',
        'INVALID_FORMAT'
      ]) {
        expect(msg(code), isNot(contains(code)));
        expect(msg(code), isNot(contains('uid')));
      }
    });
  });
}

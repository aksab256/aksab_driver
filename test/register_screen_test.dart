import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sizer/sizer.dart';
import 'package:aksab_driver/screens/register_screen.dart';

// Request-first registration form builds offline: role/vehicle widgets
// render and no OTP dialog exists before submit. Pure widget smoke test.
void main() {
  testWidgets('register screen shows the request form', (tester) async {
    await tester.pumpWidget(
      Sizer(builder: (context, orientation, deviceType) {
        return const MaterialApp(home: RegisterScreen());
      }),
    );
    await tester.pump();
    expect(find.text('إرسال طلب الانضمام'), findsOneWidget);
    expect(find.text('مندوب حر (صاحب مركبة)'), findsOneWidget);
    expect(find.text('كود التفعيل'), findsNothing);
  });
}

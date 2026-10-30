import 'package:flutter_test/flutter_test.dart';
import 'package:aksab_driver/core/app_links.dart';

void main() {
  test('privacy policy uses the single official URL', () {
    expect(AppLinks.privacyPolicy, 'https://aksabtech.com/privacy.html');
    expect(AppLinks.privacyPolicy.startsWith('https://'), isTrue);
  });
}

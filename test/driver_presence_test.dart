import 'package:flutter_test/flutter_test.dart';
import 'package:aksab_driver/services/driver_presence.dart';

void main() {
  group('DriverPresence.displayIsActive', () {
    test('online and busy render as connected', () {
      expect(DriverPresence.displayIsActive('online'), isTrue);
      expect(DriverPresence.displayIsActive('busy'), isTrue);
    });

    test('offline and browsing states render as disconnected', () {
      for (final s in ['offline', 'browsing_radar', '', 'unknown']) {
        expect(DriverPresence.displayIsActive(s), isFalse, reason: s);
      }
    });
  });

  group('DriverPresence.canOpenMissionTab', () {
    test('online drivers may always open the tab', () {
      expect(
        DriverPresence.canOpenMissionTab(
            serverStatus: 'online', activeOrderId: null),
        isTrue,
      );
    });

    test('busy driver WITH an active order may open his mission tab', () {
      expect(
        DriverPresence.canOpenMissionTab(
            serverStatus: 'busy', activeOrderId: 'order1'),
        isTrue,
      );
    });

    test('busy driver WITHOUT an active order is sent back online', () {
      expect(
        DriverPresence.canOpenMissionTab(
            serverStatus: 'busy', activeOrderId: null),
        isFalse,
      );
    });

    test('offline driver without an order is sent back online', () {
      expect(
        DriverPresence.canOpenMissionTab(
            serverStatus: 'offline', activeOrderId: null),
        isFalse,
      );
    });
  });
}

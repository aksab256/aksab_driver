import 'package:flutter_test/flutter_test.dart';
import 'package:aksab_driver/services/driver_tracking_service.dart';

void main() {
  group('TrackingGate.shouldStart', () {
    test('starts only after a confirmed accept and when not already running', () {
      expect(
        TrackingGate.shouldStart(acceptSucceeded: true, alreadyRunning: false),
        isTrue,
      );
    });

    test('never starts on rejected/failed accept', () {
      expect(
        TrackingGate.shouldStart(acceptSucceeded: false, alreadyRunning: false),
        isFalse,
      );
    });

    test('never starts a duplicate instance', () {
      expect(
        TrackingGate.shouldStart(acceptSucceeded: true, alreadyRunning: true),
        isFalse,
      );
    });
  });

  group('TrackingGate.shouldRestore', () {
    test('restores only with server-confirmed active order + permission + idle', () {
      expect(
        TrackingGate.shouldRestore(
          hasActiveOrder: true,
          permissionGranted: true,
          alreadyRunning: false,
        ),
        isTrue,
      );
    });

    test('does not restore without an active order (fresh open / login / list)', () {
      expect(
        TrackingGate.shouldRestore(
          hasActiveOrder: false,
          permissionGranted: true,
          alreadyRunning: false,
        ),
        isFalse,
      );
    });

    test('does not restore when permission denied', () {
      expect(
        TrackingGate.shouldRestore(
          hasActiveOrder: true,
          permissionGranted: false,
          alreadyRunning: false,
        ),
        isFalse,
      );
    });

    test('does not restore a duplicate instance', () {
      expect(
        TrackingGate.shouldRestore(
          hasActiveOrder: true,
          permissionGranted: true,
          alreadyRunning: true,
        ),
        isFalse,
      );
    });
  });

  group('TrackingGate.shouldStop', () {
    test('stops only after server confirmation', () {
      expect(TrackingGate.shouldStop(serverConfirmed: true), isTrue);
      expect(TrackingGate.shouldStop(serverConfirmed: false), isFalse);
    });
  });

  group('TrackingGate.isActiveStatus', () {
    test('accepts the live order lifecycle statuses', () {
      for (final s in [
        'accepted',
        'picked_up',
        'returning_to_seller',
        'returning_to_merchant',
      ]) {
        expect(TrackingGate.isActiveStatus(s), isTrue, reason: s);
      }
    });

    test('rejects terminal and unrelated statuses', () {
      for (final s in [
        'pending',
        'delivered',
        'cancelled_by_user_after_accept',
        'driver_cancelled_reseeking',
        'returned_successfully',
        null,
        '',
      ]) {
        expect(TrackingGate.isActiveStatus(s), isFalse, reason: '$s');
      }
    });
  });
}

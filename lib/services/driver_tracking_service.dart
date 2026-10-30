// lib/services/driver_tracking_service.dart
//
// Single gate for driver location tracking lifecycle.
//
// Contract (highest priority):
// - Tracking starts ONLY after an order accept is confirmed by the server.
//   Opening the app, signing in, or browsing the order list never starts it.
// - While the order is active, tracking follows the current mechanism
//   (foreground stream in the active-order screen + background service when
//   the app is backgrounded, ~10s / 10m, respecting OS permissions).
// - Tracking stops ONLY after the server confirms delivery / return /
//   cancellation — never on button press alone.
// - On app restart / session restore, tracking resumes only if the server
//   still reports an active order for this driver.
// - At most one tracking service instance per driver/order: every start path
//   checks `isRunning()` first; every stop path is idempotent.
// - Permission denial, connectivity loss, write failures, and restarts are
//   handled gracefully (no crash, no silent privilege escalation).

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../screens/location_service_handler.dart';

/// Pure, unit-testable tracking decisions (no platform calls).
class TrackingGate {
  TrackingGate._();

  /// Server statuses that count as "driver has an active order".
  static const Set<String> activeStatuses = {
    'accepted',
    'picked_up',
    'returning_to_seller',
    'returning_to_merchant',
  };

  static bool isActiveStatus(String? status) =>
      status != null && activeStatuses.contains(status);

  /// Start only on confirmed accept and only when not already running.
  static bool shouldStart({
    required bool acceptSucceeded,
    required bool alreadyRunning,
  }) =>
      acceptSucceeded && !alreadyRunning;

  /// Resume on restart only when the server reports an active order,
  /// permission allows it, and no instance is already running.
  static bool shouldRestore({
    required bool hasActiveOrder,
    required bool permissionGranted,
    required bool alreadyRunning,
  }) =>
      hasActiveOrder && permissionGranted && !alreadyRunning;

  /// Permanent stop only after the server confirms completion.
  static bool shouldStop({required bool serverConfirmed}) => serverConfirmed;
}

/// Platform orchestration for the tracking lifecycle.
class DriverTrackingService {
  DriverTrackingService._();

  static const String _kDriverUid = 'driver_uid';
  static const String _kActiveOrderId = 'active_order_id';
  static const String _kArmed = 'tracking_armed';

  /// Records the confirmed active order and (re)configures the background
  /// service WITHOUT starting it. Idempotent — safe to call on every
  /// ActiveOrderScreen init and right after a confirmed accept.
  static Future<void> armForOrder({
    required String uid,
    required String orderId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kDriverUid, uid);
    await prefs.setString(_kActiveOrderId, orderId);
    await prefs.setBool(_kArmed, true);

    final service = FlutterBackgroundService();
    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: false,
        isForegroundMode: true,
        notificationChannelId: 'high_importance_channel',
        initialNotificationTitle: 'أسواق أكسب: إدارة العهدة نشطة 🛡️',
        initialNotificationContent: 'جاري مراقبة المسار لضمان أمان النقل...',
        foregroundServiceNotificationId: 888,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: onStart,
      ),
    );
  }

  /// Starts the background service if (and only if) an order is armed,
  /// location permission is already granted, and no instance is running.
  /// Returns true when tracking is (now) running.
  static Future<bool> startIfArmed() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final bool armed = prefs.getBool(_kArmed) ?? false;
      final String? orderId = prefs.getString(_kActiveOrderId);
      if (!armed || orderId == null || orderId.isEmpty) return false;

      final LocationPermission permission = await Geolocator.checkPermission();
      if (permission != LocationPermission.always &&
          permission != LocationPermission.whileInUse) {
        return false; // Permission denied: stay armed, do not start.
      }

      final service = FlutterBackgroundService();
      if (await service.isRunning()) return true;
      service.startService();
      return true;
    } catch (e) {
      debugPrint('Tracking startIfArmed failed: $e');
      return false;
    }
  }

  /// Temporary stop (e.g. app returned to foreground: the live stream takes
  /// over). Keeps the armed order so background tracking can resume later.
  static Future<void> stopBackgroundKeepArmed() async {
    try {
      final service = FlutterBackgroundService();
      if (await service.isRunning()) {
        service.invoke('stopService');
      }
    } catch (e) {
      debugPrint('Tracking temporary stop failed: $e');
    }
  }

  /// Permanent stop — call ONLY after the server confirms delivery, return,
  /// or cancellation. Clears the armed order. Idempotent.
  static Future<void> stopAfterServerConfirm() async {
    try {
      final service = FlutterBackgroundService();
      if (await service.isRunning()) {
        service.invoke('stopService');
      }
    } catch (e) {
      debugPrint('Tracking stop failed: $e');
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kActiveOrderId);
      await prefs.setBool(_kArmed, false);
    } catch (e) {
      debugPrint('Tracking disarm failed: $e');
    }
  }

  /// Session restore: asks the server whether this driver still has an
  /// active order. If yes → re-arm and start (permission permitting) and
  /// return the order id. If no → make sure nothing is running and disarm.
  /// On network/permission errors the current state is left untouched
  /// (fail-open: never kill tracking or sign out on a transient error).
  static Future<String?> restoreIfActive(String uid) async {
    if (uid.isEmpty) return null;
    try {
      final QuerySnapshot snap = await FirebaseFirestore.instance
          .collection('specialRequests')
          .where('driverId', isEqualTo: uid)
          .where('status', whereIn: TrackingGate.activeStatuses.toList())
          .limit(1)
          .get()
          .timeout(const Duration(seconds: 12));

      if (snap.docs.isEmpty) {
        await stopAfterServerConfirm();
        return null;
      }

      final String orderId = snap.docs.first.id;
      final String? status =
          (snap.docs.first.data() as Map<String, dynamic>)['status']
              as String?;
      if (!TrackingGate.isActiveStatus(status)) {
        await stopAfterServerConfirm();
        return null;
      }

      await armForOrder(uid: uid, orderId: orderId);
      final bool permissionGranted = await _permissionGranted();
      final service = FlutterBackgroundService();
      final bool alreadyRunning = await service.isRunning();
      if (TrackingGate.shouldRestore(
        hasActiveOrder: true,
        permissionGranted: permissionGranted,
        alreadyRunning: alreadyRunning,
      )) {
        service.startService();
      }
      return orderId;
    } catch (e) {
      debugPrint('Tracking restore check failed (state untouched): $e');
      return null;
    }
  }

  static Future<bool> _permissionGranted() async {
    try {
      final LocationPermission permission = await Geolocator.checkPermission();
      return permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse;
    } catch (_) {
      return false;
    }
  }
}

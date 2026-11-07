// Pure, unit-testable driver presence rules for the home shell.
//
// - The status toggle renders ON for both 'online' and 'busy' (busy means
//   carrying custody, not offline).
// - The mission/radar tab opens for online drivers, and for busy drivers
//   that still hold an active order id. An order-less non-online driver is
//   sent back to go online first.
class DriverPresence {
  DriverPresence._();

  static bool displayIsActive(String status) =>
      status == 'online' || status == 'busy';

  static bool canOpenMissionTab({
    required String serverStatus,
    required String? activeOrderId,
  }) =>
      serverStatus == 'online' || activeOrderId != null;
}

import 'package:flutter_test/flutter_test.dart';
import 'package:aksab_driver/services/akedly_auth_service.dart';

// Phase-1 request profile builder: what the driver app sends to
// POST /register-request (pending review, no OTP before approval).
// Pure offline tests — no network, no Firebase, no real accounts.
void main() {
  group('buildRequestProfile', () {
    test('free_driver keeps vehicle and referral for the admin review', () {
      final profile = AkedlyAuthService.buildRequestProfile(
        role: 'free_driver',
        fullname: '  Ahmed  ',
        address: ' Cairo ',
        vehicleConfig: 'motorcycleConfig',
        referredBy: ' REF1 ',
      );
      expect(profile['fullname'], 'Ahmed');
      expect(profile['address'], 'Cairo');
      expect(profile['vehicleConfig'], 'motorcycleConfig');
      expect(profile['referredBy'], 'REF1');
      expect(profile['appliedCampaignId'], 'default_launch');
    });

    test('free_driver without referral omits the field', () {
      final profile = AkedlyAuthService.buildRequestProfile(
        role: 'free_driver',
        fullname: 'Ahmed',
        address: 'Cairo',
        vehicleConfig: 'pickupConfig',
        referredBy: '   ',
      );
      expect(profile['vehicleConfig'], 'pickupConfig');
      expect(profile.containsKey('referredBy'), isFalse);
    });

    test('staff roles send the minimal profile only', () {
      for (final role in [
        'delivery_rep',
        'delivery_supervisor',
        'delivery_manager'
      ]) {
        final profile = AkedlyAuthService.buildRequestProfile(
          role: role,
          fullname: 'Sara',
          address: 'Giza',
          vehicleConfig: 'jumboConfig',
          referredBy: 'REF9',
          appliedCampaignId: 'camp1',
        );
        expect(profile['fullname'], 'Sara');
        expect(profile['appliedCampaignId'], 'camp1');
        expect(profile.containsKey('vehicleConfig'), isFalse);
        expect(profile.containsKey('referredBy'), isFalse);
      }
    });
  });
}

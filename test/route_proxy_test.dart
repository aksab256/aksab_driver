import 'package:flutter_test/flutter_test.dart';
import 'package:aksab_driver/services/route_proxy.dart';

void main() {
  test('proxy endpoint is https and carries no key', () {
    expect(RouteProxy.endpoint.startsWith('https://'), isTrue);
    expect(RouteProxy.endpoint.toLowerCase(), isNot(contains('key')));
    expect(RouteProxy.endpoint.toLowerCase(), isNot(contains('AIza')));
  });

  test('buildRequest keeps the origin/destination contract without secrets', () {
    final body = RouteProxy.buildRequest(
      originLat: 31.2,
      originLng: 29.9,
      destLat: 31.3,
      destLng: 30.0,
    );

    final origin = (body['origin'] as Map)['location'] as Map;
    final dest = (body['destination'] as Map)['location'] as Map;
    expect((origin['latLng'] as Map)['latitude'], 31.2);
    expect((origin['latLng'] as Map)['longitude'], 29.9);
    expect((dest['latLng'] as Map)['latitude'], 31.3);
    expect((dest['latLng'] as Map)['longitude'], 30.0);
    expect(body['travelMode'], 'DRIVE');

    final encoded = body.toString();
    expect(encoded.toLowerCase(), isNot(contains('AIza')));
    expect(encoded.toLowerCase(), isNot(contains('api-key')));
    expect(encoded, isNot(contains('X-Goog')));
  });
}

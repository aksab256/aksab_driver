// lib/services/route_proxy.dart
//
// Routes requests MUST NOT carry a Google API key inside the client.
// The client calls our own backend proxy (authenticated with the driver
// Firebase ID token); the proxy holds the server-side Routes key and
// enforces per-driver authorization. Until the proxy is deployed, callers
// fall back to a straight-line segment so the map keeps working.

class RouteProxy {
  RouteProxy._();

  /// Backend proxy endpoint for Directions/Routes.
  /// TODO(backend): deploy a Cloud Function at this path that verifies the
  /// Firebase ID token, checks the driver owns [orderId]-adjacent work, and
  /// forwards to Google Routes with a server-held restricted key.
  static const String endpoint =
      'https://us-central1-aksab-erp.cloudfunctions.net/routesProxy/computeRoute';

  /// Pure request-body builder (no keys, no secrets).
  static Map<String, dynamic> buildRequest({
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
  }) {
    return {
      'origin': {
        'location': {
          'latLng': {'latitude': originLat, 'longitude': originLng},
        },
      },
      'destination': {
        'location': {
          'latLng': {'latitude': destLat, 'longitude': destLng},
        },
      },
      'travelMode': 'DRIVE',
      'routingPreference': 'TRAFFIC_AWARE',
    };
  }
}

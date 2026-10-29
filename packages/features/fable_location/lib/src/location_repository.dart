import 'package:fable_core/fable_core.dart';

/// Value object only. OS location permission and provider API keys are not
/// accessed or stored by this optional capability.
class FableGeoPoint {
  FableGeoPoint(this.lat, this.lng, {this.accuracyMeters, this.capturedAt}) {
    if (!lat.isFinite || !lng.isFinite || lat < -90 || lat > 90 ||
        lng < -180 || lng > 180 ||
        (accuracyMeters != null && (!accuracyMeters!.isFinite || accuracyMeters! < 0 || accuracyMeters! > 100000))) {
      throw ArgumentError('Invalid geographic point');
    }
  }
  final double lat, lng;
  final double? accuracyMeters;
  final DateTime? capturedAt;
  Map<String, dynamic> toJson() => {
    'lat': lat, 'lng': lng,
    if (accuracyMeters != null) 'accuracyMeters': accuracyMeters,
    if (capturedAt != null) 'capturedAt': capturedAt!.toUtc().toIso8601String(),
  };
}

/// Immutable snapshot of ALL provider fields; UI explicitly selects safe ones.
/// Attribution cannot be missing, because the provider's license may require it.
class FableLocationResponse {
  FableLocationResponse._(this.provider, this.data, this.policy, this.warnings, this.raw);
  final String provider;
  final Object? data;
  final Map<String, dynamic> policy;
  final List<String> warnings;
  final Map<String, dynamic> raw;
  String get attribution => policy['attribution'] as String;
  factory FableLocationResponse.fromFable(Object? value) {
    if (value is! Map || !const {'google', 'osm'}.contains(value['provider']) ||
        value['policy'] is! Map || value['warnings'] is! List || !value.containsKey('data')) {
      throw const FormatException('Malformed location provider response');
    }
    final attribution = (value['policy'] as Map)['attribution'];
    if (attribution is! String || attribution.trim().isEmpty || attribution.length > 1000 ||
        !(value['warnings'] as List).every((w) => w is String && w.length <= 1000)) {
      throw const FormatException('Invalid provider attribution or warnings');
    }
    final raw = FableImmutablePayload.object(value);
    return FableLocationResponse._(raw['provider'] as String, raw['data'],
      raw['policy'] as Map<String, dynamic>,
      List<String>.unmodifiable((raw['warnings'] as List).cast<String>()), raw);
  }
}
/// Geofence is a backend-local calculation and is NOT a provider envelope.
class FableGeofenceDecision {
  const FableGeofenceDecision._(this.inside, this.distanceMeters, this.raw);
  final bool inside;
  final double? distanceMeters;
  final Map<String, dynamic> raw;
  factory FableGeofenceDecision.fromFable(Object? value) {
    if (value is! Map || value['inside'] is! bool ||
        (value['distanceMeters'] != null && value['distanceMeters'] is! num)) {
      throw const FormatException('Invalid geofence decision');
    }
    final raw = FableImmutablePayload.object(value);
    return FableGeofenceDecision._(raw['inside'] as bool,
        (raw['distanceMeters'] as num?)?.toDouble(), raw);
  }
}

typedef FableLocationDecoder = FableLocationResponse Function(Object? payload);
typedef FableGeofenceDecoder = FableGeofenceDecision Function(Object? payload);

/// Each ID is verified against the imported contract; Other Backend MUST map
/// its own IDs explicitly and never inherits Fable paths or permissions.
class FableLocationOperations {
  FableLocationOperations._(this.ids);
  final Map<String, String> ids;
  static const fableIds = <String, String>{
    'clientContract': 'location.client-contract',
    'providers': 'location.providers',
    'capabilities': 'location.capabilities',
    'geocode': 'location.geocode',
    'reverseGeocode': 'location.reverse-geocode',
    'nearby': 'location.nearby',
    'route': 'location.route',
    'matrix': 'location.matrix',
    'nearestRoad': 'location.nearest-road',
    'mapMatch': 'location.map-match',
    'isochrone': 'location.isochrone',
    'geofence': 'location.geofence',
  };
  static const _getRoles = {'clientContract', 'providers', 'capabilities'};
  factory FableLocationOperations.fable(FableContract catalog) =>
      FableLocationOperations._checked(catalog, fableIds);
  factory FableLocationOperations.external(ExternalOperationCatalog catalog,
      Map<String, String> bindings) => FableLocationOperations._checked(catalog, bindings);
  factory FableLocationOperations._checked(OperationCatalog catalog,
      Map<String, String> bindings) {
    if (bindings.isEmpty) throw const FormatException('Missing location operations');
    final accepted = <String, String>{};
    for (final entry in bindings.entries) {
      if (!fableIds.containsKey(entry.key)) throw const FormatException('Unknown location operation role');
      final op = catalog.require(entry.value);
      if (op.method != (_getRoles.contains(entry.key) ? 'GET' : 'POST') ||
          !op.requiresAuth || op.credentialHeader != null ||
          op.path.contains('{') || op.path.contains('}') || op.path.contains('?')) {
        throw const FormatException('Unsafe location operation binding');
      }
      accepted[entry.key] = op.id;
    }
    return FableLocationOperations._(Map.unmodifiable(accepted));
  }
  bool supports(String role) => ids.containsKey(role);
  String require(String role) => ids[role] ?? (throw StateError('Unbound location role: $role'));
}

class FableLocationRepository {
  const FableLocationRepository({required this.gateway, required this.operations,
      this.decoder = FableLocationResponse.fromFable,
      this.geofenceDecoder = FableGeofenceDecision.fromFable});
  final BackendApiGateway gateway;
  final FableLocationOperations operations;
  /// For Other Backend inject an explicitly reviewed response adapter if needed.
  final FableLocationDecoder decoder;
  final FableGeofenceDecoder geofenceDecoder;
  Future<Object?> _read(String role) async {
    final result = await gateway.execute(operations.require(role));
    return FableImmutablePayload.object({'data': result.data})['data'];
  }
  Future<Object?> clientContract() => _read('clientContract');
  Future<Object?> providers() => _read('providers');
  Future<Object?> capabilities() => _read('capabilities');
  Future<FableLocationResponse> _post(String role, Map<String, dynamic> body) async {
    final result = await gateway.execute(operations.require(role), body: body);
    return decoder(result.data);
  }
  static String? _provider(String? p) {
    if (p != null && !const {'google', 'osm'}.contains(p)) throw ArgumentError('Unsupported provider');
    return p;
  }
  Future<FableLocationResponse> geocode(String query, {String? provider, int limit = 10}) {
    final normalized = query.trim();
    if (normalized.runes.length < 2 || normalized.runes.length > 500 ||
        normalized.contains(RegExp(r'[\x00-\x1f\x7f]')) || limit < 1 || limit > 20) {
      throw ArgumentError('Invalid geocode query');
    }
    return _post('geocode', {'query': normalized, 'limit': limit,
      if (_provider(provider) != null) 'provider': provider});
  }
  Future<FableLocationResponse> reverse(FableGeoPoint point, {String? provider}) =>
    _post('reverseGeocode', {'point': point.toJson(),
      if (_provider(provider) != null) 'provider': provider});
  Future<FableLocationResponse> nearby(FableGeoPoint point, {String? provider,
      int radiusMeters = 3000, int limit = 20, List<String> types = const []}) {
    if (radiusMeters < 1 || radiusMeters > 50000 || limit < 1 || limit > 20 ||
        types.length > 20 || types.any((t) => t.isEmpty || t.length > 100)) {
      throw ArgumentError('Invalid nearby search');
    }
    return _post('nearby', {'point': point.toJson(), 'radiusMeters': radiusMeters,
      'limit': limit, 'types': types,
      if (_provider(provider) != null) 'provider': provider});
  }
  Future<FableLocationResponse> route(FableGeoPoint origin, FableGeoPoint destination,
      {String mode = 'DRIVE', String? provider}) {
    if (!const {'DRIVE','WALK','BICYCLE','TWO_WHEELER','TRANSIT'}.contains(mode)) {
      throw ArgumentError('Unsupported travel mode');
    }
    return _post('route', {'origin': origin.toJson(), 'destination': destination.toJson(),
      'mode': mode, if (_provider(provider) != null) 'provider': provider});
  }
  Future<FableLocationResponse> matrix(List<FableGeoPoint> origins,
      List<FableGeoPoint> destinations, {String? provider}) {
    if (origins.isEmpty || destinations.isEmpty || origins.length > 25 ||
        destinations.length > 25 || origins.length * destinations.length > 625) {
      throw ArgumentError('Invalid route matrix');
    }
    return _post('matrix', {'origins': origins.map((p) => p.toJson()).toList(),
      'destinations': destinations.map((p) => p.toJson()).toList(),
      if (_provider(provider) != null) 'provider': provider});
  }
  Future<FableLocationResponse> nearestRoad(List<FableGeoPoint> points,
      {String? provider}) => _points('nearestRoad', points, provider);
  Future<FableLocationResponse> mapMatch(List<FableGeoPoint> points,
      {String? provider}) => _points('mapMatch', points, provider);
  Future<FableLocationResponse> _points(String role, List<FableGeoPoint> points, String? provider) {
    if (points.isEmpty || points.length > 100) throw ArgumentError('Invalid point set');
    return _post(role, {'points': points.map((p) => p.toJson()).toList(),
      if (_provider(provider) != null) 'provider': provider});
  }
  Future<FableLocationResponse> isochrone(FableGeoPoint point,
      {int? minutes, int? meters, String? provider}) {
    if ((minutes == null && meters == null) ||
        (minutes != null && (minutes < 1 || minutes > 240)) ||
        (meters != null && (meters < 100 || meters > 500000))) {
      throw ArgumentError('Invalid isochrone');
    }
    return _post('isochrone', {'origin': point.toJson(),
      if (minutes != null) 'minutes': minutes, if (meters != null) 'meters': meters,
      if (_provider(provider) != null) 'provider': provider});
  }
  Future<FableGeofenceDecision> geofenceCircle(FableGeoPoint point,
      FableGeoPoint center, double radiusMeters) async {
    if (!radiusMeters.isFinite || radiusMeters < 1 || radiusMeters > 1000000) {
      throw ArgumentError('Invalid geofence radius');
    }
    final result = await gateway.execute(operations.require('geofence'), body: {
      'type': 'CIRCLE', 'point': point.toJson(),
      'center': center.toJson(), 'radiusMeters': radiusMeters,
    });
    return geofenceDecoder(result.data);
  }
}

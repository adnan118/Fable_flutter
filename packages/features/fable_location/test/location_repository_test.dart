import 'package:flutter_test/flutter_test.dart';
import 'package:fable_core/fable_core.dart';
import 'package:fable_location/fable_location.dart';
import 'package:dio/dio.dart';

class _Gateway implements BackendApiGateway {
  String? id;
  Object? requestBody;
  Object? output;
  @override
  Future<Response<dynamic>> execute(String operationId, {Map<String, dynamic>? path,
      Map<String, dynamic>? query, Object? body, CancelToken? cancelToken, String? ifMatch}) async {
    id = operationId;
    requestBody = body;
    return Response<dynamic>(requestOptions: RequestOptions(path: '/'), data: output);
  }
  @override void dispose() {}
}

void main() {
  const digest = '0123456789abcdef';
  final ops = <String, FableOperation>{
    for (final entry in FableLocationOperations.fableIds.entries)
      entry.value: FableOperation(entry.value,
        const {'clientContract', 'providers', 'capabilities'}.contains(entry.key) ? 'GET' : 'POST',
        '/geo/${entry.key}', digest, requiresAuth: true,enforceAuth:true),
  };
  FableContract contract() => FableContract(contractHash: digest, operations: ops,
    featureIds: const {'location-platform'}, projectName: 'test', selectionMode: 'explicit');

  test('fable operation registry uses verified bearer operations', () {
    final binding = FableLocationOperations.fable(contract());
    expect(binding.require('geocode'), 'location.geocode');
    expect(binding.supports('route'), true);
  });
  test('missing or public operation is rejected before any network access', () {
    final catalog = FableContract(contractHash: digest, operations: {
      'location.geocode': const FableOperation('location.geocode','POST','/geo',digest,requiresAuth:false),
    }, featureIds: const {}, projectName:'test',selectionMode:'explicit');
    expect(() => FableLocationOperations.fable(catalog), throwsA(isA<StateError>()));
  });
  test('RC227 declared auth alone cannot bind location API operations',(){
    final weakOps=<String,FableOperation>{
      for(final entry in FableLocationOperations.fableIds.entries)
        entry.value:FableOperation(entry.value,
          const {'clientContract','providers','capabilities'}.contains(entry.key)?'GET':'POST',
          '/geo/${entry.key}',digest,requiresAuth:true,enforceAuth:false),
    };
    final weak=FableContract(contractHash:digest,operations:weakOps,
      featureIds:const {'location-platform'},projectName:'weak',selectionMode:'explicit');
    expect(()=>FableLocationOperations.fable(weak),throwsFormatException);
    expect(FableLocationOperations.fable(contract()).supports('route'),true);
  });
  test('RC227 geofence refuses negative or nonfinite distances',(){
    for(final distance in <num>[-1,double.nan,double.infinity,double.negativeInfinity]){
      expect(()=>FableGeofenceDecision.fromFable({
        'inside':false,'distanceMeters':distance,
      }),throwsFormatException);
    }
    expect(FableGeofenceDecision.fromFable({'inside':true,'distanceMeters':0})
      .distanceMeters,0);
    expect(FableGeofenceDecision.fromFable({'inside':false})
      .distanceMeters,isNull);
  });
  test('RC227 location operation fragments are not valid client bindings',(){
    final poisoned=<String,FableOperation>{
      for(final entry in FableLocationOperations.fableIds.entries)
        entry.value:FableOperation(entry.value,
          const {'clientContract','providers','capabilities'}.contains(entry.key)?'GET':'POST',
          '/geo/${entry.key}#private',digest,requiresAuth:true,enforceAuth:true),
    };
    final c=FableContract(contractHash:digest,operations:poisoned,
      featureIds:const {'location-platform'},projectName:'invalid',
      selectionMode:'explicit');
    expect(()=>FableLocationOperations.fable(c),throwsFormatException);
  });
  test('provider response retains unknown fields and attribution immutably', () {
    final response = FableLocationResponse.fromFable({
      'provider': 'osm', 'data': [{'formattedAddress':'Damascus','location':{'lat':33.5,'lng':36.3}}],
      'policy': {'attribution': '© OpenStreetMap contributors'},
      'warnings': <String>[], 'extension': {'backendVersion':'1'},
    });
    expect(response.raw['extension'], isNotNull);
    expect(response.attribution, contains('OpenStreetMap'));
    expect(() => response.raw['extension'] = {}, throwsUnsupportedError);
    expect(() => FableLocationResponse.fromFable({
      'provider':'osm','data': [],'policy':{},'warnings':[],
    }), throwsFormatException);
  });
  test('geofence uses backend decision, not provider envelope', () async {
    final gateway = _Gateway()..output = {'inside': true, 'distanceMeters': 42.0};
    final repo = FableLocationRepository(gateway: gateway,
        operations: FableLocationOperations.fable(contract()));
    final result = await repo.geofenceCircle(FableGeoPoint(33,36), FableGeoPoint(33,36), 100);
    expect(result.inside, true);
    expect(result.distanceMeters, 42.0);
    expect(gateway.id, 'location.geofence');
  });
  test('geocode request uses authenticated bound operation and rejects invalid data', () async {
    final gateway = _Gateway()..output = {
      'provider':'osm','data': [],
      'policy':{'attribution':'© OpenStreetMap'},'warnings':<String>[],
    };
    final repo = FableLocationRepository(gateway:gateway,
      operations:FableLocationOperations.fable(contract()));
    await repo.geocode('  Hama  ');
    expect(gateway.id,'location.geocode');
    expect((gateway.requestBody as Map)['query'],'Hama');
    expect(() => repo.geocode('a'), throwsArgumentError);
    expect(() => FableGeoPoint(99,35), throwsArgumentError);
    expect(() => repo.matrix([], [FableGeoPoint(33,36)]), throwsArgumentError);
  });
}

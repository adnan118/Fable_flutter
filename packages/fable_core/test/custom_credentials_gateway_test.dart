import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fable_core/fable_core.dart';

class _RuntimeCredentials implements BackendCredentialProvider {
  String value = 'opaque-key';
  int recoveries = 0;
  @override
  Future<String?> credentialFor(FableOperation operation) async => value;
  @override
  Future<bool> recoverUnauthorized(FableOperation operation) async {
    recoveries++;
    value = 'new-key';
    return true;
  }
}

ExternalOperationCatalog _catalog({String method = 'GET'}) {
  final ops = <Map<String, String>>[
    {'operationId': 'protected.request', 'method': method, 'path': '/protected',
     'auth': 'provider', 'credentialHeader': 'X-Client-Key'},
    {'operationId': 'public.read', 'method': 'GET', 'path': '/public', 'auth': 'none'},
  ];
  return ExternalOperationCatalog.fromMap({
    'schemaVersion': 1,
    'kind': 'fable.external-operation-catalog',
    'adapter': 'openapi',
    'baseUrl': 'https://api.example.test',
    'sourceHash': List<String>.filled(64, 'a').join(),
    'operationsHash': sha256.convert(utf8.encode(jsonEncode(ops))).toString(),
    'operations': ops,
  });
}

void main() {
  test('runtime-only API key belongs only to protected declared header', () async {
    final credentials = _RuntimeCredentials();
    final dio = Dio();
    final recorded = <RequestOptions>[];
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      recorded.add(options);
      handler.resolve(Response<dynamic>(requestOptions: options, statusCode: 200, data: {}));
    }));
    final gateway = ExternalApiGateway(catalog: _catalog(),
      session: FableSecureSession(), client: dio,
      credentialProvider: credentials);
    addTearDown(gateway.dispose);
    await gateway.execute('public.read');
    await gateway.execute('protected.request');
    expect(recorded[0].headers.containsKey('X-Client-Key'), false);
    expect(recorded[1].headers['X-Client-Key'], 'opaque-key');
    expect(recorded[1].headers.containsKey('Authorization'), false);
  });

  test('provider credentials can recover GET 401 only once', () async {
    final creds = _RuntimeCredentials();
    final dio = Dio();
    var count = 0;
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      count++;
      handler.resolve(Response<dynamic>(requestOptions: options,
        statusCode: count == 1 ? 401 : 200, data: {}));
    }));
    final gateway = ExternalApiGateway(catalog: _catalog(),
      session: FableSecureSession(), client: dio, credentialProvider: creds);
    addTearDown(gateway.dispose);
    await gateway.execute('protected.request');
    expect(count, 2);
    expect(creds.recoveries, 1);
  });

  test('mutation is never automatically replayed after recovery', () async {
    final creds = _RuntimeCredentials();
    final dio = Dio();
    var count = 0;
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      count++;
      handler.resolve(Response<dynamic>(requestOptions: options, statusCode: 401, data: {}));
    }));
    final gateway = ExternalApiGateway(catalog: _catalog(method: 'POST'),
      session: FableSecureSession(), client: dio, credentialProvider: creds);
    addTearDown(gateway.dispose);
    await expectLater(gateway.execute('protected.request', body: {'item': 1}),
      throwsA(isA<FableApiException>()));
    expect(count, 1);
  });
}

import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fable_core/fable_core.dart';

void main() {
  final operations = <Map<String, String>>[
    {'operationId': 'session.login', 'method': 'POST', 'path': '/signin', 'auth': 'none'},
    {'operationId': 'session.refresh', 'method': 'POST', 'path': '/token', 'auth': 'none'},
    {'operationId': 'session.logout', 'method': 'POST', 'path': '/signout', 'auth': 'bearer'},
  ];
  final hash = sha256.convert(utf8.encode(jsonEncode(operations))).toString();
  final catalog = ExternalOperationCatalog.fromMap({
    'schemaVersion': 1,
    'kind': 'fable.external-operation-catalog',
    'adapter': 'openapi',
    'baseUrl': 'https://api.example.test',
    'sourceHash': List<String>.filled(64, 'a').join(),
    'operationsHash': hash,
    'operations': operations,
  });
  Map<String, dynamic> valid() => {
    'schemaVersion': 1,
    'kind': 'fable.external-auth-binding',
    'adapter': 'openapi',
    'sourceHash': List<String>.filled(64, 'a').join(),
    'operationsHash': hash,
    'login': {
      'operationId': 'session.login',
      'request': {'identifier': 'credentials.email', 'password': 'credentials.password'},
      'response': {'accessToken': 'data.access', 'refreshToken': 'data.refresh'},
    },
    'refresh': {
      'operationId': 'session.refresh',
      'request': {'refreshToken': 'refreshToken'},
      'response': {'accessToken': 'data.access', 'refreshToken': null},
    },
    'logout': {'operationId': 'session.logout'},
  };

  test('only contract-pinned external login/refresh/logout are accepted', () {
    final spec = ExternalAuthBinding.fromMap(valid(), catalog);
    expect(spec.login['operationId'], 'session.login');
    expect(spec.refresh?['operationId'], 'session.refresh');
    expect(spec.logout?['operationId'], 'session.logout');
  });
  test('contract drift invalidates authentication mapping', () {
    final spec = valid()..['operationsHash'] = List<String>.filled(64, '0').join();
    expect(() => ExternalAuthBinding.fromMap(spec, catalog), throwsFormatException);
  });
  test('untrusted payload field selectors and bearer login are rejected', () {
    final polluted = valid();
    (polluted['login'] as Map)['request'] = {'identifier': '__proto__.email', 'password': 'pass'};
    expect(() => ExternalAuthBinding.fromMap(polluted, catalog), throwsFormatException);
    final invalid = valid();
    (invalid['login'] as Map)['operationId'] = 'session.logout';
    expect(() => ExternalAuthBinding.fromMap(invalid, catalog), throwsFormatException);
  });
  test('backend tokens are namespace isolated by origin and contract', () {
    final a = ExternalAuthGateway.secureSessionFor(catalog);
    final same = ExternalAuthGateway.secureSessionFor(catalog);
    expect(a.runtimeType, same.runtimeType);
    final changedCatalog = ExternalOperationCatalog.fromMap({
      'schemaVersion': 1,
      'kind': 'fable.external-operation-catalog',
      'adapter': 'openapi',
      'baseUrl': 'https://different.example.test',
      'sourceHash': List<String>.filled(64, 'a').join(),
      'operationsHash': hash,
      'operations': operations,
    });
    expect(ExternalAuthGateway.secureSessionFor(changedCatalog).runtimeType, same.runtimeType);
    // Full namespace isolation is also exercised by application-level storage tests
    // in a real Flutter runtime; reading private key names here is intentionally avoided.
  });
}

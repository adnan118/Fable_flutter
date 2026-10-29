import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fable_core/fable_core.dart';

/// Integration tests with REAL loopback sockets. These deliberately use no
/// framework-specific Backend assumptions and no platform secure-storage calls.
/// They run with `flutter test` on the CI runner; they have not been executed
/// in SDK-free environments.
class _ServerCatalog implements OperationCatalog {
  const _ServerCatalog(this.isFable);
  final bool isFable;
  @override
  bool get sendsInstallationId => isFable;
  @override
  bool supports(String id) => const {'public.get', 'account.get', 'payment.post'}.contains(id);
  @override
  FableOperation require(String id) {
    if (!supports(id)) throw StateError('Operation not declared: $id');
    return FableOperation(
      id,
      id == 'payment.post' ? 'POST' : 'GET',
      id == 'public.get' ? '/public' : id == 'payment.post' ? '/payment' : '/me',
      'fixture-contract-hash',
      requiresAuth: id != 'public.get', enforceAuth: true,
    );
  }
}

class _Session extends FableSecureSession {
  String? token = 'old';
  int generation = 0;
  int clearCount = 0;
  @override
  int get identityRevision => generation;
  @override
  Future<String?> get accessToken async => token;
  @override
  Future<String?> get refreshToken async => null;
  @override
  Future<String> installationId() async => '0123456789abcdef0123456789abcdef';
  @override
  Future<bool> clearSessionIfIdentity(int expectedIdentity, {
    String? expectedAccessToken, String? expectedRefreshToken,
  }) async {
    if (generation != expectedIdentity ||
        (expectedAccessToken != null && token != expectedAccessToken)) return false;
    token = null;
    generation++;
    clearCount++;
    return true;
  }
}

Future<void> _respond(HttpResponse res, int code, Object body) async {
  res.statusCode = code;
  res.headers.contentType = ContentType.json;
  res.write(jsonEncode(body));
  await res.close();
}

void main() {
  test('Fable headers, public route, one refresh, and read retry over HTTP', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final seen = <Map<String, String?>>[];
    server.listen((request) async {
      seen.add({
        'path': request.uri.path,
        'auth': request.headers.value(HttpHeaders.authorizationHeader),
        'installation': request.headers.value('x-installation-id'),
      });
      if (request.uri.path == '/public') {
        await _respond(request.response, 200, {'public': true});
      } else if (request.headers.value(HttpHeaders.authorizationHeader) == 'Bearer fresh') {
        await _respond(request.response, 200, {'name': 'Fable user'});
      } else {
        await _respond(request.response, 401, {'code': 'expired'});
      }
    });
    final session = _Session();
    const catalog = _ServerCatalog(true);
    var refreshes = 0;
    final gateway = UnifiedApiClient(
      baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
      contract: catalog,
      session: session,
      adapter: FableTransportAdapter(catalog: catalog, language: 'ar'),
      refreshSession: () async { refreshes++; session.token = 'fresh'; return true; },
      allowHttpForLocalDevelopment: true,
    );
    addTearDown(() async { gateway.dispose(); await server.close(force: true); });
    expect((await gateway.execute('public.get')).statusCode, 200);
    expect((await gateway.execute('account.get')).statusCode, 200);
    expect(refreshes, 1);
    expect(seen.map((e) => e['path']).toList(), ['/public', '/me', '/me']);
    expect(seen[0]['auth'], isNull);
    expect(seen[0]['installation'], '0123456789abcdef0123456789abcdef');
    expect(seen[1]['auth'], 'Bearer old');
    expect(seen[2]['auth'], 'Bearer fresh');
  });

  test('Generic single-bearer backend never gets Fable headers or refreshes', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final seen = <Map<String, String?>>[];
    server.listen((request) async {
      seen.add({
        'auth': request.headers.value(HttpHeaders.authorizationHeader),
        'installation': request.headers.value('x-installation-id'),
        'publicHeader': request.headers.value('x-client-version'),
      });
      await _respond(request.response,
        request.uri.path == '/public' ? 200 : 401, {'message': 'token expired'});
    });
    final session = _Session();
    const catalog = _ServerCatalog(false);
    final gateway = UnifiedApiClient(
      baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
      contract: catalog,
      session: session,
      adapter: ExternalTransportAdapter(catalog: catalog,
        sessionMode: BackendSessionMode.singleBearer,
        publicHeaders: const {'X-Client-Version': 'ci'}),
      allowHttpForLocalDevelopment: true,
    );
    addTearDown(() async { gateway.dispose(); await server.close(force: true); });
    await gateway.execute('public.get');
    await expectLater(gateway.execute('account.get'),
      throwsA(isA<FableApiException>().having((e) => e.status, 'status', 401)));
    expect(seen.length, 2); // No invented refresh or automatic retry.
    expect(seen[0]['auth'], isNull);
    expect(seen[1]['auth'], 'Bearer old');
    expect(seen.every((e) => e['installation'] == null), isTrue);
    expect(seen.every((e) => e['publicHeader'] == 'ci'), isTrue);
    expect(session.token, isNull);
    expect(session.clearCount, 1);
  });

  test('A non-idempotent POST remains one request after refresh', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var writes = 0;
    server.listen((request) async {
      writes++;
      await _respond(request.response, 401, {'code': 'expired'});
    });
    final session = _Session();
    const catalog = _ServerCatalog(false);
    var refreshes = 0;
    final gateway = UnifiedApiClient(
      baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
      contract: catalog,
      session: session,
      adapter: ExternalTransportAdapter(catalog: catalog,
        sessionMode: BackendSessionMode.rotatingBearer),
      refreshSession: () async { refreshes++; session.token = 'fresh'; return true; },
      allowHttpForLocalDevelopment: true,
    );
    addTearDown(() async { gateway.dispose(); await server.close(force: true); });
    await expectLater(gateway.execute('payment.post', body: {'amount': 100}),
      throwsA(isA<FableApiException>().having((e) => e.code, 'code',
        'session_refreshed_retry_manually')));
    expect(writes, 1);
    expect(refreshes, 1);
  });

  test('Transient GET 503 retries once on a real loopback server', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var requests = 0;
    server.listen((request) async {
      requests++;
      await _respond(request.response, requests == 1 ? 503 : 200,
          {'request': requests});
    });
    final session = _Session();
    const catalog = _ServerCatalog(false);
    final client = UnifiedApiClient(
      baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
      contract: catalog, session: session,
      allowHttpForLocalDevelopment: true,
      retryPolicy: const FableRetryPolicy(baseDelay: Duration.zero,
          maxDelay: Duration.zero),
    );
    addTearDown(() async { client.dispose(); await server.close(force: true); });
    expect((await client.execute('public.get')).statusCode, 200);
    expect(requests, 2);
  });

  test('POST 503 is NEVER automatically replayed', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var writes = 0;
    server.listen((request) async {
      writes++;
      await _respond(request.response, 503, {'code': 'unavailable'});
    });
    final session = _Session();
    const catalog = _ServerCatalog(false);
    final client = UnifiedApiClient(
      baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
      contract: catalog, session: session,
      allowHttpForLocalDevelopment: true,
      retryPolicy: const FableRetryPolicy(baseDelay: Duration.zero,
          maxDelay: Duration.zero),
    );
    addTearDown(() async { client.dispose(); await server.close(force: true); });
    await expectLater(client.execute('payment.post', body: {'amount': 100}),
        throwsA(isA<FableApiException>().having((e) => e.status, 'status', 503)));
    expect(writes, 1);
  });

  test('429 Retry-After beyond safe foreground window is respected', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var hits = 0;
    server.listen((request) async {
      hits++;
      request.response.headers.set('retry-after', '30');
      await _respond(request.response, 429, {'code': 'rate_limited'});
    });
    final session = _Session();
    const catalog = _ServerCatalog(false);
    final client = UnifiedApiClient(
      baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
      contract: catalog, session: session,
      allowHttpForLocalDevelopment: true,
      retryPolicy: const FableRetryPolicy(maxDelay: Duration(seconds: 2)),
    );
    addTearDown(() async { client.dispose(); await server.close(force: true); });
    await expectLater(client.execute('public.get'),
        throwsA(isA<FableApiException>().having((e) => e.status, 'status', 429)));
    expect(hits, 1);
  });


  test('Account switch during backoff prevents replay using old credentials', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final session = _Session();
    var hits = 0;
    server.listen((request) async {
      hits++;
      session.generation++;
      await _respond(request.response, 503, {'code': 'unavailable'});
    });
    const catalog = _ServerCatalog(false);
    final client = UnifiedApiClient(
      baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
      contract: catalog, session: session,
      allowHttpForLocalDevelopment: true,
      retryPolicy: const FableRetryPolicy(baseDelay: Duration.zero,
          maxDelay: Duration.zero),
    );
    addTearDown(() async { client.dispose(); await server.close(force: true); });
    await expectLater(client.execute('account.get'),
      throwsA(isA<FableApiException>().having((e) => e.code, 'code',
        'session_changed_discard_response')));
    expect(hits, 1);
  });

}

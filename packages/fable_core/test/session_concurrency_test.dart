import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fable_core/fable_core.dart';

class _Operations implements OperationCatalog {
  const _Operations();
  @override
  bool get sendsInstallationId => false;
  @override
  bool supports(String id) => const {'account.read', 'profile.update', 'health.public'}.contains(id);
  @override
  FableOperation require(String id) {
    if (!supports(id)) throw StateError('Unknown operation');
    return FableOperation(id, id == 'profile.update' ? 'PATCH' : 'GET',
        id == 'health.public' ? '/health' : '/account', 'verified',
        requiresAuth: id != 'health.public', enforceAuth: true);
  }
}

class _MemorySession extends FableSecureSession {
  String? token = 'old';
  int clears = 0;
  @override
  int identityRevision = 0;
  @override
  Future<void> replaceTokens({required String accessToken, String? refreshToken}) async {
    identityRevision++;
    token = accessToken;
  }
  @override
  Future<String?> get accessToken async => token;
  @override
  Future<String?> get refreshToken async => null;
  @override
  Future<void> clearSession() async { clears++; identityRevision++; token = null; }
  @override
  Future<bool> clearSessionIfIdentity(int expectedIdentity, {String? expectedAccessToken, String? expectedRefreshToken}) async {
    if (identityRevision != expectedIdentity ||
        (expectedAccessToken != null && token != expectedAccessToken)) return false;
    await clearSession();
    return true;
  }
  @override
  Future<bool> saveTokensIfIdentity({required int expectedIdentity,
      required String accessToken, String? refreshToken, String? expectedRefreshToken}) async {
    if (identityRevision != expectedIdentity) return false;
    token = accessToken;
    return true;
  }
  @override
  Future<bool> replaceTokensIfIdentity({required int expectedIdentity,
      required String accessToken, String? refreshToken}) async {
    if (identityRevision != expectedIdentity) return false;
    await replaceTokens(accessToken: accessToken, refreshToken: refreshToken);
    return true;
  }
  @override
  Future<String> installationId() async => '0123456789abcdef0123456789abcdef';
}

Dio _stub(FutureOr<int> Function(RequestOptions) status) {
  final dio = Dio();
  dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) async {
    try {
      final result = await status(request);
      handler.resolve(Response<dynamic>(requestOptions: request, statusCode: result,
          data: <String, dynamic>{}));
    } catch (error, stack) {
      // Test-only diagnostics: never print any Bearer token or request body.
      // Dio otherwise converts an assertion in this stub to network_error.
      // ignore: avoid_print
      print('DIO_TEST_STUB_FAILURE host=${request.uri.host} path=${request.path} error=$error\n$stack');
      rethrow;
    }
  }));
  return dio;
}

void main() {
  test('Late stale 401 uses already-rotated token; exactly one refresh', () async {
    final session = _MemorySession();
    const catalog = _Operations();
    final secondStarted = Completer<void>();
    final releaseLate = Completer<void>();
    var oldRequests = 0;
    var refreshes = 0;
    final client = UnifiedApiClient(baseUri: Uri.parse('https://service.example.test'),
      contract: catalog, session: session,
      adapter: ExternalTransportAdapter(catalog: catalog,
          sessionMode: BackendSessionMode.rotatingBearer),
      refreshSession: () async { refreshes++; session.token = 'new'; return true; },
      client: _stub((request) async {
        expect(request.uri.host, 'service.example.test');
        final auth = request.headers['Authorization'];
        if (auth == 'Bearer new') return 200;
        expect(auth, 'Bearer old');
        oldRequests++;
        if (oldRequests == 1) await secondStarted.future;
        if (oldRequests == 2) { secondStarted.complete(); await releaseLate.future; }
        return 401;
      }));
    addTearDown(client.dispose);
    final first = client.execute('account.read');
    final second = client.execute('account.read');
    expect((await first).statusCode, 200);
    releaseLate.complete();
    expect((await second).statusCode, 200);
    expect(refreshes, 1);
    expect(oldRequests, 2);
    expect(session.clears, 0);
  });

  test('Stale 401 cannot delete a newer single-token login', () async {
    final session = _MemorySession();
    const catalog = _Operations();
    final client = UnifiedApiClient(baseUri: Uri.parse('https://service.example.test'),
      contract: catalog, session: session,
      adapter: ExternalTransportAdapter(catalog: catalog,
          sessionMode: BackendSessionMode.singleBearer),
      client: _stub((request) { session.token = 'new-login'; return 401; }));
    addTearDown(client.dispose);
    await expectLater(client.execute('account.read'), throwsA(isA<FableApiException>()));
    expect(session.token, 'new-login');
    expect(session.clears, 0);
  });

  test('Rotated token never silently replays a PATCH mutation', () async {
    final session = _MemorySession();
    const catalog = _Operations();
    var calls = 0;
    var refreshes = 0;
    final client = UnifiedApiClient(baseUri: Uri.parse('https://service.example.test'),
      contract: catalog, session: session,
      adapter: ExternalTransportAdapter(catalog: catalog,
          sessionMode: BackendSessionMode.rotatingBearer),
      refreshSession: () async { refreshes++; session.token = 'new'; return true; },
      client: _stub((request) { calls++; return 401; }));
    addTearDown(client.dispose);
    await expectLater(client.execute('profile.update', body: {'name': 'Ada'}),
      throwsA(isA<FableApiException>().having((e) => e.code, 'code',
          'session_refreshed_retry_manually')));
    expect(calls, 1);
    expect(refreshes, 1);
  });

  test('An in-flight success for a signed-out user is never delivered', () async {
    final session = _MemorySession();
    const catalog = _Operations();
    final client = UnifiedApiClient(baseUri: Uri.parse('https://service.example.test'),
      contract: catalog, session: session,
      client: _stub((request) async {
        await session.clearSession();
        return 200;
      }));
    addTearDown(client.dispose);
    await expectLater(client.execute('account.read'),
      throwsA(isA<FableApiException>().having((error) => error.code,
        'code', 'session_changed_discard_response')));
    expect(session.token, null);
  });

  test('Old account success cannot be displayed after a different login', () async {
    final session = _MemorySession();
    const catalog = _Operations();
    final client = UnifiedApiClient(baseUri: Uri.parse('https://service.example.test'),
      contract: catalog, session: session,
      client: _stub((request) async {
        expect(request.headers['Authorization'], 'Bearer old');
        await session.replaceTokens(accessToken: 'other-account');
        return 200;
      }));
    addTearDown(client.dispose);
    await expectLater(client.execute('account.read'),
      throwsA(isA<FableApiException>().having((error) => error.code,
        'code', 'session_changed_discard_response')));
    expect(session.token, 'other-account');
    expect(session.clears, 0);
  });

  test('Stale unauthorized response cannot clear new account after refresh', () async {
    final session = _MemorySession();
    const catalog = _Operations();
    final client = UnifiedApiClient(baseUri: Uri.parse('https://service.example.test'),
      contract: catalog, session: session,
      adapter: ExternalTransportAdapter(catalog: catalog,
          sessionMode: BackendSessionMode.rotatingBearer),
      refreshSession: () async {
        await session.replaceTokens(accessToken: 'new-account');
        return false;
      },
      client: _stub((request) => 401));
    addTearDown(client.dispose);
    await expectLater(client.execute('account.read'),
      throwsA(isA<FableApiException>().having((error) => error.code,
        'code', 'session_changed_discard_response')));
    expect(session.token, 'new-account');
    expect(session.clears, 0);
  });

  test('Anonymous adapter cannot leak locally stored Bearer tokens', () async {
    final session = _MemorySession();
    const catalog = _Operations();
    var hits = 0;
    final client = UnifiedApiClient(baseUri: Uri.parse('https://service.example.test'),
      contract: catalog, session: session,
      adapter: ExternalTransportAdapter(catalog: catalog,
          sessionMode: BackendSessionMode.anonymous),
      client: _stub((request) {
        hits++;
        expect(request.headers.containsKey('Authorization'), false);
        return 200;
      }));
    addTearDown(client.dispose);
    await expectLater(client.execute('account.read'), throwsA(isA<FableApiException>()));
    expect((await client.execute('health.public')).statusCode, 200);
    expect(hits, 1);
  });

  test('An old refresh flight cannot be reused by a newly logged-in account', () async {
    final session = _MemorySession();
    const catalog = _Operations();
    final oldRefresh = Completer<bool>();
    var refreshCalls = 0;
    final client = UnifiedApiClient(baseUri: Uri.parse('https://service.example.test'),
      contract: catalog, session: session,
      adapter: ExternalTransportAdapter(catalog: catalog,
          sessionMode: BackendSessionMode.rotatingBearer),
      refreshSession: () {
        refreshCalls++;
        if (refreshCalls == 1) return oldRefresh.future;
        session.token = 'new-account-fresh';
        return Future<bool>.value(true);
      },
      client: _stub((request) {
        return request.headers['Authorization'] == 'Bearer new-account-fresh' ? 200 : 401;
      }));
    addTearDown(client.dispose);
    final oldCall = client.execute('account.read');
    // Wait until the first refresh is in flight, rather than using delays.
    while (refreshCalls == 0) { await Future<void>.delayed(Duration.zero); }
    await session.replaceTokens(accessToken: 'new-account');
    expect((await client.execute('account.read')).statusCode, 200);
    oldRefresh.complete(false);
    await expectLater(oldCall, throwsA(isA<FableApiException>()));
    expect(refreshCalls, 2);
    expect(session.token, 'new-account-fresh');
    expect(session.clears, 0);
  });

  test('A delayed 401 cannot clear another identity even with the same token', () async {
    final session = _MemorySession();
    const catalog = _Operations();
    final client = UnifiedApiClient(baseUri: Uri.parse('https://service.example.test'),
      contract: catalog, session: session,
      adapter: ExternalTransportAdapter(catalog: catalog,
          sessionMode: BackendSessionMode.singleBearer),
      client: _stub((request) async {
        await session.replaceTokens(accessToken: 'old');
        return 401;
      }));
    addTearDown(client.dispose);
    await expectLater(client.execute('account.read'),
      throwsA(isA<FableApiException>().having((e) => e.code,
          'code', 'session_changed_discard_response')));
    expect(session.token, 'old');
    expect(session.clears, 0);
  });

}

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fable_core/fable_core.dart';

/// هذه الاختبارات تعزل شبكة Auth عن SecureStorage الحقيقي؛
/// التكامل مع Keychain/Keystore وBackend الحي يبقى بوابة E2E مستقلة.
class _Session extends FableSecureSession {
  String? access = 'old-access';
  String? refresh = List<String>.filled(64, 'r').join();
  @override int identityRevision = 0;

  @override Future<String?> get accessToken async => access;
  @override Future<String?> get refreshToken async => refresh;
  @override Future<String> installationId() async => '0123456789abcdef0123456789abcdef';

  @override
  Future<bool> replaceTokensIfIdentity({
    required int expectedIdentity,
    required String accessToken,
    String? refreshToken,
  }) async {
    if (expectedIdentity != identityRevision) return false;
    identityRevision++;
    access = accessToken;
    refresh = refreshToken;
    return true;
  }

  @override
  Future<bool> saveTokensIfIdentity({
    required int expectedIdentity,
    required String accessToken,
    String? refreshToken,
    String? expectedRefreshToken,
  }) async {
    if (expectedIdentity != identityRevision ||
        (expectedRefreshToken != null && expectedRefreshToken != refresh)) {
      return false;
    }
    access = accessToken;
    if (refreshToken != null) refresh = refreshToken;
    return true;
  }

  @override
  Future<bool> clearSessionIfIdentity(int expectedIdentity, {
    String? expectedAccessToken,
    String? expectedRefreshToken,
  }) async {
    if (expectedIdentity != identityRevision ||
        (expectedAccessToken != null && expectedAccessToken != access) ||
        (expectedRefreshToken != null && expectedRefreshToken != refresh)) {
      return false;
    }
    identityRevision++;
    access = null;
    refresh = null;
    return true;
  }
}

FableOperation _op(String id, String method, String path, {
  bool requiresAuth = false,
  bool enforceAuth = true,
  String? credentialHeader,
}) => FableOperation(id, method, path, 'verified-hash',
  requiresAuth: requiresAuth,
  enforceAuth: enforceAuth,
  credentialHeader: credentialHeader,
);

FableContract _contract(Map<String, FableOperation> ops) => FableContract(
  contractHash: List<String>.filled(64, 'a').join(),
  operations: ops,
  featureIds: const <String>{'auth'},
  projectName: 'rc83',
  selectionMode: 'explicit',
);

Dio _network(Future<Response<dynamic>> Function(RequestOptions) respond) {
  final dio = Dio();
  dio.interceptors.add(InterceptorsWrapper(onRequest: (req, handler) async {
    try {
      handler.resolve(await respond(req));
    } catch (error) {
      handler.reject(DioException(requestOptions: req, error: error));
    }
  }));
  return dio;
}

Response<dynamic> _reply(RequestOptions req, int code, Object? value) =>
  Response<dynamic>(requestOptions: req, statusCode: code, data: value);

const _sessionId = '550e8400-e29b-41d4-a716-446655440000';
final _sessionRecord = <String, dynamic>{
  'id': _sessionId, 'isCurrent': true,
  'createdAt': '2026-10-01T12:00:00Z',
  'expiresAt': '2026-12-01T12:00:00Z',
};

void main() {
  test('Login rejects wrong method, route, auth mode, and unsigned auth metadata', () async {
    final invalid = <FableOperation>[
      _op('auth.login', 'GET', '/auth/login'),
      _op('auth.login', 'POST', '/other/login'),
      _op('auth.login', 'POST', '/auth/login', requiresAuth: true),
      _op('auth.login', 'POST', '/auth/login', enforceAuth: false),
      _op('auth.login', 'POST', '/auth/login', credentialHeader: 'X-Key'),
    ];
    for (final operation in invalid) {
      var requests = 0;
      final gateway = FableAuthGateway(
        baseUri: Uri.parse('https://fable.test'),
        contract: _contract({'auth.login': operation}),
        secureSession: _Session(),
        client: _network((req) async {
          requests++;
          return _reply(req, 200, {});
        }),
      );
      await expectLater(gateway.login(
        identifier: 'demo@example.test',
        password: 'fake-secret',
        platform: 'android',
      ), throwsStateError);
      expect(requests, 0);
      gateway.dispose();
    }
  });

  test('Valid Login uses declared Fable request and verifies tokens before saving', () async {
    final session = _Session();
    var calls = 0;
    final gateway = FableAuthGateway(
      baseUri: Uri.parse('https://fable.test'),
      contract: _contract({
        'auth.login': _op('auth.login', 'POST', '/auth/login'),
      }),
      secureSession: session,
      client: _network((req) async {
        calls++;
        expect(req.method, 'POST');
        expect(req.path, '/auth/login');
        expect(req.data, {
          'identifier': 'demo@example.test',
          'password': 'fake-secret',
          'clientType': 'flutter',
          'installationId': '0123456789abcdef0123456789abcdef',
          'platform': 'android',
        });
        expect(req.headers.containsKey('Authorization'), false);
        expect(req.headers.containsKey('X-Fable-Managed-Entity-Id'), false);
        return _reply(req, 200, {
          'accessToken': 'new-access',
          'refreshToken': List<String>.filled(64, 's').join(),
          'expiresAt': '2026-12-01T12:00:00Z',
        });
      }),
    );
    addTearDown(gateway.dispose);
    final outcome = await gateway.login(
      identifier: ' demo@example.test ',
      password: 'fake-secret',
      platform: 'android',
    );
    expect(outcome.authenticated, true);
    expect(session.access, 'new-access');
    expect(session.identityRevision, 1);
    expect(calls, 1);
  });

  test('Session policy is public GET only and requires deployed installation policy', () async {
    for (final bad in <FableOperation>[
      _op('auth.session-policy', 'POST', '/auth/session-policy'),
      _op('auth.session-policy', 'GET', '/auth/session-policy', requiresAuth: true),
      _op('auth.session-policy', 'GET', '/other/session-policy'),
    ]) {
      var calls = 0;
      final gateway = FableAuthGateway(
        baseUri: Uri.parse('https://fable.test'),
        contract: _contract({'auth.session-policy': bad}),
        secureSession: _Session(),
        client: _network((req) async {
          calls++;
          return _reply(req, 200, {});
        }),
      );
      await expectLater(gateway.loadSessionPolicy(), throwsStateError);
      expect(calls, 0);
      gateway.dispose();
    }

    final gateway = FableAuthGateway(
      baseUri: Uri.parse('https://fable.test'),
      contract: _contract({
        'auth.session-policy': _op('auth.session-policy',
          'GET', '/auth/session-policy'),
      }),
      secureSession: _Session(),
      client: _network((req) async {
        expect(req.headers.containsKey('Authorization'), false);
        return _reply(req, 200, {
          'mode': 'multi',
          'maxActive': 3,
          'overflow': 'reject-new',
          'onePerInstallation': true,
        });
      }),
    );
    addTearDown(gateway.dispose);
    final policy = await gateway.loadSessionPolicy();
    expect(policy.maxActive, 3);
    expect(policy.onePerInstallation, true);
    expect(policy.overflow, 'reject-new');
  });

  test('Missing onePerInstallation runtime value is not silently guessed', () async {
    final gateway = FableAuthGateway(
      baseUri: Uri.parse('https://fable.test'),
      contract: _contract({
        'auth.session-policy': _op('auth.session-policy',
          'GET', '/auth/session-policy'),
      }),
      secureSession: _Session(),
      client: _network((req) async => _reply(req, 200, {
        'mode': 'multi', 'maxActive': 5, 'overflow': 'revoke-oldest',
      })),
    );
    addTearDown(gateway.dispose);
    await expectLater(gateway.loadSessionPolicy(), throwsFormatException);
  });

  test('Sessions require verified authenticated GET and strict session DTO', () async {
    final session = _Session();
    var calls = 0;
    final wrong = FableAuthGateway(
      baseUri: Uri.parse('https://fable.test'),
      contract: _contract({
        'auth.sessions': _op('auth.sessions', 'GET', '/auth/sessions'),
      }),
      secureSession: session,
      client: _network((req) async {
        calls++;
        return _reply(req, 200, [_sessionRecord]);
      }),
    );
    await expectLater(wrong.listActiveSessions(), throwsStateError);
    expect(calls, 0);
    wrong.dispose();

    final valid = FableAuthGateway(
      baseUri: Uri.parse('https://fable.test'),
      contract: _contract({
        'auth.sessions': _op('auth.sessions', 'GET', '/auth/sessions',
          requiresAuth: true),
      }),
      secureSession: session,
      client: _network((req) async {
        expect(req.headers['Authorization'], 'Bearer old-access');
        return _reply(req, 200, [_sessionRecord]);
      }),
    );
    addTearDown(valid.dispose);
    final rows = await valid.listActiveSessions();
    expect(rows, hasLength(1));
    expect(rows.single.isCurrent, true);
    expect(rows.single.id, _sessionId);
  });

  test('Refresh rotation is single-use and preserves the same session identity', () async {
    final session = _Session();
    var refreshRequests = 0;
    final gateway = FableAuthGateway(
      baseUri: Uri.parse('https://fable.test'),
      contract: _contract({
        'auth.sessions': _op('auth.sessions', 'GET', '/auth/sessions',
          requiresAuth: true),
        'auth.refresh': _op('auth.refresh', 'POST', '/auth/refresh'),
      }),
      secureSession: session,
      client: _network((req) async {
        if (req.path == '/auth/refresh') {
          refreshRequests++;
          expect(req.method, 'POST');
          expect(req.headers.containsKey('Authorization'), false);
          expect(req.data, {
            'refreshToken': List<String>.filled(64, 'r').join(),
            'installationId': '0123456789abcdef0123456789abcdef',
            'clientType': 'flutter',
          });
          return _reply(req, 200, {
            'accessToken': 'rotated-access',
            'refreshToken': List<String>.filled(64, 's').join(),
            'expiresAt': '2026-12-01T12:00:00Z',
          });
        }
        if (req.path == '/auth/sessions') {
          if (req.headers['Authorization'] == 'Bearer old-access') {
            return _reply(req, 401, {'code': 'AUTH_TOKEN_INVALID'});
          }
          expect(req.headers['Authorization'], 'Bearer rotated-access');
          return _reply(req, 200, [_sessionRecord]);
        }
        return _reply(req, 404, {});
      }),
    );
    addTearDown(gateway.dispose);
    expect(await gateway.listActiveSessions(), hasLength(1));
    expect(refreshRequests, 1);
    expect(session.access, 'rotated-access');
    expect(session.refresh, List<String>.filled(64, 's').join());
    expect(session.identityRevision, 0);
  });

  test('Invalid Refresh contract never sends a refresh token or clears valid credentials', () async {
    final session = _Session();
    var refreshRequests = 0;
    final gateway = FableAuthGateway(
      baseUri: Uri.parse('https://fable.test'),
      contract: _contract({
        'auth.sessions': _op('auth.sessions', 'GET', '/auth/sessions',
          requiresAuth: true),
        'auth.refresh': _op('auth.refresh', 'POST', '/not-the-refresh-route'),
      }),
      secureSession: session,
      client: _network((req) async {
        if (req.path != '/auth/sessions') refreshRequests++;
        return _reply(req, 401, {'code': 'AUTH_TOKEN_INVALID'});
      }),
    );
    addTearDown(gateway.dispose);
    await expectLater(gateway.listActiveSessions(), throwsStateError);
    expect(refreshRequests, 0);
    expect(session.access, 'old-access');
    expect(session.refresh, List<String>.filled(64, 'r').join());
  });
}

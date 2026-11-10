import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:fable_core/fable_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// RC160: real Flutter-package gateway over external public HTTPS.
/// This is deliberately a read-only, unauthenticated/invalid-Bearer test. The
/// checked-in contract is a structural test-project fixture, NOT a verified
/// live Backend project export. Never claim a signed-in mobile E2E from this.
const _liveAcceptance = bool.fromEnvironment(
  'FABLE_RC160_REAL_HTTPS',
  defaultValue: false,
);
final _staging = Uri.parse(
  'https://fable-rc151-free-ephemeral-api.onrender.com',
);

class _NonCredentialSession extends FableSecureSession {
  _NonCredentialSession() : super(namespace: 'rc160.live.negative.only');

  @override
  Future<String> installationId() async =>
      '8d6c4e9a761e4bca802047ae994e2f62';

  // This is not a real JWT and cannot identify any user. No native store
  // is ever read in the opt-in runner.
  @override
  Future<String?> get accessToken async => 'rc160.not.a.jwt';

  @override
  Future<String?> get refreshToken async => null;

  @override
  Future<bool> clearSessionIfIdentity(
    int expectedIdentity, {
    String? expectedAccessToken,
    String? expectedRefreshToken,
  }) async =>
      true;
}

Future<Map<String, dynamic>> _readAsset(String path) async {
  // Targeted CI executes from packages/fable_core; keep the standard
  // root Flutter test suite disabled by default and file access read-only.
  final first = File('../../assets/contracts/$path');
  final file = await first.exists() ? first : File('assets/contracts/$path');
  return jsonDecode(await file.readAsString()) as Map<String, dynamic>;
}

Future<FableContract> _fixtureContract() async {
  final contract = await _readAsset('contract.json');
  if ((contract['project'] as Map?)?['id'] != 'test-project') {
    throw StateError(
      'RC160 uses only the reusable source fixture; never treat a real '
      'project as an unverified cross-environment test.',
    );
  }
  final handoff = await _readAsset('flutter-handoff.json');
  final openApi = await _readAsset('openapi.json');
  final core = await _readAsset('mobile-core-operations.json');
  return FableContract.fromMaps(handoff, contract, openApi, mobileCore: core);
}

Dio _realDio() {
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 25),
      receiveTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 20),
      followRedirects: false,
      validateStatus: (status) => status != null && status < 500,
    ),
  );
  // GitHub hosted runners can require HTTPS_PROXY; preserve native
  // certificate checking. Never add badCertificateCallback or allow HTTP.
  dio.httpClientAdapter = IOHttpClientAdapter(
    createHttpClient: () => HttpClient()
      ..findProxy = HttpClient.findProxyFromEnvironment,
  );
  return dio;
}

void main() {
  test(
    'RC160 real UnifiedApiClient rejects invalid Bearer via public HTTPS',
    () async {
      // flutter_test blocks network by default to avoid accidental live tests.
      // This explicitly opt-in test restores the native HTTP stack only for
      // its own duration; ordinary CI tests remain offline and deterministic.
      final originalOverrides = HttpOverrides.global;
      HttpOverrides.global = null;
      addTearDown(() => HttpOverrides.global = originalOverrides);

      final catalog = await _fixtureContract();
      expect(catalog.projectName, 'fable-test');
      final expected = <String, String>{
        'account.me': '/auth/me/account',
        'auth.sessions': '/auth/sessions',
      };
      for (final item in expected.entries) {
        final op = catalog.require(item.key);
        expect(op.path, item.value);
        expect(op.method, 'GET');
        expect(op.requiresAuth, isTrue);
        expect(op.enforceAuth, isTrue);
      }

      for (final operationId in expected.keys) {
        final session = _NonCredentialSession();
        final dio = _realDio();
        var dispatched = 0;
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              // Fail before sending anything to the wrong destination or a
              // method that might mutate data. Only an invalid JWT is sent.
              if (options.uri.origin != _staging.origin ||
                  options.uri.scheme != 'https' ||
                  options.method != 'GET' ||
                  options.headers.keys.any(
                    (key) => const {
                      'cookie',
                      'proxy-authorization',
                      'x-api-key',
                    }.contains(key.toLowerCase()),
                  )) {
                handler.reject(
                  DioException(
                    requestOptions: options,
                    error: StateError('RC160 blocked unsafe network request'),
                  ),
                );
                return;
              }
              dispatched++;
              handler.next(options);
            },
          ),
        );
        final gateway = UnifiedApiClient(
          baseUri: _staging,
          contract: catalog,
          session: session,
          client: dio,
          retryPolicy: const FableRetryPolicy(
            maxReadRetries: 1,
            baseDelay: Duration(milliseconds: 100),
          ),
        );
        try {
          await expectLater(
            gateway.execute(operationId),
            throwsA(
              isA<FableApiException>().having(
                (exception) => exception.status,
                'HTTP status',
                401,
              ),
            ),
          );
          expect(dispatched, 1, reason: 'only one invalid-Bearer GET allowed');
          // Never log the request headers, tokens or installations.
          // The checked-in fixture was NOT promoted to a real project.
          // ignore: avoid_print
          print('RC160_FLUTTER_GATEWAY_HTTPS_OK: $operationId HTTP 401');
        } finally {
          gateway.dispose();
        }
      }
      // ignore: avoid_print
      print(
        'RC160_FLUTTER_GATEWAY_EXTERNAL_PASS: 2 real Flutter-package '
        'gateway operations over validated HTTPS; invalid Bearer rejected; '
        'test-project fixture only, no live credentials or device login.',
      );
    },
    skip: !_liveAcceptance,
    timeout: const Timeout(Duration(minutes: 4)),
  );
}

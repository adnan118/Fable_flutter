import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fable_core/fable_core.dart';

/// In-memory identity store: the gateways should never need platform plugins
/// during contract / concurrency tests. Native storage is tested on devices.
class _Session extends FableSecureSession {
  String? token = 'old-access';
  String? refresh = List<String>.filled(64, 'r').join();
  @override int identityRevision = 0;
  @override Future<String?> get accessToken async => token;
  @override Future<String?> get refreshToken async => refresh;
  @override Future<String> installationId() async => '0123456789abcdef0123456789abcdef';
  @override Future<bool> clearSessionIfIdentity(int expectedIdentity, {String? expectedAccessToken, String? expectedRefreshToken}) async {
    if (expectedIdentity != identityRevision ||
        (expectedAccessToken != null && expectedAccessToken != token) ||
        (expectedRefreshToken != null && expectedRefreshToken != refresh)) return false;
    identityRevision++;
    token = null;
    refresh = null;
    return true;
  }
  @override Future<void> clearSession() async {
    await clearSessionIfIdentity(identityRevision);
  }
  @override Future<bool> replaceTokensIfIdentity({required int expectedIdentity,
      required String accessToken, String? refreshToken}) async {
    if (expectedIdentity != identityRevision) return false;
    identityRevision++;
    token = accessToken;
    refresh = refreshToken;
    return true;
  }
  @override Future<void> replaceTokens({required String accessToken, String? refreshToken}) async {
    await replaceTokensIfIdentity(expectedIdentity: identityRevision,
      accessToken: accessToken, refreshToken: refreshToken);
  }
  @override Future<bool> saveTokensIfIdentity({required int expectedIdentity,
      required String accessToken, String? refreshToken, String? expectedRefreshToken}) async {
    if (expectedIdentity != identityRevision ||
        (expectedRefreshToken != null && expectedRefreshToken != refresh)) return false;
    token = accessToken;
    if (refreshToken != null) refresh = refreshToken;
    return true;
  }
}

Dio _intercept(Future<Response<dynamic>> Function(RequestOptions) invoke) {
  final dio = Dio();
  dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) async {
    try { handler.resolve(await invoke(options)); }
    catch (error) { handler.reject(DioException(requestOptions: options, error: error)); }
  }));
  return dio;
}
Response<dynamic> _response(RequestOptions req, int status, [Object? data]) =>
    Response<dynamic>(requestOptions: req, statusCode: status, data: data ?? <String,dynamic>{});

void main() {
  test('Fable late logout cannot delete credentials for a newer account', () async {
    final session = _Session();
    final arrived = Completer<void>();
    final resume = Completer<void>();
    final dio = _intercept((request) async {
      if (request.path == '/auth/logout') {
        arrived.complete();
        await resume.future;
        return _response(request, 200);
      }
      return _response(request, 404);
    });
    final contract = FableContract(contractHash: List<String>.filled(64, 'a').join(),
      projectName: 'test', selectionMode: 'explicit', featureIds: const <String>{},
      operations: <String,FableOperation>{
        'auth.logout': const FableOperation('auth.logout','POST','/auth/logout','hash',
          requiresAuth: true, enforceAuth: true),
      });
    final gateway = FableAuthGateway(baseUri: Uri.parse('https://fable.example.test'),
      contract: contract, secureSession: session, client: dio);
    addTearDown(gateway.dispose);
    final logout = gateway.logout();
    await arrived.future;
    await session.replaceTokens(accessToken: 'new-account', refreshToken: List<String>.filled(64, 's').join());
    resume.complete();
    expect(await logout, false); // Old response belongs to an invalidated identity.
    expect(session.token, 'new-account');
    expect(session.refresh, List<String>.filled(64, 's').join());
  });

  test('A rejected old Fable refresh cannot sign out a newly logged-in account', () async {
    final session = _Session();
    final refreshArrived = Completer<void>();
    final resumeRefresh = Completer<void>();
    final dio = _intercept((request) async {
      if (request.path == '/auth/sessions') return _response(request, 401);
      if (request.path == '/auth/refresh') {
        refreshArrived.complete();
        await resumeRefresh.future;
        return _response(request, 401);
      }
      return _response(request, 404);
    });
    final contract = FableContract(contractHash: List<String>.filled(64, 'a').join(),
      projectName: 'test', selectionMode: 'explicit', featureIds: const <String>{},
      operations: <String,FableOperation>{
        'auth.sessions': const FableOperation('auth.sessions','GET','/auth/sessions','hash',
          requiresAuth: true, enforceAuth: true),
        'auth.refresh': const FableOperation('auth.refresh','POST','/auth/refresh','hash',
          requiresAuth: false, enforceAuth: true),
      });
    final gateway = FableAuthGateway(baseUri: Uri.parse('https://fable.example.test'),
      contract: contract, secureSession: session, client: dio);
    addTearDown(gateway.dispose);
    final pending = gateway.sessions();
    await refreshArrived.future;
    await session.replaceTokens(accessToken: 'new-account', refreshToken: List<String>.filled(64, 's').join());
    resumeRefresh.complete();
    await expectLater(pending, throwsA(isA<FableApiException>()));
    expect(session.token, 'new-account');
    expect(session.refresh, List<String>.filled(64, 's').join());
  });

  test('An old refresh failure cannot clear a newer rotation in the SAME identity', () async {
    final session = _Session();
    final refreshArrived = Completer<void>();
    final resumeRefresh = Completer<void>();
    final dio = _intercept((request) async {
      if (request.path == '/auth/sessions') return _response(request, 401);
      if (request.path == '/auth/refresh') {
        refreshArrived.complete();
        await resumeRefresh.future;
        return _response(request, 401);
      }
      return _response(request, 404);
    });
    final contract = FableContract(contractHash: List<String>.filled(64, 'a').join(),
      projectName: 'test', selectionMode: 'explicit', featureIds: const <String>{},
      operations: <String,FableOperation>{
        'auth.sessions': const FableOperation('auth.sessions','GET','/auth/sessions','hash',
          requiresAuth: true, enforceAuth: true),
        'auth.refresh': const FableOperation('auth.refresh','POST','/auth/refresh','hash',
          requiresAuth: false, enforceAuth: true),
      });
    final gateway = FableAuthGateway(baseUri: Uri.parse('https://fable.example.test'),
      contract: contract, secureSession: session, client: dio);
    addTearDown(gateway.dispose);
    final pending = gateway.sessions();
    await refreshArrived.future;
    expect(await session.saveTokensIfIdentity(expectedIdentity: session.identityRevision,
      expectedRefreshToken: List<String>.filled(64, 'r').join(),
      accessToken: 'already-rotated',
      refreshToken: List<String>.filled(64, 's').join()), true);
    resumeRefresh.complete();
    await expectLater(pending, throwsA(isA<FableApiException>()));
    expect(session.token, 'already-rotated');
    expect(session.refresh, List<String>.filled(64, 's').join());
    expect(session.identityRevision, 0); // Token rotation does not switch accounts.
  });

  test('Other backend late logout cannot delete newly logged-in account', () async {
    final operations = <Map<String,String>>[
      {'operationId':'session.login','method':'POST','path':'/signin','auth':'none'},
      {'operationId':'session.logout','method':'POST','path':'/signout','auth':'bearer'},
    ];
    final hash = sha256.convert(utf8.encode(jsonEncode(operations))).toString();
    final catalog = ExternalOperationCatalog.fromMap({
      'schemaVersion': 1, 'kind': 'fable.external-operation-catalog',
      'adapter':'custom','baseUrl':'https://other.example.test',
      'sourceHash':List<String>.filled(64, 'a').join(),'operationsHash':hash,'operations':operations,
    });
    final binding = ExternalAuthBinding.fromMap({
      'schemaVersion':1,'kind':'fable.external-auth-binding','adapter':'custom',
      'sourceHash':List<String>.filled(64, 'a').join(),'operationsHash':hash,
      'login': {
        'operationId':'session.login',
        'request': {'identifier':'email','password':'password'},
        'response': {'accessToken':'access'},
      },
      'logout': {'operationId':'session.logout'},
    }, catalog);
    final arrived = Completer<void>();
    final resume = Completer<void>();
    final dio = _intercept((request) async {
      arrived.complete();
      await resume.future;
      return _response(request, 200);
    });
    final session = _Session();
    final gateway = ExternalAuthGateway(catalog: catalog, mapping: binding,
      secureSession: session, client: dio);
    addTearDown(gateway.dispose);
    final pending = gateway.logout();
    await arrived.future;
    await session.replaceTokens(accessToken: 'new-account');
    resume.complete();
    expect(await pending, false);
    expect(session.token, 'new-account');
  });
}

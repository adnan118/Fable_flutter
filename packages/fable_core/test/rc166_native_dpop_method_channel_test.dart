import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fable_core/fable_core.dart';

const _native = MethodChannel('fable/dpop_native_v1');

String _proof() => [
  List<String>.filled(110,'a').join(),
  List<String>.filled(110,'b').join(),
  List<String>.filled(110,'c').join(),
].join('.');

class _OfflineSession extends FableSecureSession {
  _OfflineSession():super(namespace:'rc166.native.policy.local.test');
  @override Future<String> installationId() async =>
      'device-fixture-stable-but-not-credential';
}
const _testContractHash='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _policyCatalog=FableContract(
  contractHash:_testContractHash,
  projectName:'rc166-only-test-catalog',
  selectionMode:'explicit',
  featureIds:<String>{'auth'},
  operations:<String,FableOperation>{
    'AuthController_sessionPolicy':FableOperation('AuthController_sessionPolicy','GET',
      '/auth/session-policy',_testContractHash,requiresAuth:false,enforceAuth:true),
    'auth.login':FableOperation('auth.login','POST','/auth/login',_testContractHash,
      requiresAuth:false,enforceAuth:true),
  },
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_native, null);
  });

  test('RC166 native bridge sends exact method, htu, origin and ath token input', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_native,(call) async {
      calls.add(call);
      return _proof();
    });
    final signer = FableNativeDpopProofSigner(
      serverOrigin: Uri.parse('https://api.example.test'),
    );
    final actual = await signer.signProof(
      method:'GET',htu:Uri.parse('https://api.example.test/auth/me/account'),
      accessToken:List<String>.filled(96,'t').join(),
    );
    expect(actual,_proof());
    expect(calls.length,1);
    expect(calls.single.method,'sign');
    final sent = Map<String,dynamic>.from(calls.single.arguments as Map);
    expect(sent['method'],'GET');
    expect(sent['htu'],'https://api.example.test/auth/me/account');
    expect(sent['origin'],'https://api.example.test');
    expect(sent['accessToken'],List<String>.filled(96,'t').join());
  });

  test('RC166 public login proof never adds accessToken or fake ath', () async {
    Map<dynamic,dynamic>? params;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_native,(call) async {
      params=call.arguments as Map;
      return _proof();
    });
    final signer=FableNativeDpopProofSigner(
      serverOrigin:Uri.parse('https://api.example.test'));
    await signer.signProof(method:'POST',
      htu:Uri.parse('https://api.example.test/auth/login'));
    expect(params?.containsKey('accessToken'),false);
  });

  test('RC166 rejects different host, HTTP, query or fragment before native call', () async {
    var calls=0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_native,(call) async {
      calls++;return _proof();
    });
    final signer=FableNativeDpopProofSigner(
      serverOrigin:Uri.parse('https://api.example.test'));
    for(final bad in [
      'https://evil.example.test/account',
      'http://api.example.test/account',
      'https://api.example.test/account?token=1',
      'https://api.example.test/account#fragment',
    ]) {
      await expectLater(
        signer.signProof(method:'GET',htu:Uri.parse(bad)),
        throwsArgumentError,
      );
    }
    expect(calls,0);
  });

  test('RC166 forbids malformed origin and credentials', () async {
    expect(()=>FableNativeDpopProofSigner(
      serverOrigin:Uri.parse('http://api.example.test')),throwsArgumentError);
    expect(()=>FableNativeDpopProofSigner(
      serverOrigin:Uri.parse('https://api.example.test:443/path')),throwsArgumentError);
    final signer=FableNativeDpopProofSigner(
      serverOrigin:Uri.parse('https://api.example.test'));
    await expectLater(signer.signProof(method:'GET',
      htu:Uri.parse('https://api.example.test/account'),
      accessToken:'short'),throwsArgumentError);
  });

  test('RC166 device signer fails closed on missing hardware channel', () async {
    final signer=FableNativeDpopProofSigner(
      serverOrigin:Uri.parse('https://api.example.test'));
    await expectLater(
      signer.signProof(method:'GET',htu:Uri.parse('https://api.example.test/me')),
      throwsA(isA<MissingPluginException>()),
    );
  });

  test('RC166 malformed signed JWS never returns to API client', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_native,(call) async => 'not.a.jwt');
    final signer=FableNativeDpopProofSigner(
      serverOrigin:Uri.parse('https://api.example.test'));
    await expectLater(signer.signProof(
      method:'GET',htu:Uri.parse('https://api.example.test/me')),
      throwsStateError);
  });
  test('RC166 pinned native auth checks required runtime policy before signing login',() async {
    var policies=0,logins=0,signs=0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_native,(call) async {
      signs++;
      return _proof();
    });
    final dio=Dio();
    dio.interceptors.add(InterceptorsWrapper(onRequest:(options,handler) {
      if(options.path=='/auth/session-policy') {
        policies++;
        expect(options.headers.containsKey('DPoP'),false);
        return handler.resolve(Response<dynamic>(
          requestOptions:options,statusCode:200,data:<String,dynamic>{
            'mode':'multi','maxActive':5,'overflow':'revoke-oldest',
            'onePerInstallation':true,
            'dpop':{'flutter':'required','proofType':'dpop+jwt','algorithm':'ES256'},
          }));
      }
      if(options.path=='/auth/login') {
        logins++;
        expect(options.headers['DPoP'],isA<String>());
        return handler.resolve(Response<dynamic>(
          requestOptions:options,statusCode:200,data:<String,dynamic>{}));
      }
      handler.reject(DioException(requestOptions:options,
        type:DioExceptionType.badResponse));
    }));
    final client=FableApiClient(baseUri:Uri.parse('https://api.example.test'),
      contract:_policyCatalog,session:_OfflineSession(),
      dpopProofSigner:FableNativeDpopProofSigner(
        serverOrigin:Uri.parse('https://api.example.test')),client:dio);
    addTearDown(client.dispose);
    await client.request('auth.login',authorized:false,body:<String,dynamic>{});
    await client.request('auth.login',authorized:false,body:<String,dynamic>{});
    expect(policies,2);expect(logins,2);expect(signs,2);
  });

  test('RC166 pinned native login fails before proof if server DPoP is off',() async {
    var logins=0,signs=0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_native,(call) async {
      signs++;return _proof();
    });
    final dio=Dio();
    dio.interceptors.add(InterceptorsWrapper(onRequest:(options,handler) {
      if(options.path=='/auth/session-policy') {
        return handler.resolve(Response<dynamic>(
          requestOptions:options,statusCode:200,data:<String,dynamic>{
            'mode':'multi','maxActive':5,'overflow':'revoke-oldest',
            'onePerInstallation':true,
            'dpop':{'flutter':'off','proofType':'dpop+jwt','algorithm':'ES256'},
          }));
      }
      logins++;
      handler.reject(DioException(requestOptions:options,
        type:DioExceptionType.badResponse));
    }));
    final client=FableApiClient(baseUri:Uri.parse('https://api.example.test'),
      contract:_policyCatalog,session:_OfflineSession(),
      dpopProofSigner:FableNativeDpopProofSigner(
        serverOrigin:Uri.parse('https://api.example.test')),client:dio);
    addTearDown(client.dispose);
    await expectLater(client.request('auth.login',authorized:false),
      throwsA(isA<FableApiException>()));
    expect(logins,0);expect(signs,0);
  });

  test('RC166 duplicate OpenAPI operations for same public policy route are rejected',() async {
    var calls=0,signatures=0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_native,(call) async {
      signatures++;
      return _proof();
    });
    final duplicate=FableContract(
      contractHash:_testContractHash,
      projectName:'rc166-duplicate-operation',
      selectionMode:'explicit',
      featureIds:const <String>{'auth'},
      operations:<String,FableOperation>{
        ..._policyCatalog.operations,
        'AuthController_duplicateSessionPolicy':const FableOperation(
          'AuthController_duplicateSessionPolicy','GET','/auth/session-policy',
          _testContractHash,requiresAuth:false,enforceAuth:true),
      },
    );
    final dio=Dio();
    dio.interceptors.add(InterceptorsWrapper(onRequest:(options,handler) {
      calls++;
      return handler.resolve(Response<dynamic>(
        requestOptions:options,statusCode:200,data:<String,dynamic>{}));
    }));
    final client=FableApiClient(baseUri:Uri.parse('https://api.example.test'),
      contract:duplicate,session:_OfflineSession(),
      dpopProofSigner:FableNativeDpopProofSigner(
        serverOrigin:Uri.parse('https://api.example.test')),client:dio);
    addTearDown(client.dispose);
    await expectLater(client.request('auth.login',authorized:false),
      throwsA(isA<FableApiException>()));
    expect(calls,0);
    expect(signatures,0);
  });

  test('RC166 signed policy route marked private cannot satisfy public preflight',() async {
    var requests=0,signatures=0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_native,(call) async {
      signatures++;return _proof();
    });
    final denied=FableContract(
      contractHash:_testContractHash,
      projectName:'rc166-private-operation',
      selectionMode:'explicit',
      featureIds:const <String>{'auth'},
      operations:<String,FableOperation>{
        ..._policyCatalog.operations,
        'AuthController_sessionPolicy':const FableOperation(
          'AuthController_sessionPolicy','GET','/auth/session-policy',
          _testContractHash,requiresAuth:true,enforceAuth:true),
      },
    );
    final dio=Dio();
    dio.interceptors.add(InterceptorsWrapper(onRequest:(options,handler) {
      requests++;
      return handler.resolve(Response<dynamic>(
        requestOptions:options,statusCode:200,data:<String,dynamic>{}));
    }));
    final client=FableApiClient(baseUri:Uri.parse('https://api.example.test'),
      contract:denied,session:_OfflineSession(),
      dpopProofSigner:FableNativeDpopProofSigner(
        serverOrigin:Uri.parse('https://api.example.test')),client:dio);
    addTearDown(client.dispose);
    await expectLater(client.request('auth.login',authorized:false),
      throwsA(isA<FableApiException>()));
    expect(requests,0);
    expect(signatures,0);
  });

  test('RC166 server flips DPoP from required to off: next login fails closed',() async {
    var checks=0,logins=0,signs=0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_native,(call) async {
      signs++;return _proof();
    });
    final dio=Dio();
    dio.interceptors.add(InterceptorsWrapper(onRequest:(options,handler) {
      if(options.path=='/auth/session-policy') {
        checks++;
        return handler.resolve(Response<dynamic>(
          requestOptions:options,statusCode:200,data:<String,dynamic>{
            'mode':'multi','maxActive':5,'overflow':'revoke-oldest',
            'onePerInstallation':true,
            'dpop':{'flutter':checks==1?'required':'off',
              'proofType':'dpop+jwt','algorithm':'ES256'},
          }));
      }
      if(options.path=='/auth/login') {
        logins++;
        return handler.resolve(Response<dynamic>(
          requestOptions:options,statusCode:200,data:<String,dynamic>{}));
      }
      throw StateError('Unexpected network operation');
    }));
    final client=FableApiClient(baseUri:Uri.parse('https://api.example.test'),
      contract:_policyCatalog,session:_OfflineSession(),
      dpopProofSigner:FableNativeDpopProofSigner(
        serverOrigin:Uri.parse('https://api.example.test')),client:dio);
    addTearDown(client.dispose);
    await client.request('auth.login',authorized:false,body:<String,dynamic>{});
    await expectLater(client.request('auth.login',authorized:false,
        body:<String,dynamic>{}),throwsA(isA<FableApiException>()));
    expect(checks,2);expect(logins,1);expect(signs,1);
  });

}

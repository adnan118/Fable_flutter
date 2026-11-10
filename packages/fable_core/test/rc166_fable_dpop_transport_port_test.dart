import 'package:dio/dio.dart';
import 'package:fable_core/fable_core.dart';
import 'package:flutter_test/flutter_test.dart';

class _SignedProofPort implements FableDpopProofSigner {
  int calls = 0;
  final methods = <String>[];
  final uris = <Uri>[];
  final accessTokens = <String?>[];
  @override
  Future<String> signProof({
    required String method,
    required Uri htu,
    String? accessToken,
  }) async {
    calls++;
    methods.add(method);
    uris.add(htu);
    accessTokens.add(accessToken);
    // Fixture syntax ONLY: does not sign or expose a P-256 private key.
    return '${'a' * 110}.${'b' * 110}.${'c' * (110 + calls)}';
  }
}
class _Session extends FableSecureSession {
  _Session():super(namespace:'rc166.dpop.offline');
  @override Future<String> installationId() async => 'abc123abc123abc123abc123abc123ab';
  @override Future<String?> get accessToken async => 'fixture-user-token';
  @override Future<String?> get refreshToken async => null;
}
const _catalog = FableContract(
  contractHash:'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  operations:{
    'account.me': FableOperation('account.me','GET','/auth/me/account','hash',
      requiresAuth:true,enforceAuth:true),
    'auth.login': FableOperation('auth.login','POST','/auth/login','hash',
      requiresAuth:false,enforceAuth:true),
    'public.ping': FableOperation('public.ping','GET','/health','hash',
      requiresAuth:false,enforceAuth:true),
  },
  featureIds:<String>{},projectName:'rc166-test-not-live',
  selectionMode:'explicit',
);
Dio _mockDio(int Function(RequestOptions) respond) {
  final dio = Dio();
  dio.interceptors.add(InterceptorsWrapper(
    onRequest:(options,handler) => handler.resolve(Response<dynamic>(
      requestOptions:options,statusCode:respond(options),data:<String,dynamic>{})),
  ));
  return dio;
}

void main() {
  test('RC166 bound GET uses DPoP scheme and fresh proof with exact ath input',() async {
    final signer=_SignedProofPort();var seen=0;
    final client=FableApiClient(
      baseUri:Uri.parse('https://api.example.test'),contract:_catalog,
      session:_Session(),dpopProofSigner:signer,
      client:_mockDio((options) {
        seen++;
        expect(options.headers['Authorization'],'DPoP fixture-user-token');
        expect(options.headers['DPoP'],isA<String>());
        expect(options.headers['X-Installation-Id'],isNotEmpty);
        return 200;
      }));
    addTearDown(client.dispose);
    expect((await client.request('account.me')).statusCode,200);
    expect(seen,1);expect(signer.calls,1);
    expect(signer.methods.single,'GET');
    expect(signer.uris.single.toString(),'https://api.example.test/auth/me/account');
    expect(signer.accessTokens.single,'fixture-user-token');
  });

  test('RC166 public login gets proof without ath or Authorization',() async {
    final signer=_SignedProofPort();
    final client=FableApiClient(
      baseUri:Uri.parse('https://api.example.test'),contract:_catalog,
      session:_Session(),dpopProofSigner:signer,
      client:_mockDio((options) {
        expect(options.headers.containsKey('Authorization'),false);
        expect(options.headers['DPoP'],isA<String>());
        return 200;
      }));
    addTearDown(client.dispose);
    await client.request('auth.login',authorized:false,body:<String,dynamic>{});
    expect(signer.calls,1);expect(signer.methods.single,'POST');
    expect(signer.accessTokens.single,isNull);
  });

  test('RC166 no proof leaks onto unrelated public operation',() async {
    final signer=_SignedProofPort();
    final client=FableApiClient(
      baseUri:Uri.parse('https://api.example.test'),contract:_catalog,
      session:_Session(),dpopProofSigner:signer,
      client:_mockDio((options) {
        expect(options.headers.containsKey('DPoP'),false);
        expect(options.headers.containsKey('Authorization'),false);
        return 200;
      }));
    addTearDown(client.dispose);
    await client.request('public.ping',authorized:false);
    expect(signer.calls,0);
  });

  test('RC166 retry creates a NEW jti proof per GET request attempt',() async {
    final signer=_SignedProofPort();var attempts=0;final proofs=<String>[];
    final client=FableApiClient(
      baseUri:Uri.parse('https://api.example.test'),contract:_catalog,
      session:_Session(),dpopProofSigner:signer,
      retryPolicy:const FableRetryPolicy(
        maxReadRetries:1,baseDelay:Duration(milliseconds:1)),
      client:_mockDio((options) {
        attempts++;
        proofs.add(options.headers['DPoP']! as String);
        return attempts==1?503:200;
      }));
    addTearDown(client.dispose);
    expect((await client.request('account.me')).statusCode,200);
    expect(attempts,2);expect(signer.calls,2);
    expect(proofs[0],isNot(proofs[1]));
  });

  test('RC166 legacy Fable is still Bearer unless native signer injected',() async {
    final client=FableApiClient(
      baseUri:Uri.parse('https://api.example.test'),contract:_catalog,
      session:_Session(),
      client:_mockDio((options) {
        expect(options.headers['Authorization'],'Bearer fixture-user-token');
        expect(options.headers.containsKey('DPoP'),false);
        return 200;
      }));
    addTearDown(client.dispose);
    await client.request('account.me');
  });

  test('RC166 external Backend cannot receive the Fable-only signer',() {
    const c=_ExternalCatalog();
    expect(()=>UnifiedApiClient(baseUri:Uri.parse('https://external.test'),
      contract:c,session:_Session(),dpopProofSigner:_SignedProofPort(),
      adapter:ExternalTransportAdapter(catalog:c)),throwsArgumentError);
    expect(()=>ExternalTransportAdapter(catalog:c,
      publicHeaders:const <String,String>{'DPoP':'forbidden'}),throwsArgumentError);
  });

  test('RC166 injected Dio may not smuggle DPoP BaseOptions header',() {
    expect(()=>FableApiClient(baseUri:Uri.parse('https://api.example.test'),
      contract:_catalog,session:_Session(),dpopProofSigner:_SignedProofPort(),
      client:Dio(BaseOptions(headers:<String,dynamic>{'DPoP':'ambient'}))),
      throwsArgumentError);
  });
}
class _ExternalCatalog implements OperationCatalog {
  const _ExternalCatalog();
  @override bool get sendsInstallationId => false;
  @override bool supports(String id) => id=='public.ping';
  @override FableOperation require(String id) =>
    const FableOperation('public.ping','GET','/ping','hash',
      requiresAuth:false,enforceAuth:true);
}

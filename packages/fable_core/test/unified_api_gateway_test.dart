import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fable_core/fable_core.dart';

class _Catalog implements OperationCatalog {
  @override bool get sendsInstallationId => false;
  @override bool supports(String id) => const {'account.me','payment.write','public.ping'}.contains(id);
  @override FableOperation require(String id) {
    if (!supports(id)) throw StateError('Not in contract');
    return FableOperation(id,id=='payment.write'?'POST':'GET',
      id=='payment.write'?'/pay':id=='public.ping'?'/ping':'/me','test',
      requiresAuth:id!='public.ping',enforceAuth:true);
  }
}
class _Session extends FableSecureSession {
  String? token='old';
  bool cleared=false;
  @override Future<String?> get accessToken async => token;
  @override Future<String?> get refreshToken async => null;
  @override Future<void> clearSession() async {cleared=true;token=null;}
  @override Future<bool> clearSessionIfIdentity(int expectedIdentity, {String? expectedAccessToken, String? expectedRefreshToken}) async {
    if (expectedAccessToken != null && token != expectedAccessToken) return false;
    await clearSession();
    return true;
  }
  @override Future<String> installationId() async => '0123456789abcdef0123456789abcdef';
}
Dio _mockDio(int Function(RequestOptions) response) {
  final dio=Dio(BaseOptions(baseUrl:'https://untrusted.example.test'));
  dio.interceptors.add(InterceptorsWrapper(onRequest:(options,handler){
    handler.resolve(Response<dynamic>(requestOptions:options,statusCode:response(options),data:<String,dynamic>{}));
  }));
  return dio;
}
void main(){
  test('Laravel single bearer: no refresh, one request, 401 clears expired token', () async {
    final session=_Session();var hits=0;
    final client=FableApiClient(baseUri:Uri.parse('https://laravel.example.test'),
      contract:_Catalog(),session:session,
      client:_mockDio((options){hits++;expect(options.uri.host,'laravel.example.test');
        expect(options.headers['Authorization'],'Bearer old');
        expect(options.headers.containsKey('X-Installation-Id'),false);
        return 401;}));
    addTearDown(client.dispose);
    await expectLater(client.request('account.me'),throwsA(isA<FableApiException>()));
    expect(hits,1);expect(session.cleared,true);
  });
  test('Fable-style rotating bearer refresh retries GET once only',() async {
    final session=_Session();final catalog=_Catalog();var hits=0;var refreshes=0;
    final client=FableApiClient(baseUri:Uri.parse('https://fable.example.test'),
      contract:catalog,session:session,
      adapter:ExternalTransportAdapter(catalog:catalog,sessionMode:BackendSessionMode.rotatingBearer),
      refreshSession:() async {refreshes++;session.token='new';return true;},
      client:_mockDio((options){hits++;return hits==1?401:200;}));
    addTearDown(client.dispose);
    final result=await client.request('account.me');
    expect(result.statusCode,200);expect(hits,2);expect(refreshes,1);
  });
  test('Never replay a payment/mutation after refreshing credentials',() async {
    final session=_Session();final catalog=_Catalog();var hits=0;var refreshes=0;
    final client=FableApiClient(baseUri:Uri.parse('https://fable.example.test'),
      contract:catalog,session:session,
      adapter:ExternalTransportAdapter(catalog:catalog,sessionMode:BackendSessionMode.rotatingBearer),
      refreshSession:() async {refreshes++;session.token='new';return true;},
      client:_mockDio((options){hits++;return 401;}));
    addTearDown(client.dispose);
    await expectLater(client.request('payment.write',body:{'amount':100}),
      throwsA(isA<FableApiException>().having((e)=>e.code,'code','session_refreshed_retry_manually')));
    expect(hits,1);expect(refreshes,1);expect(session.cleared,false);
  });
  test('Public operation never uses Bearer and cannot be forcibly authorized',() async {
    final session=_Session();final catalog=_Catalog();
    final client=FableApiClient(baseUri:Uri.parse('https://laravel.example.test'),
      contract:catalog,session:session,client:_mockDio((options){
        expect(options.headers.containsKey('Authorization'),false);return 200;}));
    addTearDown(client.dispose);
    expect((await client.request('public.ping')).statusCode,200);
    await expectLater(client.request('public.ping',authorized:true),throwsArgumentError);
  });
}

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fable_core/fable_core.dart';

class _Session extends FableSecureSession {
  String? token;
  String? refresh;
  @override int identityRevision = 0;
  @override Future<String> installationId() async => '0123456789abcdef0123456789abcdef';
  @override Future<String?> get accessToken async => token;
  @override Future<String?> get refreshToken async => refresh;
  @override Future<bool> replaceTokensIfIdentity({required int expectedIdentity,
      required String accessToken,String? refreshToken}) async {
    if(expectedIdentity != identityRevision)return false;
    identityRevision++;
    token=accessToken;refresh=refreshToken;
    return true;
  }
}
final _ops=<String,FableOperation>{
 'auth.login':const FableOperation('auth.login','POST','/auth/login','R3',requiresAuth:false,enforceAuth:true),
 'auth.2fa.login.request':const FableOperation('auth.2fa.login.request','POST','/auth/2fa/login/request','R3',requiresAuth:false,enforceAuth:true),
 'auth.2fa.login.complete':const FableOperation('auth.2fa.login.complete','POST','/auth/2fa/login/complete','R3',requiresAuth:false,enforceAuth:true),
};
FableContract _contract([Map<String,FableOperation>? operations])=>FableContract(
  contractHash:List<String>.filled(64,'a').join(),projectName:'test',selectionMode:'explicit',
  featureIds:const <String>{'auth'},operations:operations??_ops);
Dio _mock(Future<Response<dynamic>> Function(RequestOptions) respond){
 final dio=Dio();
 dio.interceptors.add(InterceptorsWrapper(onRequest:(request,handler)async{
  try{handler.resolve(await respond(request));}
  catch(error){handler.reject(DioException(requestOptions:request,error:error));}
 }));
 return dio;
}
Response<dynamic> _response(RequestOptions request,Object? data)=>Response<dynamic>(
 requestOptions:request,statusCode:200,data:{'data':data});

void main(){
 test('2FA cannot persist credentials before completion; completion is bound to identity',()async{
  final session=_Session();
  final calls=<String>[];
  final dio=_mock((request)async{
   calls.add(request.uri.path);
   if(request.uri.path=='/auth/login')return _response(request,{
     'requiresTwoFactor':true,'twoFactorToken':List<String>.filled(64,'t').join(),
     'methods':['EMAIL_OTP'], 'expiresAt':'2099-01-01T00:00:00Z'});
   if(request.uri.path=='/auth/2fa/login/request')return _response(request,{
     'challengeId':'11111111-1111-4111-8111-111111111111'});
   if(request.uri.path=='/auth/2fa/login/complete')return _response(request,{
     'accessToken':'new-access','refreshToken':List<String>.filled(64,'r').join()});
   throw StateError('Undeclared route');
  });
  final gateway=FableAuthGateway(baseUri:Uri.parse('https://example.test'),
    contract:_contract(),secureSession:session,client:dio);
  addTearDown(gateway.dispose);
  final login=await gateway.login(identifier:'someone@example.test',password:'password',platform:'android');
  expect(login.authenticated,false);expect(login.requiresTwoFactor,true);
  expect(session.token,isNull);
  final pending=login.secondFactor!;
  final id=await gateway.requestSecondFactor(pending,preferredChannel:'EMAIL');
  expect(session.token,isNull);
  await gateway.completeSecondFactor(pending,challengeId:id,code:'123456');
  expect(session.token,'new-access');
  expect(session.refresh,List<String>.filled(64,'r').join());
  expect(calls,['/auth/login','/auth/2fa/login/request','/auth/2fa/login/complete']);
 });
 test('missing 2FA contract rejects flow without guessing or creating a session',()async{
  final session=_Session();
  final dio=_mock((request)async=>_response(request,{
    'requiresTwoFactor':true,'twoFactorToken':List<String>.filled(64,'t').join()}));
  final gateway=FableAuthGateway(baseUri:Uri.parse('https://example.test'),
    contract:_contract({'auth.login':_ops['auth.login']!}),secureSession:session,client:dio);
  addTearDown(gateway.dispose);
  final login=await gateway.login(identifier:'a',password:'b',platform:'ios');
  await expectLater(gateway.requestSecondFactor(login.secondFactor!),throwsStateError);
  expect(session.token,isNull);
 });
 test('second factor for old identity is rejected after account switch',()async{
  final session=_Session();
  final dio=_mock((request)async=>_response(request,{
    'requiresTwoFactor':true,'twoFactorToken':List<String>.filled(64,'t').join()}));
  final gateway=FableAuthGateway(baseUri:Uri.parse('https://example.test'),
    contract:_contract(),secureSession:session,client:dio);
  addTearDown(gateway.dispose);
  final login=await gateway.login(identifier:'a',password:'b',platform:'ios');
  session.identityRevision++;
  await expectLater(gateway.requestSecondFactor(login.secondFactor!),throwsA(isA<FableApiException>()));
  expect(session.token,isNull);
 });
}

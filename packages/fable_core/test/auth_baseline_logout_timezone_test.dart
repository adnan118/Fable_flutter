import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fable_core/fable_core.dart';

/// لا نستخدم خزنة النظام ضمن اختبارات عقد Auth؛ الاختبار يتحقق من
/// التجريد نفسه، واختبار Secure Storage الحقيقي يتم على الأجهزة.
class _Session extends FableSecureSession {
  String? token='session-A';
  int cleared=0;
  @override int identityRevision=0;
  @override Future<String?> get accessToken async=>token;
  @override Future<String?> get refreshToken async=>null;
  @override Future<String> installationId()async=>'0123456789abcdef0123456789abcdef';
  @override Future<bool> clearSessionIfIdentity(int expectedIdentity,{
    String? expectedAccessToken,String? expectedRefreshToken})async{
    if(expectedIdentity!=identityRevision||
       expectedAccessToken!=null&&expectedAccessToken!=token)return false;
    cleared++;
    identityRevision++;
    token=null;
    return true;
  }
}
FableContract _contract({bool timezone=true,bool logout=true})=>FableContract(
  contractHash:List<String>.filled(64,'a').join(),
  projectName:'rc82',selectionMode:'explicit',featureIds:const <String>{},
  operations:{
    if(logout)'auth.logout':const FableOperation(
      'auth.logout','POST','/auth/logout','hash',
      requiresAuth:true,enforceAuth:true),
    if(timezone)'auth.session.timezone':const FableOperation(
      'auth.session.timezone','POST','/auth/session/timezone','hash',
      requiresAuth:true,enforceAuth:true),
  });
Dio _intercept(Future<Response<dynamic>> Function(RequestOptions) invoke){
  final dio=Dio();
  dio.interceptors.add(InterceptorsWrapper(onRequest:(req,handler)async{
    try{handler.resolve(await invoke(req));}
    catch(err){handler.reject(DioException(requestOptions:req,error:err));}
  }));
  return dio;
}
Response<dynamic> _response(RequestOptions req,Object? value) =>
  Response(requestOptions:req,statusCode:200,data:value);

void main(){
 test('revoked:false is not remote logout success, while local secrets are cleared',()async{
  final session=_Session();
  final gateway=FableAuthGateway(baseUri:Uri.parse('https://fable.test'),
    contract:_contract(),secureSession:session,client:_intercept((req)async{
      expect(req.method,'POST');
      expect(req.path,'/auth/logout');
      return _response(req,{'data':{'revoked':false,'clientActions':['DELETE_LOCAL_PUSH_TOKEN']}});
    }));
  addTearDown(gateway.dispose);
  expect(await gateway.logout(),false);
  expect(session.cleared,1);
  expect(session.token,isNull);
 });
 test('remote logout requires explicit revoked:true, not just HTTP 200',()async{
  final session=_Session();
  final gateway=FableAuthGateway(baseUri:Uri.parse('https://fable.test'),
    contract:_contract(),secureSession:session,client:_intercept((req)async=>
      _response(req,{'revoked':true,'sessionId':'550e8400-e29b-41d4-a716-446655440000'})));
  addTearDown(gateway.dispose);
  expect(await gateway.logout(),true);
  expect(session.cleared,1);
 });
 test('late logout cannot clear a newer user, even after a confirmed response',()async{
  final session=_Session();
  final started=Completer<void>(),finish=Completer<void>();
  final gateway=FableAuthGateway(baseUri:Uri.parse('https://fable.test'),
    contract:_contract(),secureSession:session,client:_intercept((req)async{
      started.complete();await finish.future;
      return _response(req,{'revoked':true});
    }));
  addTearDown(gateway.dispose);
  final pending=gateway.logout();
  await started.future;
  session.identityRevision++;
  session.token='session-B';
  finish.complete();
  expect(await pending,false);
  expect(session.token,'session-B');
  expect(session.cleared,0);
 });
 test('verified timezone POST keeps server as IANA authority and confirms payload',()async{
  final session=_Session();
  var calls=0;
  final gateway=FableAuthGateway(baseUri:Uri.parse('https://fable.test'),
    contract:_contract(),secureSession:session,client:_intercept((req)async{
      calls++;
      expect(req.method,'POST');
      expect(req.path,'/auth/session/timezone');
      expect(req.headers['Authorization'],'Bearer session-A');
      expect(req.headers.containsKey('X-Fable-Managed-Entity-Id'),false);
      expect(req.data,{'timeZone':'Asia/Damascus'});
      return _response(req,{'data':{'updated':true,'timeZone':'Asia/Damascus'}});
    }));
  addTearDown(gateway.dispose);
  expect(await gateway.updateSessionTimeZone(' Asia/Damascus '),'Asia/Damascus');
  expect(calls,1);
  expect(session.token,'session-A');
  expect(session.cleared,0);
 });
 test('missing/invalid timezone operation does not issue network request',()async{
  final session=_Session();
  var calls=0;
  final gateway=FableAuthGateway(baseUri:Uri.parse('https://fable.test'),
    contract:_contract(timezone:false),secureSession:session,
    client:_intercept((req)async{
      calls++;return _response(req,{'updated':true});
    }));
  addTearDown(gateway.dispose);
  expect(gateway.supportsSessionTimeZone,false);
  await expectLater(gateway.updateSessionTimeZone('UTC'),throwsStateError);
  expect(calls,0);
 });
 test('invalid timezone input and false server reply are rejected',()async{
  final session=_Session();
  var calls=0;
  final gateway=FableAuthGateway(baseUri:Uri.parse('https://fable.test'),
    contract:_contract(),secureSession:session,client:_intercept((req)async{
      calls++;return _response(req,{'updated':true,'timeZone':'Europe/Berlin'});
    }));
  addTearDown(gateway.dispose);
  for(final bad in ['','../etc/passwd','Etc/../UTC','UTC\nAuthorization: x']){
    await expectLater(gateway.updateSessionTimeZone(bad),throwsArgumentError);
  }
  expect(calls,0);
  await expectLater(gateway.updateSessionTimeZone('Asia/Damascus'),throwsFormatException);
  expect(calls,1);
 });
 test('an outdated successful timezone response cannot affect a switched user',()async{
  final session=_Session();
  final entered=Completer<void>(),release=Completer<void>();
  final gateway=FableAuthGateway(baseUri:Uri.parse('https://fable.test'),
    contract:_contract(),secureSession:session,client:_intercept((req)async{
      entered.complete();await release.future;
      return _response(req,{'updated':true,'timeZone':'UTC'});
    }));
  addTearDown(gateway.dispose);
  final pending=gateway.updateSessionTimeZone('UTC');
  await entered.future;
  session.identityRevision++;
  session.token='session-B';
  release.complete();
  await expectLater(pending,throwsA(isA<FableApiException>()));
  expect(session.token,'session-B');
 });
}

import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fable_core/fable_core.dart';

class _Session extends FableSecureSession {
  String? token='old-account-access';
  @override int identityRevision=0;
  var clearCount=0;
  @override Future<String?> get accessToken async=>token;
  @override Future<String?> get refreshToken async=>null;
  @override Future<bool> clearSessionIfIdentity(int expectedIdentity,{
    String? expectedAccessToken,String? expectedRefreshToken,
  })async{
    if(expectedIdentity!=identityRevision ||
       expectedAccessToken!=null&&token!=expectedAccessToken)return false;
    clearCount++;identityRevision++;token=null;return true;
  }
}
FableContract _contract({bool supported=true})=>FableContract(
  contractHash:List<String>.filled(64,'a').join(),projectName:'rc81-test',selectionMode:'explicit',
  featureIds:const <String>{},
  operations: supported?const {
    'auth.change-password':FableOperation('auth.change-password',
      'POST','/auth/change-password','hash',
      requiresAuth:true,enforceAuth:true),
  }:const <String,FableOperation>{},
);
Dio _intercept(Future<Response<dynamic>> Function(RequestOptions request) call){
  final dio=Dio();
  dio.interceptors.add(InterceptorsWrapper(onRequest:(options,handler)async{
    try{handler.resolve(await call(options));}
    catch(error){handler.reject(DioException(requestOptions:options,error:error));}
  }));
  return dio;
}
Response<dynamic> _response(RequestOptions req,int code,Object? body)=>
  Response(requestOptions:req,statusCode:code,data:body);

void main(){
 test('verified change-password sends exactly two secret DTO keys and clears all-session local login',()async{
  final session=_Session();
  var hits=0;
  final gateway=FableAuthGateway(baseUri:Uri.parse('https://api.example.test'),
    contract:_contract(),secureSession:session,
    client:_intercept((request)async{
      hits++;
      expect(request.method,'POST');
      expect(request.path,'/auth/change-password');
      expect(request.headers['Authorization'],'Bearer old-account-access');
      expect(request.headers.containsKey('X-Fable-Managed-Entity-Id'),false);
      expect(request.data,{'currentPassword':'OLD@safe-987',
        'newPassword':'NEW@safe-012'});
      return _response(request,200,{'data':{'changed':true}});
    }));
  addTearDown(gateway.dispose);
  await gateway.changePassword(currentPassword:'OLD@safe-987',
    newPassword:'NEW@safe-012');
  expect(hits,1);expect(session.clearCount,1);
  expect(session.token,isNull);expect(session.identityRevision,1);
 });
 test('operation missing in project contract fails closed without request',()async{
   final session=_Session();
   var hits=0;
   final gateway=FableAuthGateway(baseUri:Uri.parse('https://api.example.test'),
     contract:_contract(supported:false),secureSession:session,
     client:_intercept((req)async{
       hits++;return _response(req,200,{'changed':true});
     }));
   addTearDown(gateway.dispose);
   await expectLater(gateway.changePassword(
     currentPassword:'old-password',newPassword:'new-password'),throwsStateError);
   expect(hits,0);expect(session.clearCount,0);
 });
 test('empty/equal passwords are refused; server remains source for complexity policy',()async{
   final session=_Session();
   var hits=0;
   final gateway=FableAuthGateway(baseUri:Uri.parse('https://api.example.test'),
     contract:_contract(),secureSession:session,
     client:_intercept((req)async{
       hits++;return _response(req,200,{'changed':true});
     }));
   addTearDown(gateway.dispose);
   await expectLater(gateway.changePassword(
     currentPassword:'same',newPassword:'same'),throwsArgumentError);
   await expectLater(gateway.changePassword(
     currentPassword:'',newPassword:'new'),throwsArgumentError);
   expect(hits,0);
 });
 test('rejected or malformed confirmation cannot falsely report password changed',()async{
   final session=_Session();
   var hits=0;
   final gateway=FableAuthGateway(baseUri:Uri.parse('https://api.example.test'),
     contract:_contract(),secureSession:session,
     client:_intercept((req)async{
       hits++;
       return _response(req,200,{'data':{'changed':false}});
     }));
   addTearDown(gateway.dispose);
   await expectLater(gateway.changePassword(
     currentPassword:'old',newPassword:'new'),throwsFormatException);
   expect(hits,1);expect(session.clearCount,0);
   expect(session.token,'old-account-access');
 });
 test('late password change success never clears different user credentials',()async{
   final session=_Session();
   final reached=Completer<void>(),release=Completer<void>();
   final gateway=FableAuthGateway(baseUri:Uri.parse('https://api.example.test'),
     contract:_contract(),secureSession:session,
     client:_intercept((req)async{
       reached.complete();await release.future;
       return _response(req,200,{'changed':true});
     }));
   addTearDown(gateway.dispose);
   final pending=gateway.changePassword(
     currentPassword:'old',newPassword:'new');
   await reached.future;
   session.identityRevision++;
   session.token='different-account-token';
   release.complete();
   await expectLater(pending,throwsA(isA<FableApiException>()));
   expect(session.clearCount,0);
   expect(session.token,'different-account-token');
 });
 test('network ambiguity is not retried as a sensitive mutation',()async{
   final session=_Session();
   var attempts=0;
   final gateway=FableAuthGateway(baseUri:Uri.parse('https://api.example.test'),
     contract:_contract(),secureSession:session,
     client:_intercept((req)async{
       attempts++;throw StateError('simulated interrupted connection');
     }));
   addTearDown(gateway.dispose);
   await expectLater(gateway.changePassword(
     currentPassword:'old',newPassword:'new'),throwsA(anything));
   expect(attempts,1);
   expect(session.clearCount,0);
 });
}

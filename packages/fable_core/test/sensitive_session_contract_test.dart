import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fable_core/fable_core.dart';

const id='550e8400-e29b-41d4-a716-446655440001';
const challenge='550e8400-e29b-41d4-a716-446655440002';
class MemorySession extends FableSecureSession {
  @override int identityRevision=0;
  String? access='demo-token';
  @override Future<String?> get accessToken async=>access;
  @override Future<String?> get refreshToken async=>null;
  @override Future<String> installationId()async=>'0123456789abcdef0123456789abcdef';
  @override Future<bool> clearSessionIfIdentity(int expectedIdentity,
      {String? expectedAccessToken,String? expectedRefreshToken})async{
    if(identityRevision!=expectedIdentity)return false;
    access=null;identityRevision++;return true;
  }
}
FableContract contract({bool otp=true,bool revoke=true})=>FableContract(contractHash:'hash',projectName:'test',selectionMode:'advisory',
    featureIds:const <String>{},operations:{
      if(revoke)'sessions.remove':const FableOperation('sessions.remove','POST',
        '/auth/sessions/{id}/revoke','hash',requiresAuth:true,enforceAuth:true),
      'sessions.all':const FableOperation('sessions.all','POST',
        '/auth/logout-all','hash',requiresAuth:true,enforceAuth:true),
      if(otp)'sensitive.send':const FableOperation('sensitive.send','POST',
        '/auth/otp/request','hash',requiresAuth:true,enforceAuth:true),
      if(otp)'sensitive.verify':const FableOperation('sensitive.verify','POST',
        '/auth/otp/verify','hash',requiresAuth:true,enforceAuth:true),
    });
Dio intercepted(Future<Response<dynamic>> Function(RequestOptions) reply){
  final dio=Dio();
  dio.interceptors.add(InterceptorsWrapper(onRequest:(options,handler)async{
    handler.resolve(await reply(options));
  }));
  return dio;
}
Response<dynamic> response(RequestOptions req,int code,Object body)=>
  Response<dynamic>(requestOptions:req,statusCode:code,data:body);

void main(){
  test('Revoke other device only after Backend SENSITIVE_ACTION OTP confirmation',()async{
    final seen=<RequestOptions>[];
    var revocations=0;
    final session=MemorySession();
    final client=FableAuthGateway(baseUri:Uri.parse('https://fable.example.test'),
      contract:contract(),secureSession:session,
      client:intercepted((req)async{
        seen.add(req);
        if(req.path=='/auth/otp/request')return response(req,200,{'challengeId':challenge});
        if(req.path=='/auth/otp/verify')return response(req,200,
          {'verified':true,'purpose':'SENSITIVE_ACTION','challengeId':challenge});
        if(req.path=='/auth/sessions/'+id+'/revoke'){
          revocations++;
          if(req.headers['X-Security-Challenge-Id']!=challenge)
            return response(req,403,{'code':'AUTH_RECENT_AUTH_REQUIRED'});
          return response(req,200,{'sessionId':id,'revoked':true});
        }
        return response(req,404,{'code':'not_found'});
      }));
    addTearDown(client.dispose);
    await expectLater(client.revokeOtherSession(id),throwsA(isA<FableApiException>()
      .having((e)=>e.code,'code','AUTH_RECENT_AUTH_REQUIRED')));
    final challengeId=await client.requestSensitiveActionOtp();
    expect(challengeId,challenge);
    final proof=await client.verifySensitiveActionOtp(challengeId,'123456');
    expect(await client.revokeOtherSession(id,proof:proof),true);
    expect(revocations,2);
    expect(seen.where((x)=>x.path.contains('/revoke')).first.headers.containsKey(
      'X-Security-Challenge-Id'),false);
    expect(seen.last.headers['X-Security-Challenge-Id'],challenge);
    expect(session.access,'demo-token');
  });
  test('Sensitive OTP cannot be used on other API routes or external transport',()async{
    final fable=contract();
    final session=MemorySession();
    final client=UnifiedApiClient(baseUri:Uri.parse('https://fable.example.test'),
      contract:fable,session:session);
    addTearDown(client.dispose);
    await expectLater(client.request('sensitive.send',
      securityChallengeId:challenge),throwsArgumentError);
    await expectLater(client.request('sessions.remove',
      path:{'id':id},securityChallengeId:'bad'),throwsArgumentError);
    await expectLater(client.request('sessions.remove',
      path:{'id':id},managedEntityId:id),throwsArgumentError);
    final fake=FableContract(contractHash:'hash',projectName:'test',
      selectionMode:'advisory',featureIds:const <String>{},
      operations:{'external.foo':const FableOperation('external.foo','POST',
        '/payment','hash',requiresAuth:true)});
    final other=UnifiedApiClient(baseUri:Uri.parse('https://fable.example.test'),
      contract:fake,session:session,adapter:ExternalTransportAdapter(
        catalog:fake,sessionMode:BackendSessionMode.singleBearer));
    addTearDown(other.dispose);
    await expectLater(other.request('external.foo',
      securityChallengeId:challenge),throwsArgumentError);
  });
  test('A fresh logout-all revokes local identity only on server confirmation',()async{
    final session=MemorySession();
    final client=FableAuthGateway(baseUri:Uri.parse('https://fable.example.test'),
      contract:contract(),secureSession:session,
      client:intercepted((req)async{
        if(req.path=='/auth/logout-all')return response(req,200,
          {'revoked':2,'sessionIds':[id]});
        return response(req,404,{});
      }));
    addTearDown(client.dispose);
    expect(await client.revokeAllSessions(),2);
    expect(session.access,isNull);
    expect(session.identityRevision,1);
  });
  test('Missing revocation or OTP operations remain unavailable',()async{
    final client=FableAuthGateway(baseUri:Uri.parse('https://fable.example.test'),
      contract:contract(otp:false,revoke:false),secureSession:MemorySession());
    addTearDown(client.dispose);
    expect(client.canRevokeOtherSessions,false);
    expect(client.canRequestSensitiveProof,false);
    await expectLater(client.requestSensitiveActionOtp(),throwsStateError);
    await expectLater(client.revokeOtherSession(id),throwsStateError);
  });
}

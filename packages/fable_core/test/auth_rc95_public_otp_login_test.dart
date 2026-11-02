import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fable_core/fable_core.dart';

const challengeId='550e8400-e29b-41d4-a716-446655440014';
String get futureIso=>DateTime.now().toUtc()
  .add(const Duration(minutes:10)).toIso8601String();

class _Session extends FableSecureSession {
  _Session():super(namespace:'rc95.test.otp');
  @override int identityRevision=0;
  @override Future<String?> get accessToken async=>null;
  @override Future<String?> get refreshToken async=>null;
  @override Future<String> installationId()async=>'abcdef0123456789abcdef0123456789';
  bool saved=false;
  @override Future<bool> replaceTokensIfIdentity({
    required int expectedIdentity,required String accessToken,
    String? refreshToken})async {
    if(identityRevision!=expectedIdentity)return false;
    saved=true;identityRevision++;
    return true;
  }
}

FableContract _contract({bool badComplete=false})=>FableContract(
  contractHash:'rc95',projectName:'rc95',selectionMode:'advisory',
  featureIds:const {'auth'},operations:{
    'auth.otp.public.request':const FableOperation('auth.otp.public.request',
      'POST','/auth/otp/public/request','rc95',requiresAuth:false,enforceAuth:true),
    'auth.otp.public.verify':const FableOperation('auth.otp.public.verify',
      'POST','/auth/otp/public/verify','rc95',requiresAuth:false,enforceAuth:true),
    'auth.otp.login.complete':FableOperation('auth.otp.login.complete',
      'POST',badComplete?'/auth/web/otp/login/complete':
      '/auth/otp/login/complete','rc95',requiresAuth:false,enforceAuth:true),
  });

Dio _fake(List<RequestOptions> calls,
    Object Function(RequestOptions) reply) {
  final dio=Dio();
  dio.interceptors.add(InterceptorsWrapper(onRequest:(req,handler){
    calls.add(req);
    handler.resolve(Response(requestOptions:req,statusCode:200,data:reply(req)));
  }));
  return dio;
}
void main(){
  test('RC95 public LOGIN request, verify, complete stores only confirmed session',()async{
    final calls=<RequestOptions>[];
    final session=_Session();
    final gateway=FableAuthGateway(baseUri:Uri.parse('https://fable.test'),
      contract:_contract(),secureSession:session,client:_fake(calls,(req){
        if(req.path=='/auth/otp/public/request')return {
          'accepted':true,'deliveryStatus':'QUEUED',
          'challengeId':challengeId,'expiresAt':futureIso};
        if(req.path=='/auth/otp/public/verify')return {
          'verified':true,'purpose':'LOGIN','challengeId':challengeId};
        return {'accessToken':'mock-access','refreshToken':List.filled(64,'a').join(),
          'expiresAt':futureIso,'mustChangePassword':false};
      }));
    addTearDown(gateway.dispose);
    expect(gateway.canLoginWithPublicOtp,true);
    final challenge=await gateway.requestLoginOtp(identifier:'user@test.invalid');
    expect(session.saved,false);
    final proof=await gateway.verifyLoginOtp(challenge,'123456');
    expect(session.saved,false);
    final outcome=await gateway.completeLoginWithOtp(proof,platform:'ios');
    expect(outcome.authenticated,true);
    expect(outcome.mustChangePassword,false);
    expect(session.saved,true);
    expect((calls[0].data as Map)['purpose'],'LOGIN');
    expect((calls[1].data as Map)['challengeId'],challengeId);
    expect((calls[2].data as Map)['clientType'],'flutter');
    await expectLater(gateway.completeLoginWithOtp(proof,platform:'ios'),throwsStateError);
    expect(calls.length,3);
  });

  test('RC95 rejects wrong OTP purpose and never creates a session',()async{
    final calls=<RequestOptions>[];
    final session=_Session();
    final gateway=FableAuthGateway(baseUri:Uri.parse('https://fable.test'),
      contract:_contract(),secureSession:session,client:_fake(calls,(req)=>
      req.path.endsWith('/request')?
        {'accepted':true,'deliveryStatus':'QUEUED',
         'challengeId':challengeId,'expiresAt':futureIso}:
        {'verified':true,'purpose':'PASSWORD_RESET','challengeId':challengeId}));
    addTearDown(gateway.dispose);
    final pending=await gateway.requestLoginOtp(identifier:'user@test.invalid');
    await expectLater(gateway.verifyLoginOtp(pending,'123456'),throwsFormatException);
    expect(session.saved,false);
    expect(calls.length,2);
  });

  test('RC95 fails closed when LOGIN operation is replaced by WEB route',()async{
    final gateway=FableAuthGateway(baseUri:Uri.parse('https://fable.test'),
      contract:_contract(badComplete:true),secureSession:_Session());
    addTearDown(gateway.dispose);
    expect(gateway.canLoginWithPublicOtp,false);
    await expectLater(gateway.requestLoginOtp(identifier:'user@test.invalid'),
      throwsStateError);
  });

  test('RC95 rejects malformed session ACK after valid verification',()async{
    final session=_Session();
    final gateway=FableAuthGateway(baseUri:Uri.parse('https://fable.test'),
      contract:_contract(),secureSession:session,client:_fake([], (req){
        if(req.path.endsWith('/request'))return {
          'accepted':true,'deliveryStatus':'QUEUED',
          'challengeId':challengeId,'expiresAt':futureIso};
        if(req.path.endsWith('/verify'))return {
          'verified':true,'purpose':'LOGIN','challengeId':challengeId};
        return {'accessToken':'mock','refreshToken':'bad',
          'expiresAt':futureIso,'mustChangePassword':false};
      }));
    addTearDown(gateway.dispose);
    final pending=await gateway.requestLoginOtp(identifier:'user@test.invalid');
    final proof=await gateway.verifyLoginOtp(pending,'123456');
    await expectLater(gateway.completeLoginWithOtp(proof,platform:'android'),
      throwsFormatException);
    expect(session.saved,false);
  });
}

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fable_core/fable_core.dart';

const challenge='550e8400-e29b-41d4-a716-446655440002';
final futureExpiration=DateTime.now().toUtc().add(const Duration(minutes:5))
  .toIso8601String();

class MemorySession extends FableSecureSession {
  @override int identityRevision=0;
  @override Future<String?> get accessToken async=>null;
  @override Future<String?> get refreshToken async=>null;
  @override Future<String> installationId()async=>'0123456789abcdef0123456789abcdef';
}
FableContract resetContract({bool request=true,bool verify=true,bool reset=true,
  bool wrongAuth=false,bool wrongPath=false})=>
  FableContract(contractHash:'hash',projectName:'rc91',
    selectionMode:'advisory',featureIds:const <String>{'auth'},
    operations:{
      if(request)'auth.otp.public.request':FableOperation(
        'auth.otp.public.request','POST',
        wrongPath?'/auth/otp/request':'/auth/otp/public/request','hash',
        requiresAuth:wrongAuth,enforceAuth:true),
      if(verify)'auth.otp.public.verify':const FableOperation(
        'auth.otp.public.verify','POST','/auth/otp/public/verify','hash',
        requiresAuth:false,enforceAuth:true),
      if(reset)'auth.password.reset':const FableOperation(
        'auth.password.reset','POST','/auth/password/reset','hash',
        requiresAuth:false,enforceAuth:true),
    });
Dio intercepted(Future<Response<dynamic>> Function(RequestOptions) reply){
  final dio=Dio();
  dio.interceptors.add(InterceptorsWrapper(onRequest:(options,handler)async{
    handler.resolve(await reply(options));
  }));
  return dio;
}
Response<dynamic> response(RequestOptions options,int status,Object body)=>
  Response<dynamic>(requestOptions:options,statusCode:status,data:body);

void main(){
  test('RC91 request -> purpose-confirmed OTP -> reset has exact public routes and no session',()async{
    final requests=<RequestOptions>[];
    final session=MemorySession();
    final gateway=FableAuthGateway(baseUri:Uri.parse('https://api.fable.example'),
      contract:resetContract(),secureSession:session,
      client:intercepted((req)async{
        requests.add(req);
        if(req.path=='/auth/otp/public/request')return response(req,200,{
          'challengeId':challenge,'accepted':true,
          'deliveryStatus':'QUEUED','expiresAt':futureExpiration});
        if(req.path=='/auth/otp/public/verify')return response(req,200,{
          'verified':true,'challengeId':challenge,'purpose':'PASSWORD_RESET'});
        if(req.path=='/auth/password/reset')return response(req,200,{
          'changed':true,'sessionsRevoked':3,'twoFactorPreserved':true});
        return response(req,404,{});
      }));
    addTearDown(gateway.dispose);
    expect(gateway.canResetPasswordWithPublicOtp,true);
    final pending=await gateway.requestPasswordResetOtp(
      identifier:' user@example.test ',preferredChannel:'EMAIL');
    expect(pending.challengeId,challenge);
    final proof=await gateway.verifyPasswordResetOtp(pending,'123456');
    final result=await gateway.completePasswordReset(proof,
      newPassword:'new-backend-approved-password');
    expect(result.sessionsRevoked,3);
    expect(result.twoFactorPreserved,true);
    expect(session.identityRevision,0);
    expect(requests.map((x)=>x.path),[
      '/auth/otp/public/request','/auth/otp/public/verify','/auth/password/reset']);
    for(final req in requests){
      expect(req.method,'POST');
      expect(req.headers.containsKey('Authorization'),false);
      expect(req.headers.containsKey('Cookie'),false);
    }
    expect((requests[0].data as Map)['identifier'],'user@example.test');
    expect((requests[0].data as Map)['purpose'],'PASSWORD_RESET');
    expect((requests[0].data as Map).containsKey('installationId'),false);
    expect((requests[1].data as Map)['code'],'123456');
    expect((requests[2].data as Map)['newPassword'],'new-backend-approved-password');
  });

  test('RC91 malformed public request and false QUEUED/accepted never yield OTP',()async{
    final session=MemorySession();
    var requests=0;
    final gateway=FableAuthGateway(baseUri:Uri.parse('https://api.fable.example'),
      contract:resetContract(),secureSession:session,
      client:intercepted((req)async{
        requests++;
        return response(req,200,{'challengeId':challenge,'accepted':true,
          'deliveryStatus':'SENT','expiresAt':futureExpiration});
      }));
    addTearDown(gateway.dispose);
    await expectLater(gateway.requestPasswordResetOtp(identifier:' '),
      throwsArgumentError);
    await expectLater(gateway.requestPasswordResetOtp(
      identifier:'user',preferredChannel:'WHATSAPP'),throwsArgumentError);
    expect(requests,0);
    await expectLater(gateway.requestPasswordResetOtp(identifier:'user'),
      throwsFormatException);
    expect(requests,1);
  });

  test('RC91 refuses mismatched purpose, short OTP, old identity and wrong gateway',()async{
    final session=MemorySession();
    final seen=<String>[];
    final gateway=FableAuthGateway(baseUri:Uri.parse('https://api.fable.example'),
      contract:resetContract(),secureSession:session,
      client:intercepted((req)async{
        seen.add(req.path);
        if(req.path=='/auth/otp/public/request')return response(req,200,{
          'challengeId':challenge,'accepted':true,'deliveryStatus':'QUEUED',
          'expiresAt':futureExpiration});
        if(req.path=='/auth/otp/public/verify')return response(req,200,{
          'challengeId':challenge,'purpose':'LOGIN','verified':true});
        return response(req,200,{'changed':true,'sessionsRevoked':0,
          'twoFactorPreserved':false});
      }));
    addTearDown(gateway.dispose);
    final pending=await gateway.requestPasswordResetOtp(identifier:'user');
    await expectLater(gateway.verifyPasswordResetOtp(pending,'1234'),
      throwsArgumentError);
    expect(seen.length,1);
    await expectLater(gateway.verifyPasswordResetOtp(pending,'123456'),
      throwsFormatException);
    expect(seen.length,2);
    session.identityRevision++;
    await expectLater(gateway.verifyPasswordResetOtp(pending,'123456'),
      throwsStateError);
    expect(seen.length,2);
  });

  test('RC91 missing/wrong public auth contract fails closed before network',()async{
    for(final contract in [
      resetContract(request:false),resetContract(verify:false),
      resetContract(reset:false),resetContract(wrongAuth:true),
      resetContract(wrongPath:true),
    ]){
      var sent=0;
      final gateway=FableAuthGateway(baseUri:Uri.parse('https://api.fable.example'),
        contract:contract,secureSession:MemorySession(),
        client:intercepted((req)async{
          sent++;
          return response(req,200,{});
        }));
      expect(gateway.canResetPasswordWithPublicOtp,false);
      if(!contract.operations.containsKey('auth.otp.public.request')||
        contract.operations['auth.otp.public.request']?.path!='/auth/otp/public/request'||
        contract.operations['auth.otp.public.request']?.requiresAuth==true){
        await expectLater(gateway.requestPasswordResetOtp(identifier:'user'),
          throwsStateError);
      }
      expect(sent,0);
      gateway.dispose();
    }
  });

  test('RC91 sensitive-action OTP uses 6–10 while 2FA login DTO is separate',()async{
    final session=MemorySession();
    final contract=FableContract(contractHash:'hash',projectName:'rc91',
      selectionMode:'advisory',featureIds:const <String>{'auth'},
      operations:{
        'auth.otp.request':const FableOperation('auth.otp.request','POST',
          '/auth/otp/request','hash',requiresAuth:true,enforceAuth:true),
        'auth.otp.verify':const FableOperation('auth.otp.verify','POST',
          '/auth/otp/verify','hash',requiresAuth:true,enforceAuth:true),
      });
    final gateway=FableAuthGateway(baseUri:Uri.parse('https://api.fable.example'),
      contract:contract,secureSession:session);
    addTearDown(gateway.dispose);
    await expectLater(gateway.verifySensitiveActionOtp(challenge,'1234'),
      throwsArgumentError);
  });
}

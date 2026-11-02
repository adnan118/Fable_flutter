import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fable_core/fable_core.dart';

const account='550e8400-e29b-41d4-a716-446655440012';
const recentChallenge='550e8400-e29b-41d4-a716-446655440013';
String get futureIso=>DateTime.now().toUtc()
  .add(const Duration(minutes:5)).toIso8601String();

class Session extends FableSecureSession {
  @override int identityRevision=0;
  @override Future<String?> get accessToken async=>'rc93-session';
  @override Future<String?> get refreshToken async=>null;
  @override Future<String> installationId()async=>'abcdef0123456789abcdef0123456789';
}
FableContract contract({bool fable=true,bool guarded=true})=>
  FableContract(contractHash:'hash',projectName:'rc93',
    selectionMode:'advisory',featureIds:const <String>{'auth'},
    operations:{
      'auth.otp.request':FableOperation('auth.otp.request','POST',
        '/auth/otp/request','hash',requiresAuth:true,enforceAuth:guarded),
      'auth.otp.verify':FableOperation('auth.otp.verify','POST',
        '/auth/otp/verify','hash',requiresAuth:true,enforceAuth:guarded),
      'auth.2fa.status':FableOperation('auth.2fa.status','GET',
        fable?'/auth/2fa/status':'/other/2fa/status','hash',
        requiresAuth:true,enforceAuth:guarded),
      'auth.2fa.enable':FableOperation('auth.2fa.enable','POST',
        '/auth/2fa/enable','hash',requiresAuth:true,enforceAuth:guarded),
      'auth.2fa.disable':FableOperation('auth.2fa.disable','POST',
        '/auth/2fa/disable','hash',requiresAuth:true,enforceAuth:guarded),
      'auth.contact.email.change':FableOperation('auth.contact.email.change',
        'POST','/auth/contact/email/change','hash',
        requiresAuth:true,enforceAuth:guarded),
      'auth.contact.phone.change':FableOperation('auth.contact.phone.change',
        'POST','/auth/contact/phone/change','hash',
        requiresAuth:true,enforceAuth:guarded),
    });

Dio intercepted(Future<Response<dynamic>> Function(RequestOptions) send) {
  final dio=Dio();
  dio.interceptors.add(InterceptorsWrapper(onRequest:(req,handler)async{
    handler.resolve(await send(req));
  }));
  return dio;
}
Response<dynamic> ok(RequestOptions req,Object data)=>
  Response<dynamic>(requestOptions:req,statusCode:200,data:data);

Map<String,Object> sentOtp(String purpose,{String channel='EMAIL'})=> {
  'challengeId':account,'expiresAt':futureIso,'channel':channel,
  'transport':channel=='EMAIL'?'EMAIL':'SMS',
  'destination':channel=='EMAIL'?'t***@domain.test':'+123***78',
};
Map<String,Object> verifiedOtp(String purpose)=> {
  'verified':true,'challengeId':account,'purpose':purpose,
};

void main(){
  test('RC93 2FA status, purpose-specific request/verify and 2FA enable ACK',()async{
    final requests=<RequestOptions>[];
    final session=Session();
    final gateway=FableAuthGateway(baseUri:Uri.parse('https://api.fable.test'),
      contract:contract(),secureSession:session,
      client:intercepted((req)async{
        requests.add(req);
        if(req.path=='/auth/2fa/status')return ok(req,{
          'enabled':false,'enabledAt':null,'methods':['EMAIL_OTP']});
        if(req.path=='/auth/otp/request')return ok(req,sentOtp('TWO_FACTOR'));
        if(req.path=='/auth/otp/verify')return ok(req,verifiedOtp('TWO_FACTOR'));
        if(req.path=='/auth/2fa/enable')return ok(req,{
          'enabled':true,'enabledAt':futureIso,'revokedOtherSessions':2});
        return ok(req,{});
      }));
    addTearDown(gateway.dispose);
    expect(gateway.canManageTwoFactor,true);
    final status=await gateway.loadTwoFactorStatus();
    expect(status.enabled,false);
    expect(status.methods,['EMAIL_OTP']);
    final pending=await gateway.requestSecurityOtp(
      purpose:FableSecurityOtpPurpose.twoFactor);
    final proof=await gateway.verifySecurityOtp(pending,'123456');
    final update=await gateway.setTwoFactorEnabled(proof,enabled:true);
    expect(update.enabled,true);
    expect(update.revokedOtherSessions,2);
    expect(session.identityRevision,0);
    expect(requests.map((r)=>r.path),[
      '/auth/2fa/status','/auth/otp/request','/auth/otp/verify',
      '/auth/2fa/enable',
    ]);
    expect((requests[1].data as Map)['purpose'],'TWO_FACTOR');
    expect((requests[1].data as Map).containsKey('destination'),false);
    expect((requests[3].data as Map)['challengeId'],account);
    expect(requests.every((r)=>r.headers.containsKey('Authorization')),true);
    await expectLater(gateway.setTwoFactorEnabled(proof,enabled:false),
      throwsStateError);
    expect(requests.length,4);
  });

  test('RC93 contact email OTP must be bound to new normalized destination',()async{
    final requests=<RequestOptions>[];
    final gateway=FableAuthGateway(baseUri:Uri.parse('https://api.fable.test'),
      contract:contract(),secureSession:Session(),
      client:intercepted((req)async{
        requests.add(req);
        if(req.path=='/auth/otp/request')return ok(req,sentOtp('CHANGE_EMAIL'));
        if(req.path=='/auth/otp/verify')return ok(req,verifiedOtp('CHANGE_EMAIL'));
        if(req.path=='/auth/contact/email/change')return ok(req,{
          'changed':true,'verified':true,'revokedOtherSessions':1});
        return ok(req,{});
      }));
    addTearDown(gateway.dispose);
    final pending=await gateway.requestSecurityOtp(
      purpose:FableSecurityOtpPurpose.changeEmail,
      newDestination:' NEW@Domain.Test ');
    expect((requests[0].data as Map)['destination'],'new@domain.test');
    final proof=await gateway.verifySecurityOtp(pending,'987654');
    await expectLater(gateway.changeVerifiedContact(proof,
      newDestination:'different@domain.test'),throwsArgumentError);
    expect(requests.length,2);
    final result=await gateway.changeVerifiedContact(proof,
      newDestination:' NEW@Domain.Test ');
    expect(result.purpose,FableSecurityOtpPurpose.changeEmail);
    expect(result.revokedOtherSessions,1);
    expect((requests.last.data as Map)['newEmail'],'new@domain.test');
    await expectLater(gateway.changeVerifiedContact(proof,
      newDestination:'new@domain.test'),throwsStateError);
  });

  test('RC93 contact phone requires new E.164 destination and optional recent-auth proof',()async{
    final requests=<RequestOptions>[];
    final gateway=FableAuthGateway(baseUri:Uri.parse('https://api.fable.test'),
      contract:contract(),secureSession:Session(),
      client:intercepted((req)async{
        requests.add(req);
        if(req.path=='/auth/otp/request'){
          if((req.data as Map)['purpose']=='SENSITIVE_ACTION')
            return ok(req,{'challengeId':recentChallenge});
          return ok(req,sentOtp('CHANGE_PHONE',channel:'PHONE'));
        }
        if(req.path=='/auth/otp/verify'){
          final security=(req.data as Map)['challengeId']==recentChallenge;
          return ok(req,security?{
            'verified':true,'challengeId':recentChallenge,
            'purpose':'SENSITIVE_ACTION',
          }:verifiedOtp('CHANGE_PHONE'));
        }
        return ok(req,{'changed':true,'verified':true,
          'revokedOtherSessions':3});
      }));
    addTearDown(gateway.dispose);
    await expectLater(gateway.requestSecurityOtp(
      purpose:FableSecurityOtpPurpose.changePhone,newDestination:'2345'),
      throwsArgumentError);
    final pending=await gateway.requestSecurityOtp(
      purpose:FableSecurityOtpPurpose.changePhone,
      newDestination:'+491234567890');
    final proof=await gateway.verifySecurityOtp(pending,'123456');
    final id=await gateway.requestSensitiveActionOtp();
    final recent=await gateway.verifySensitiveActionOtp(id,'123456');
    final result=await gateway.changeVerifiedContact(proof,
      newDestination:'+491234567890',securityProof:recent);
    expect(result.revokedOtherSessions,3);
    expect((requests.last.data as Map)['securityChallengeId'],recentChallenge);
    expect((requests.last.data as Map)['newPhone'],'+491234567890');
  });

  test('RC93 rejects purpose confusion, short OTP, mismatched 2FA payload',()async{
    final requests=<RequestOptions>[];
    final gateway=FableAuthGateway(baseUri:Uri.parse('https://api.fable.test'),
      contract:contract(),secureSession:Session(),
      client:intercepted((req)async{
        requests.add(req);
        if(req.path=='/auth/otp/request')return ok(req,sentOtp('CHANGE_EMAIL'));
        if(req.path=='/auth/otp/verify')return ok(req,
          verifiedOtp('TWO_FACTOR')); // wrong purpose: fail closed
        return ok(req,{'enabled':false,'revokedOtherSessions':0});
      }));
    addTearDown(gateway.dispose);
    final pending=await gateway.requestSecurityOtp(
      purpose:FableSecurityOtpPurpose.changeEmail,
      newDestination:'new@domain.test');
    await expectLater(gateway.verifySecurityOtp(pending,'1234'),
      throwsArgumentError);
    expect(requests.length,1);
    await expectLater(gateway.verifySecurityOtp(pending,'123456'),
      throwsFormatException);
    expect(requests.length,2);
  });

  test('RC93 blocks wrong operation/path/auth boundary and account switches',()async{
    for(final c in [contract(fable:false),contract(guarded:false)]){
      var calls=0;
      final gateway=FableAuthGateway(baseUri:Uri.parse('https://api.fable.test'),
        contract:c,secureSession:Session(),
        client:intercepted((req)async{
          calls++;return ok(req,{});
        }));
      addTearDown(gateway.dispose);
      expect(gateway.canManageTwoFactor,false);
      await expectLater(gateway.loadTwoFactorStatus(),throwsStateError);
      expect(calls,0);
    }
    final session=Session();
    final gateway=FableAuthGateway(baseUri:Uri.parse('https://api.fable.test'),
      contract:contract(),secureSession:session,
      client:intercepted((req)async=>ok(req,sentOtp('CHANGE_EMAIL'))));
    addTearDown(gateway.dispose);
    final pending=await gateway.requestSecurityOtp(
      purpose:FableSecurityOtpPurpose.changeEmail,
      newDestination:'another@domain.test');
    session.identityRevision++;
    await expectLater(gateway.verifySecurityOtp(pending,'123456'),
      throwsStateError);
  });
}

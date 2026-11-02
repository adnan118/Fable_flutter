import 'package:flutter_test/flutter_test.dart';
import 'package:fable_core/fable_core.dart';

FableContract _contract({bool corrupt=false})=>FableContract(
  contractHash:'rc95',projectName:'rc95',selectionMode:'advisory',
  featureIds:const {'auth'},operations:{
    'auth.2fa.login.request':FableOperation('auth.2fa.login.request','POST',
      corrupt?'/other/2fa/request':'/auth/2fa/login/request',
      'rc95',requiresAuth:false,enforceAuth:true),
    'auth.2fa.login.complete':const FableOperation('auth.2fa.login.complete','POST',
      '/auth/2fa/login/complete','rc95',requiresAuth:false,enforceAuth:true),
  });
void main(){
  test('RC95 verified social challenge becomes pending 2FA, not a session',(){
    final gateway=FableAuthGateway(baseUri:Uri.parse('https://fable.test'),
      contract:_contract());
    addTearDown(gateway.dispose);
    final data=<String,dynamic>{
      'twoFactorToken':List.filled(48,'x').join(),
      'methods':['EMAIL_OTP'],
      'expiresAt':DateTime.now().toUtc()
        .add(const Duration(minutes:5)).toIso8601String(),
    };
    final pending=gateway.adoptSocialSecondFactor(
      challengeData:data,platform:'ios');
    expect(pending.methods,['EMAIL_OTP']);
    expect(pending.expiresAt.isAfter(DateTime.now().toUtc()),true);
  });
  test('RC95 social 2FA cannot be downgraded to Other Backend route',(){
    final gateway=FableAuthGateway(baseUri:Uri.parse('https://fable.test'),
      contract:_contract(corrupt:true));
    addTearDown(gateway.dispose);
    expect(()=>gateway.adoptSocialSecondFactor(
      challengeData:{},platform:'ios'),throwsStateError);
  });
  test('RC95 rejects expired/mismatched social challenge',(){
    final gateway=FableAuthGateway(baseUri:Uri.parse('https://fable.test'),
      contract:_contract());
    addTearDown(gateway.dispose);
    expect(()=>gateway.adoptSocialSecondFactor(challengeData:{
      'twoFactorToken':List.filled(48,'x').join(),
      'methods':['TOTP'],
      'expiresAt':DateTime.now().toUtc()
        .add(const Duration(minutes:5)).toIso8601String(),
    },platform:'android'),throwsFormatException);
  });
}

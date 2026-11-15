import 'package:flutter_test/flutter_test.dart';
import 'package:fable_core/fable_core.dart';

// This source test validates only signed-route acceptance, not hardware
// WebAuthn, Android/iOS Associated Domains or an actual Backend response.
FableContract fixture({required String removal,
    required String registrationVerify, bool biometrics=true}) {
  FableOperation route(String id,String method,String path,
      {bool protected=true})=>
    FableOperation(id,method,path,List<String>.filled(64,'h').join(),
      requiresAuth:protected,enforceAuth:true);
  return FableContract(
    contractHash:List<String>.filled(64,'a').join(),
    operations:{
      'passkeys.list':route('passkeys.list','GET','/auth/passkeys'),
      'passkeys.remove':route('passkeys.remove','DELETE',removal),
      'passkeys.registration.options':route('passkeys.registration.options',
        'POST','/auth/passkeys/registration/options'),
      'passkeys.registration.verify':route('passkeys.registration.verify',
        'POST',registrationVerify),
      'auth.otp.request':route('auth.otp.request','POST','/auth/otp/request'),
      'auth.otp.verify':route('auth.otp.verify','POST','/auth/otp/verify'),
    },
    featureIds:const {'auth','access_control','biometrics'},
    projectName:'rc260',selectionMode:'explicit',
    frontendSetup:{
      'decisions':{'frontendFeatures':{
        'enabled':biometrics
          ?['auth','access_control','biometrics']
          :['auth','access_control'],
      }},
    },
  );
}

void main(){
  for(final syntax in [':','braced']){
    final removal=syntax==':'?'/auth/passkeys/:id':'/auth/passkeys/{id}';
    final verify=syntax==':'
      ?'/auth/passkeys/registration/:challengeId/verify'
      :'/auth/passkeys/registration/{challengeId}/verify';
    test('RC260 accepts only the verified $syntax Passkey route templates',(){
      final gateway=FableAuthGateway(baseUri:Uri.parse('https://api.example.org'),
        contract:fixture(removal:removal,registrationVerify:verify));
      try{
        expect(gateway.canManageAccountPasskeys,isTrue);
        expect(gateway.canRegisterNativePasskey,isTrue);
      }finally{gateway.dispose();}
    });
  }
  test('unselected biometrics remains disabled despite exported operations',(){
    final gateway=FableAuthGateway(baseUri:Uri.parse('https://api.example.org'),
      contract:fixture(removal:'/auth/passkeys/:id',
        registrationVerify:'/auth/passkeys/registration/:challengeId/verify',
        biometrics:false));
    try{
      expect(gateway.canManageAccountPasskeys,isFalse);
      expect(gateway.canRegisterNativePasskey,isFalse);
    }finally{gateway.dispose();}
  });
  test('mismatched Passkey removal path cannot enable credential deletion',(){
    final gateway=FableAuthGateway(baseUri:Uri.parse('https://api.example.org'),
      contract:fixture(removal:'/users/:id/delete',
        registrationVerify:'/auth/passkeys/registration/:challengeId/verify'));
    try{
      expect(gateway.canManageAccountPasskeys,isFalse);
      expect(gateway.canRegisterNativePasskey,isTrue);
    }finally{gateway.dispose();}
  });
}

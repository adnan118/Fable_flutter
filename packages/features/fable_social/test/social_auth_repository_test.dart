import 'package:flutter_test/flutter_test.dart';
import 'package:fable_core/fable_core.dart';
import 'package:fable_social/fable_social.dart';
import 'package:dio/dio.dart';

const digest='0123456789abcdef';
String seq(String char,int count)=>List<String>.filled(count,char).join();
class _Gateway implements BackendApiGateway {
  final calls=<String>[];
  final bodies=<Object?>[];
  Object? Function(String)? respond;
  @override Future<Response<dynamic>> execute(String operationId,{Map<String,dynamic>? path,
    Map<String,dynamic>? query,Object? body,CancelToken? cancelToken,String? ifMatch}) async {
    calls.add(operationId); bodies.add(body);
    return Response(requestOptions:RequestOptions(path:'/'),data:respond?.call(operationId));
  }
  @override void dispose() {}
}
class _Credentials implements FableSocialCredentialProvider {
  FableSocialCredential? credential;
  @override Future<FableSocialCredential?> obtain(FableSocialChallenge challenge) async => credential;
}
FableContract contract({bool insecure=false}) {
  final ops=<String,FableOperation>{};
  for(final entry in FableSocialOperations.fableIds.entries) {
    ops[entry.value]=FableOperation(entry.value,entry.key=='unlink'?'DELETE':'POST',
      entry.key=='unlink'?'/auth/social/{provider}':'/auth/social/${entry.key}',digest,
      requiresAuth:const {'googleLink','appleLink','unlink'}.contains(entry.key) ||
        (insecure && entry.key=='challenge'));
  }
  return FableContract(contractHash:digest,operations:ops,featureIds:const {'auth'},
    projectName:'test',selectionMode:'explicit');
}
void main() {
  test('Fable social bindings use only declared method, public status and paths',(){
    final bound=FableSocialOperations.fable(contract());
    expect(bound.require('challenge'),'auth.social.challenge');
    expect(bound.supports('appleLink'),true);
    expect(()=>FableSocialOperations.fable(contract(insecure:true)),throwsFormatException);
  });
  test('provider nonce mismatch denied before posting tokens',() async {
    final api=_Gateway()..respond=(id)=>{'provider':'google','state':seq('s',32),
      'nonce':seq('n',32),'expiresInMs':600000};
    final provider=_Credentials()..credential=const FableSocialCredential(
      provider:FableSocialProvider.google,nonce:'invalid',identityToken:'t-very-long-credential');
    final repository=FableSocialRepository(gateway:api,
      operations:FableSocialOperations.fable(contract()),
      session:FableSecureSession(namespace:'test.social-mismatch'),credentials:provider,
      adapter:const FableSocialBackendAdapter());
    await expectLater(repository.signIn(FableSocialProvider.google),throwsFormatException);
    expect(api.calls,['auth.social.challenge']);
  });
  test('two-factor response does not create authenticated session',() async {
    final api=_Gateway()..respond=(id)=>id=='auth.social.challenge'
      ? {'provider':'google','state':seq('s',32),'nonce':seq('n',32),'expiresInMs':600000}
      : {'requiresTwoFactor':true,'twoFactorToken':seq('x',40),'methods':['totp']};
    final provider=_Credentials()..credential=FableSocialCredential(
      provider:FableSocialProvider.google,nonce:seq('n',32),identityToken:seq('t',32));
    final repository=FableSocialRepository(gateway:api,
      operations:FableSocialOperations.fable(contract()),
      session:FableSecureSession(namespace:'test.social-2fa'),credentials:provider,
      adapter:const FableSocialBackendAdapter());
    final result=await repository.signIn(FableSocialProvider.google);
    expect(result?.signedIn,false);
    expect(result?.requiresTwoFactor,true);
    expect(api.calls,['auth.social.challenge','auth.social.google']);
    expect((api.bodies[1] as Map)['nonce'],seq('n',32));
  });
  test('Google / Apple credentials require original challenge and approved tokens',(){
    const codec=FableSocialBackendAdapter();
    final challenge=FableSocialChallenge(provider:FableSocialProvider.apple,
      state:seq('s',32),nonce:seq('n',32),expiresInMs:600000);
    expect(()=>codec.credentialRequest(FableSocialCredential(
      provider:FableSocialProvider.apple,nonce:seq('n',32),identityToken:seq('t',32)),challenge),
      throwsFormatException);
  });
}

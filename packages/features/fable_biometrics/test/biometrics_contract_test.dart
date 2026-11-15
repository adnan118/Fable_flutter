import 'package:flutter_test/flutter_test.dart';
import 'package:fable_core/fable_core.dart';

import 'package:fable_biometrics/fable_biometrics.dart';
class FakeCatalog implements OperationCatalog {
  FakeCatalog(this.ops);
  final Map<String,FableOperation> ops;
  @override bool get sendsInstallationId => false;
  @override bool supports(String id) => ops.containsKey(id);
  @override FableOperation require(String id) => ops[id] ?? (throw StateError('unlisted operation'));
}
void main(){
  FableContract fable({String optionsPath='/auth/passkeys/authentication/options',
      String verifyPath='/auth/passkeys/authentication/verify',
      bool enforceAuth=true})=>FableContract(
    contractHash:List<String>.filled(64,'a').join(),operations:{
      'passkeys.authentication.options':FableOperation('passkeys.authentication.options',
        'POST',optionsPath,List<String>.filled(64,'b').join(),requiresAuth:false,enforceAuth:enforceAuth),
      'passkeys.authentication.verify':FableOperation('passkeys.authentication.verify',
        'POST',verifyPath,List<String>.filled(64,'c').join(),requiresAuth:false,enforceAuth:enforceAuth),
    },featureIds:const {'auth','biometrics'},projectName:'project',
    selectionMode:'explicit');
  test('signed Fable public POST passkey options and verify required',(){
    final ops=FablePasskeyOperations.fable(fable());
    expect(ops.verifyId,'passkeys.authentication.verify');
  });
  test('Fable paths cannot be silently redirected or copied from Other Backend',(){
    expect(()=>FablePasskeyOperations.fable(FakeCatalog({})),throwsFormatException);
    expect(()=>FablePasskeyOperations.fable(
      fable(verifyPath:'/auth/reset-password')),throwsFormatException);
    expect(()=>FablePasskeyOperations.fable(
      fable(optionsPath:'/auth/fake-options')),throwsFormatException);
    expect(()=>FablePasskeyOperations.fable(
      fable(enforceAuth:false)),throwsFormatException);
  });
  test('a protected or GET passkey option is rejected',(){
    final c=FakeCatalog({'get':const FableOperation('get','GET','/options','h',requiresAuth:false),
      'verify':const FableOperation('verify','POST','/verify','h',requiresAuth:true)});
    expect(()=>FablePasskeyOperations.fromContract(c,optionsId:'get',verifyId:'verify'),throwsFormatException);
  });
}

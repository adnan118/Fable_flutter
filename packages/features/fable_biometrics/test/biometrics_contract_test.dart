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
  test('public POST passkey options and verify required',(){
    final c=FakeCatalog({
      'passkeys.authentication.options':const FableOperation('passkeys.authentication.options','POST','/auth/passkeys/authentication/options','h',requiresAuth:false),
      'passkeys.authentication.verify':const FableOperation('passkeys.authentication.verify','POST','/auth/passkeys/authentication/verify','h',requiresAuth:false)});
    final ops=FablePasskeyOperations.fable(c);
    expect(ops.verifyId,'passkeys.authentication.verify');
  });
  test('a protected or GET passkey option is rejected',(){
    final c=FakeCatalog({'get':const FableOperation('get','GET','/options','h',requiresAuth:false),
      'verify':const FableOperation('verify','POST','/verify','h',requiresAuth:true)});
    expect(()=>FablePasskeyOperations.fromContract(c,optionsId:'get',verifyId:'verify'),throwsFormatException);
  });
}

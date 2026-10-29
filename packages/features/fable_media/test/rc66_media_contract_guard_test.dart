import 'package:fable_core/fable_core.dart';
import 'package:fable_media/fable_media.dart';
import 'package:flutter_test/flutter_test.dart';

FableContract _catalog(Map<String,FableOperation> operations) => FableContract(
  contractHash: List.filled(64,'a').join(), operations: operations, featureIds: const <String>{'media'},
  projectName: 'verified-rc66-test', selectionMode: 'explicit',
);

FableOperation _op(String id,String method,{bool auth=true,bool enforced=true}) =>
    FableOperation(id,method,'/verified/$id',List.filled(64,'b').join(),requiresAuth:auth,enforceAuth:enforced);

void main() {
  test('RC66 seven media upload operations are all required and protected', () {
    const b=MediaUploadBindings.fable();
    final methods=<String,String>{
      b.prepare:'POST',b.status:'GET',b.chunk:'POST',b.partUrl:'POST',
      b.partAck:'POST',b.complete:'POST',b.abort:'DELETE',
    };
    expect(methods.length,7);
    final valid={for(final entry in methods.entries)entry.key:_op(entry.key,entry.value)};
    expect(() => b.verify(_catalog(valid)), returnsNormally);
    for(final key in methods.keys){
      expect(() => b.verify(_catalog({...valid}..remove(key))),throwsStateError,
        reason:'Missing $key must disable upload');
      expect(() => b.verify(_catalog({...valid,key:_op(key,methods[key]!,auth:false)})),
        throwsStateError,reason:'Public $key must never grant upload');
      expect(() => b.verify(_catalog({...valid,key:_op(key,methods[key]!,enforced:false)})),
        throwsStateError,reason:'Unenforced auth on $key must be rejected');
    }
    expect(() => b.verify(_catalog({...valid,b.abort:_op(b.abort,'POST')})),throwsStateError);
  });
}

import 'package:fable_core/fable_core.dart';
import 'package:fable_media/fable_media.dart';
import 'package:flutter_test/flutter_test.dart';

FableContract _catalog(Map<String,FableOperation> operations) => FableContract(
  contractHash: List.filled(64,'a').join(), operations: operations, featureIds: const <String>{'media'},
  projectName: 'verified-rc66-test', selectionMode: 'explicit',
);

const _realFableMediaPaths=<String,String>{
  'media.upload.prepare':'/media/uploads/prepare',
  'media.upload.status':'/media/uploads/{id}',
  'media.upload.chunk':'/media/uploads/{id}/chunk',
  'media.upload.partUrl':'/media/uploads/{id}/parts/{partNumber}/url',
  'media.upload.partAck':'/media/uploads/{id}/parts/{partNumber}/complete',
  'media.upload.complete':'/media/uploads/{id}/complete',
  'media.upload.abort':'/media/uploads/{id}',
};

FableOperation _op(String id,String method,{bool auth=true,bool enforced=true,
    String? path}) =>
    FableOperation(id,method,path ?? _realFableMediaPaths[id]!,
      List.filled(64,'b').join(),requiresAuth:auth,enforceAuth:enforced);

class _OtherCatalog implements OperationCatalog {
  const _OtherCatalog(this.operations);
  final Map<String,FableOperation> operations;
  @override bool get sendsInstallationId=>false;
  @override bool supports(String id)=>operations.containsKey(id);
  @override FableOperation require(String id){
    final op=operations[id];
    if(op==null)throw StateError('Missing Other operation: $id');
    return op;
  }
}

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
    // Fable contract is not valid merely because an operation ID, method
    // and Bearer auth flag match: another path could expose private chunks.
    expect(() => b.verify(_catalog({
      ...valid,b.chunk:_op(b.chunk,'POST',path:'/payments'),
    })),throwsStateError);
    expect(() => b.verify(_catalog({
      ...valid,b.prepare:_op(b.prepare,'POST',path:'//unsafe'),
    })),throwsStateError);
    expect(() => b.verify(_catalog({
      ...valid,b.complete:_op(b.complete,'POST',path:'/media/uploads/{id}/proxy'),
    })),throwsStateError);
    // Both {id} (OpenAPI) and :id (Nest) represent the SAME Fable API.
    expect(() => b.verify(_catalog({
      ...valid,b.chunk:_op(b.chunk,'POST',path:'/media/uploads/:id/chunk'),
    })),returnsNormally);
    // Other Backend retains independent, intentionally imported paths.
    expect(() => b.verify(_OtherCatalog({
      for(final entry in methods.entries)
        entry.key:_op(entry.key,entry.value,path:'/external/${entry.key}'),
    })),returnsNormally);
  });
}

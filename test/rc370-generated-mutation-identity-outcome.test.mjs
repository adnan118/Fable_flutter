import test from 'node:test';
import assert from 'node:assert/strict';
import {renderTypedFeature} from '../tools/render-typed-feature-rc116.mjs';

const HASH='a'.repeat(64),OP='b'.repeat(64),READ='c'.repeat(64);
const uuid={name:'id',type:'String',required:true,uuid:true};
const title={name:'title',type:'String',required:true};
const base={
  path:'/notes_ci/:id',params:['id'],resultKind:'single',
  contractHash:OP,fields:[uuid,title],bodyFields:[],
  sortFields:[],recordAccess:'owner:author',
};
function operation(method,managed){
  const operationId='notes_ci.'+
    (method==='POST'?'create':method==='PATCH'?'update':'delete');
  return {...base,operationId,
    className:'NotesCi'+(method==='POST'?'Create':method==='PATCH'?'Update':'Delete'),
    method,path:method==='POST'?'/notes_ci':'/notes_ci/:id',
    params:method==='POST'?[]:['id'],
    resultKind:method==='DELETE'?'confirmed-delete':'single',
    fields:method==='DELETE'?[]:[uuid,title],
    bodyFields:method==='DELETE'?[]:[{
      name:'title',type:'String',required:method==='POST',maxLength:191,
    }],
    ...(method==='POST'?{requiresIdempotency:true}:{
      preconditionRead:{operationId:'notes_ci.get',contractHash:READ,path:'/notes_ci/:id'},
    }),
    ...(managed?{managedScoped:true,recordAccess:'managed-entity:company'}:{}),
  };
}
function source(method,managed=false) {
  const op=operation(method,managed);
  const files=renderTypedFeature({
    featureId:'notes_ci',projectId:'rc369-project',
    contractHash:HASH,operations:[op],
  });
  const path='packages/features/fable_notes_ci/lib/src/data/fable_'+
    op.operationId.replaceAll('.','_')+'_repository.dart';
  const value=files.get(path);
  assert.ok(value,'Missing generated '+method+' adapter');
  return value;
}
test('RC370 signed POST cannot report identity loss as confirmed non-creation',()=>{
  for(const managed of [false,true]){
    const text=source('POST',managed);
    assert.match(text,/var mutationStarted=false;/);
    assert.match(text,/mutationStarted=true;\s*final response=await gateway\.execute/);
    assert.match(text,/if\(gateway\.session\.identityRevision!=identity\)/);
    assert.match(text,/if\(mutationStarted && const <TypedReadFailureKind>\{/);
    assert.match(text,/TypedReadFailureKind\.unauthenticated,/);
    assert.match(text,/TypedReadFailureKind\.invalidResponse,/);
    assert.match(text,/\.contains\(error\.kind\)\)/);
    assert.match(text,/TypedReadFailureKind\.outcomeUncertain/);
    assert.ok(text.indexOf('mutationStarted=true;') <
      text.indexOf('if(gateway.session.identityRevision!=identity)'));
  }
});
for(const method of ['PATCH','DELETE'])for(const managed of [false,true]){
  test('RC370 '+method+' '+(managed?'managed':'owner')+
    ' treats lost identity post-dispatch as unknown, but keeps preflight errors distinct',()=>{
    const text=source(method,managed);
    assert.match(text,/var mutationStarted=false;/);
    assert.match(text,/final fresh=await gateway.execute/);
    assert.match(text,/final ifMatch=etag\.substring/);
    assert.match(text,/mutationStarted=true;\s*final response=await gateway.execute/);
    assert.ok(text.indexOf('final ifMatch=etag.substring') <
      text.indexOf('mutationStarted=true;'));
    assert.match(text,/if\(gateway\.session\.identityRevision!=/);
    assert.match(text,/if\(mutationStarted && const <TypedReadFailureKind>\{/);
    assert.match(text,/TypedReadFailureKind\.unauthenticated,/);
    assert.match(text,/TypedReadFailureKind\.invalidResponse,/);
    assert.match(text,/\.contains\(e\.kind\)\)/);
    assert.match(text,/TypedReadFailureKind\.outcomeUncertain/);
    assert.doesNotMatch(text,/autoRetry|retryMutation/);
    if(managed)assert.match(text,/op\.recordAccess/);
  });
}
test('RC370 signed GET does not turn ordinary session loss into write uncertainty',()=>{
  const operation={...base,operationId:'notes_ci.get',className:'NotesCiGet',method:'GET'};
  const files=renderTypedFeature({featureId:'notes_ci',
    projectId:'rc369-project',contractHash:HASH,operations:[operation]});
  const text=files.get('packages/features/fable_notes_ci/lib/src/data/fable_notes_ci_get_repository.dart');
  assert.ok(text);
  assert.doesNotMatch(text,/var mutationStarted=false;/);
  assert.doesNotMatch(text,/mutationStarted=true;/);
  assert.doesNotMatch(text,/if\(mutationStarted && const <TypedReadFailureKind>/);
  assert.match(text,/TypedReadFailureKind\.unauthenticated/);
});

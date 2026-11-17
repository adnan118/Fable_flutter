import test from 'node:test';
import assert from 'node:assert/strict';
import {renderTypedFeature} from '../tools/render-typed-feature-rc116.mjs';

const H='a'.repeat(64), O='b'.repeat(64),G='c'.repeat(64);
const feature='notes_ci';
function output(method,managedScoped=false){
  const name='NotesCi'+(method==='POST'?'Create':method==='PATCH'?'Update':'Delete');
  const operationId='notes_ci.'+(method==='POST'?'create':method==='PATCH'?'update':'delete');
  const data={operationId,className:name,method,contractHash:O,
    path:method==='POST'?'/notes_ci':'/notes_ci/:id',
    params:method==='POST'?[]:['id'],
    resultKind:method==='DELETE'?'confirmed-delete':'single',
    fields:method==='DELETE'?[]:[{name:'title',type:'String',required:true,maxLength:191}],
    sortFields:[],
    bodyFields:method==='DELETE'?[]:[{
      name:'title',type:'String',required:method==='POST',maxLength:191,
    }],
    ...(method==='POST'?{requiresIdempotency:true}:{
      preconditionRead:{operationId:'notes_ci.get',contractHash:G,
        path:'/notes_ci/:id'},
    }),
    ...(managedScoped?{managedScoped:true,recordAccess:'managed-entity:company'}:{}),
  };
  const plan={featureId:feature,projectId:'rc363-source-fixture',
    contractHash:H,operations:[data]};
  const files=renderTypedFeature(plan);
  const path='packages/features/fable_notes_ci/lib/src/data/fable_'+operationId.replaceAll('.','_')+'_repository.dart';
  return files.get(path);
}

test('RC363 generated signed POST never reports a lost response as definitive failure',()=>{
  const source=output('POST');
  assert.ok(source);
  assert.match(source,/error.status==0\|\|error.status==408\|\|error.status>=500/);
  assert.match(source,/IDEMPOTENCY_RECOVERY_REQUIRED/);
  assert.match(source,/managed_entity_context_changed_discard_response/);
  assert.match(source,/on FormatException \{/);
  assert.match(source,/A malformed 2xx acknowledgement does not prove non-creation/);
  assert.match(source,/TypedReadFailureKind.outcomeUncertain/);
  assert.doesNotMatch(source,/retryPOST|repeatCreate/);
});

for(const method of ['PATCH','DELETE']){
  for(const managed of [false,true]){
    test('RC363 '+method+' '+(managed?'managed':'owner')+
      ' distinguishes precondition errors from uncertain mutation delivery',()=>{
      const source=output(method,managed);
      assert.ok(source);
      assert.match(source,/var mutationStarted=false;/);
      assert.match(source,/final fresh=await gateway.execute/);
      assert.match(source,/final ifMatch=etag.substring/);
      assert.ok(source.indexOf('mutationStarted=true;') >
        source.indexOf('final ifMatch=etag.substring'));
      assert.ok(source.indexOf('mutationStarted=true;') <
        source.lastIndexOf('final response=await gateway.execute'));
      assert.match(source,/mutationStarted && \(e.status==0\|\|e.status==408\|\|e.status>=500/);
      assert.match(source,/e.kind==TypedReadFailureKind.invalidResponse/);
      assert.match(source,/TypedReadFailureKind.outcomeUncertain/);
      assert.doesNotMatch(source,/retry\(/);
      if(managed)assert.match(source,/source.recordAccess/);
    });
  }
}

import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {renderTypedFeature} from '../tools/render-typed-feature-rc116.mjs';

const H='a'.repeat(64),O='b'.repeat(64),G='c'.repeat(64);
const file=path=>readFileSync(new URL('../'+path,import.meta.url),'utf8');
const identity={name:'id',type:'String',required:true,uuid:true};
const title={name:'title',type:'String',required:true};
function plan(ops) {
  return {featureId:'notes_ci',projectId:'rc364-fixture',
    contractHash:H,operations:ops};
}
const read=(idFields=[identity,title])=>({
  operationId:'notes_ci.get',className:'NotesCiGet',method:'GET',
  path:'/notes_ci/:id',params:['id'],resultKind:'single',
  contractHash:O,fields:idFields,sortFields:[],bodyFields:[],
});
const update=managedScoped=>({
  ...read(),method:'PATCH',operationId:'notes_ci.update',
  className:'NotesCiUpdate',
  bodyFields:[{name:'title',type:'String',required:false,maxLength:191}],
  preconditionRead:{operationId:'notes_ci.get',
    path:'/notes_ci/:id',contractHash:G},
  ...(managedScoped?{managedScoped:true,recordAccess:'managed-entity:company'}:{}),
});
const paged=()=>({
  operationId:'notes_ci.list.paginated',
  className:'NotesCiListPaginated',method:'GET',
  path:'/notes_ci',params:[],resultKind:'paginated-list',
  contractHash:O,fields:[identity,title],sortFields:[],bodyFields:[],
  supportsSearch:true,filters:[],
});
const root='packages/features/fable_notes_ci/lib/src/';

test('RC364 generated signed GET binds UUID result to requested record',()=>{
  const files=renderTypedFeature(plan([read()]));
  const source=files.get(root+'data/fable_notes_ci_get_repository.dart');
  assert.match(source,/entity\.id\.toLowerCase\(\)!=id\.toLowerCase\(\)/);
  assert.match(source,/Mismatched signed record identifier/);
  assert.ok(source.indexOf('final entity=') <
    source.indexOf('entity.id.toLowerCase()'));
  const legacy=renderTypedFeature(plan([read([title])]));
  assert.doesNotMatch(
    legacy.get(root+'data/fable_notes_ci_get_repository.dart'),
    /entity\.id\.toLowerCase/);
});

for(const managed of [false,true]){
  test('RC364 generated '+(managed?'managed':'owner')+
      ' PATCH cannot acknowledge a different UUID',()=>{
    const files=renderTypedFeature(plan([update(managed)]));
    const source=files.get(root+'data/fable_notes_ci_update_repository.dart');
    assert.ok(source);
    assert.match(source,/entity\.id\.toLowerCase\(\)!=id\.toLowerCase\(\)/);
    assert.match(source,/TypedReadFailureKind\.invalidResponse/);
    assert.match(source,/mutationStarted && e\.kind==TypedReadFailureKind\.invalidResponse/);
    assert.match(source,/TypedReadFailureKind\.outcomeUncertain/);
    if(managed) assert.match(source,/op\.recordAccess/);
  });
}

test('RC364 page DTO rejects empty-total rows and truncated/overfull signed pages',()=>{
  const files=renderTypedFeature(plan([paged()]));
  const source=files.get(root+'data/notes_ci_list_paginated_dto.dart');
  assert.ok(source);
  assert.match(source,/final remaining=\(meta\["total"\] as int\)/);
  assert.match(source,/input\.length!=\(remaining>20\?20:remaining\)/);
  assert.match(source,/input\.isNotEmpty/);
  assert.match(source,/Inconsistent signed page item count/);
  assert.match(source,/\(meta\['limit'\] as int\)!=20/);
});

test('RC364 mutable Dio origin/header check is reapplied after native signer awaits',()=>{
  const source=file('packages/fable_core/lib/src/fable_api.dart');
  const dart=file('packages/fable_core/test/rc364_mutable_dio_transport_boundary_test.dart');
  assert.match(source,/void _assertDioTransportStillPinned\(\)/);
  assert.match(source,/name\.startsWith\('x-fable-'\)/);
  assert.match(source,/'x-installation-id'/);
  assert.match(source,/\_dio\.options\.baseUrl != _baseUri\.origin/);
  const signing=source.indexOf('await signer.signProof(');
  const guard=source.indexOf('_assertDioTransportStillPinned();');
  const send=source.indexOf('final response = await _dio.request<dynamic>(');
  assert.ok(signing>=0&&guard>signing&&send>guard);
  assert.match(dart,/rejects changed Dio origin after credentials are pinned/);
  assert.match(dart,/injected Dio cannot add ambient credentials after constructor/);
  assert.match(dart,/transport still accepts benign public locale headers/);
  assert.match(dart,/expect\(sends,0/);
});

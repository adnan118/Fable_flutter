import test from 'node:test';
import assert from 'node:assert/strict';
import {renderTypedFeature} from '../tools/render-typed-feature-rc116.mjs';

const H='a'.repeat(64),O='b'.repeat(64);
const base={
  operationId:'notes_ci.list.paginated',className:'NotesCiListPaginated',
  method:'GET',path:'/notes_ci',params:[],contractHash:O,
  resultKind:'paginated-list',sortFields:[],filters:[],
  fields:[{name:'id',type:'String',required:true,uuid:true}],
  bodyFields:[],supportsSearch:true,
};
const root='packages/features/fable_notes_ci/';
const make=(op)=>renderTypedFeature({
  featureId:'notes_ci',projectId:'rc372-fixture',contractHash:H,
  operations:[op],
});
test('RC372 paginated generator ships Dart full-first-page and partial-last-page assertions',()=>{
  for(const supportsSearch of [true,false]){
    const files=make({...base,supportsSearch});
    const dtoTest=files.get(root+'test/notes_ci_list_paginated_dto_test.dart');
    const dto=files.get(root+'lib/src/data/notes_ci_list_paginated_dto.dart');
    assert.ok(dtoTest);assert.ok(dto);
    assert.match(dtoTest,/final template=Map<String,Object\?>\.from/);
    assert.match(dtoTest,/"page":1,"limit":20,"total":21,"totalPages":2/);
    assert.match(dtoTest,/List<Object\?>\.filled\(20,template\)/);
    assert.match(dtoTest,/items\.length,20/);
    assert.match(dtoTest,/"page":2,"limit":20,"total":21,"totalPages":2/);
    assert.match(dtoTest,/items\.length,1/);
    assert.match(dto,/input\.length!=\(remaining>20\?20:remaining\)/);
    assert.ok(dtoTest.indexOf('"page":1,"limit":20,"total":21') <
      dtoTest.indexOf('"page":2,"limit":20,"total":21'));
  }
});
test('RC372 paginated Dart tests cover truncation, overfill and empty total',()=>{
  const source=make(base).get(root+'test/notes_ci_list_paginated_dto_test.dart');
  assert.ok(source);
  assert.match(source,/json\["items"\]=<Object\?>\[template,template\];/);
  assert.match(source,/json\["items"\]=<Object\?>\[template\];/);
  assert.match(source,/json\["items"\]=<Object\?>\[\];/);
  assert.match(source,/"total":0,"totalPages":0/);
  assert.match(source,/\.items,isEmpty/);
  const failures=(source.match(/throwsFormatException/g)||[]).length;
  assert.ok(failures>=6,'Need multiple explicit failure fixtures');
  const afterZero=source.split('"total":0,"totalPages":0')[1];
  assert.ok(afterZero.includes('json["items"]=<Object?>[template];'));
  assert.ok(afterZero.includes('throwsFormatException'));
});
test('RC372 unpaginated generated Dart test maintains its own count rules',()=>{
  const op={...base,operationId:'notes_ci.list.unpaginated',
    className:'NotesCiListUnpaginated',resultKind:'unpaginated-list',
    supportsSearch:false};
  const output=make(op);
  const value=output.get(root+'test/notes_ci_list_unpaginated_dto_test.dart');
  assert.ok(value);
  assert.doesNotMatch(value,/RC372: real Dart assertions/);
  assert.match(value,/"mode":"unpaginated","count":501,"maxRows":5000/);
  assert.match(value,/List<Object\?>\.filled\(5001,template\)/);
  assert.match(value,/limitExceeded/);
});

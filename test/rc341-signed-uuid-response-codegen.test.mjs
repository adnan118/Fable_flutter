import test from 'node:test';
import assert from 'node:assert/strict';
import {renderTypedFeature} from '../tools/render-typed-feature-rc116.mjs';

function generated(kind) {
  const featureId='catalog_ci';
  const id=kind==='single'?'catalog_ci.get':'catalog_ci.list.unpaginated';
  const op={
    operationId:id,className:kind==='single'?'CatalogCiGet':'CatalogCiListUnpaginated',
    method:'GET',path:kind==='single'?'/catalog_ci/{id}':'/catalog_ci/all',
    contractHash:'b'.repeat(64),params:kind==='single'?['id']:[],
    fields:[
      {name:'id',type:'String',required:true,uuid:true},
      {name:'parentId',type:'String',required:false,uuid:true},
      {name:'title',type:'String',required:true},
    ],
    bodyFields:[],resultKind:kind,filters:[],sortFields:[],
  };
  const result=renderTypedFeature({featureId,
    projectId:'source-signed-uuid-fixture',contractHash:'a'.repeat(64),
    operations:[op]});
  const key=id.replaceAll('.','_');
  const root='packages/features/fable_catalog_ci/';
  return {
    dto:result.get(root+'lib/src/data/'+key+'_dto.dart'),
    fixture:result.get(root+'test/'+key+'_dto_test.dart'),
  };
}
test('RC341 only source-signed UUID values are checked beyond basic String type',()=>{
  for(const kind of ['single','unpaginated-list']){
    const {dto,fixture}=generated(kind);
    assert.ok(dto.includes('Invalid id UUID field'));
    assert.ok(dto.includes('Invalid parentId UUID field'));
    assert.ok(dto.includes('RegExp(r"^[0-9a-fA-F]{8}-'));
    assert.ok(!dto.includes('Invalid title UUID field'));
    assert.ok(fixture.includes('00000000-0000-4000-8000-000000000000'));
    assert.ok(fixture.includes('"title": "example"'));
  }
});
test('RC341 no automatic UUID rejection for an ordinary signed text identifier',()=>{
  const result=renderTypedFeature({
    featureId:'labels_ci',projectId:'source-fixture',
    contractHash:'a'.repeat(64),operations:[{
      operationId:'labels_ci.get',className:'LabelsCiGet',
      method:'GET',path:'/labels_ci/{id}',contractHash:'b'.repeat(64),
      params:['id'],fields:[{name:'id',type:'String',required:true}],
      bodyFields:[],resultKind:'single',
    }],
  });
  const dto=result.get('packages/features/fable_labels_ci/lib/src/data/labels_ci_get_dto.dart');
  assert.ok(!dto.includes('UUID field'));
  assert.ok(dto.includes('Invalid id DTO field'));
});

test('RC353 only RFC4122 v4 signed record UUIDs are accepted by generated DTO boundaries',()=>{
 const canonical=/^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-4[0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$/;
 assert.ok(canonical.test('00000000-0000-4000-8000-000000000000'));
 assert.ok(!canonical.test('00000000-0000-1000-8000-000000000000'));
 assert.ok(!canonical.test('00000000-0000-7000-8000-000000000000'));
 assert.ok(!canonical.test('00000000-0000-4000-c000-000000000000'));
 for(const kind of ['single','unpaginated-list']){
  const {dto}=generated(kind);
  assert.ok(dto.includes('-4[0-9a-fA-F]{3}-[89abAB]'));
  assert.ok(!dto.includes('-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'));
 }
});

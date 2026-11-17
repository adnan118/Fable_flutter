import test from 'node:test';
import assert from 'node:assert/strict';
import {renderTypedFeature} from '../tools/render-typed-feature-rc116.mjs';

const base='packages/features/fable_inventory_ci/';
function generated(kind){
  const op={
    operationId:kind==='unpaginated-list'
      ?'inventory_ci.list.unpaginated':'inventory_ci.list.paginated',
    method:'GET',path:'/inventory_ci',
    contractHash:'b'.repeat(64),className:kind==='unpaginated-list'
      ?'InventoryCiListUnpaginated':'InventoryCiListPaginated',
    fields:[{name:'id',type:'String',required:true}],
    params:[],bodyFields:[],resultKind:kind,
    filters:[],sortFields:[],supportsSearch:false,
  };
  const files=renderTypedFeature({
    featureId:'inventory_ci',projectId:'source-only-ci',
    contractHash:'a'.repeat(64),operations:[op],
  });
  const name=op.operationId.replaceAll('.','_');
  return {
    dto:files.get(base+'lib/src/data/'+name+'_dto.dart'),
    test:files.get(base+'test/'+name+'_dto_test.dart'),
  };
}
test('RC327 signed unpaginated DTO supports all 5000 approved Backend records',()=>{
  const {dto,test:regression}=generated('unpaginated-list');
  assert.ok(dto.includes('input.length>5000'));
  assert.ok(!dto.includes('input.length>500 ||'));
  assert.ok(dto.includes("(meta['count'] as int)!=input.length"));
  assert.ok(dto.includes("(meta['maxRows'] as int)>5000"));
  assert.ok(dto.includes('meta[\'limitExceeded\']==true'));
  assert.ok(regression.includes('List<Object?>.filled(501,template)'));
  assert.ok(regression.includes('List<Object?>.filled(5000,template)'));
  assert.ok(regression.includes('List<Object?>.filled(5001,template)'));
  assert.ok(regression.includes('meta["count"]=500'));
});
test('RC327 signed paginated DTO remains restricted to one 20-row page',()=>{
  const {dto}=generated('paginated-list');
  assert.ok(dto.includes('input.length>20'));
  assert.ok(dto.includes("(meta['limit'] as int)!=20"));
  assert.ok(!dto.includes('input.length>5000'));
});

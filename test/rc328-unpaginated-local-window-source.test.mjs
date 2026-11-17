import test from 'node:test';
import assert from 'node:assert/strict';
import {renderTypedFeature} from '../tools/render-typed-feature-rc116.mjs';

function page(kind){
  const id=kind==='unpaginated-list'
    ?'inventory_ci.list.unpaginated':'inventory_ci.list.paginated';
  const op={
    operationId:id,method:'GET',path:'/inventory_ci',
    contractHash:'b'.repeat(64),
    className:kind==='unpaginated-list'
      ?'InventoryCiListUnpaginated':'InventoryCiListPaginated',
    fields:[{name:'id',type:'String',required:true}],
    params:[],bodyFields:[],resultKind:kind,
    filters:[],sortFields:[],supportsSearch:false,
  };
  const files=renderTypedFeature({
    featureId:'inventory_ci',projectId:'source-only',
    contractHash:'a'.repeat(64),operations:[op],
  });
  const idSlug=id.replaceAll('.','_');
  return files.get(
    'packages/features/fable_inventory_ci/lib/src/presentation/'+
    idSlug+'_page.dart',
  );
}

test('RC328 unpaginated UI permits navigation over all 5000 verified rows in 100-row windows',()=>{
  const src=page('unpaginated-list');
  assert.ok(src.includes('int _rowOffset=0;'));
  assert.ok(src.includes('void _window(int offset){'));
  assert.ok(src.includes('state.value.items.skip(_rowOffset).take(100)'));
  assert.ok(src.includes('Rows "+(_rowOffset+1).toString()'));
  assert.ok(src.includes('Previous 100'));
  assert.ok(src.includes('Next 100'));
  assert.ok(src.includes('_rowOffset+100<state.value.items.length'));
  assert.ok(!src.includes('Displaying first 100 rows; refine the project query'));
});
test('RC328 auth/selected tenant or repository switches reset local row position',()=>{
  const src=page('unpaginated-list');
  const changes=src.slice(src.indexOf('void _bind(){'),src.indexOf('void _load(){'));
  assert.ok((changes.match(/_rowOffset=0;/g)||[]).length>=2,
    'identity events and repository/stream updates must reset row offset');
  const load=src.slice(src.indexOf('void _load(){'),src.indexOf('@override Widget build('));
  assert.ok(load.includes('setState(()=>_rowOffset=0)'));
});
test('RC328 paginated signed feed stays infinite-scroll rather than gaining local window controls',()=>{
  const src=page('paginated-list');
  assert.ok(src.includes('ScrollController _scroll'));
  assert.ok(src.includes('_controller.loadNext()'));
  assert.ok(!src.includes('_rowOffset'));
  assert.ok(!src.includes('Previous 100'));
});

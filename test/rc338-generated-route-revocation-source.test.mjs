import test from 'node:test';
import assert from 'node:assert/strict';
import {renderTypedFeature} from '../tools/render-typed-feature-rc116.mjs';

function generated(kind,method='GET') {
  const featureId='inventory_ci',name=method==='POST'?'create':kind==='paginated-list'
    ?'list.paginated':kind==='unpaginated-list'?'list.unpaginated':'get';
  const operationId=featureId+'.'+name;
  const op={
    operationId,method,path:method==='POST'?'/inventory_ci':kind==='single'
      ?'/inventory_ci/{id}':'/inventory_ci',
    className:method==='POST'?'InventoryCiCreate':kind==='paginated-list'
      ?'InventoryCiListPaginated':kind==='unpaginated-list'
      ?'InventoryCiListUnpaginated':'InventoryCiGet',
    contractHash:'b'.repeat(64),
    params:kind==='single'&&method==='GET'?['id']:[],
    bodyFields:method==='POST'?[{name:'title',type:'String',required:true,maxLength:191}]:[],
    fields:[{name:'title',type:'String',required:true}],
    resultKind:kind,supportsSearch:false,filters:[],sortFields:[],
  };
  const files=renderTypedFeature({featureId,projectId:'source-fixture',
    contractHash:'a'.repeat(64),operations:[op]});
  return files.get('packages/features/fable_inventory_ci/lib/src/presentation/'+
    operationId.replaceAll('.','_')+'_page.dart');
}
test('RC338 infinite-scroll routes never automatically read old gateway after an identity or contract invalidation',()=>{
  const page=generated('paginated-list');
  assert.ok(page.includes('bool _revoked=false;'));
  assert.ok(page.includes('_identityEpoch++;\n      _revoked=true;'));
  assert.ok(page.includes('if(_revoked || !_scroll.hasClients'));
  assert.ok(page.includes('void _refresh(){\n    if(_revoked)return;'));
  assert.ok(page.includes('if(_revoked)return Scaffold('));
  assert.ok(page.includes('Reopen this screen from the verified feature'));
  assert.ok(page.includes('_controller.invalidate();'));
  assert.ok(page.includes('void _bind({bool readAllowed=true}){\n    _revoked=!readAllowed;'));
});
test('RC338 generated read screen cannot re-read from previous project via Load button',()=>{
  for(const kind of ['single','unpaginated-list']){
    const page=generated(kind);
    assert.ok(page.includes('_revoked=true;'));
    assert.ok(page.includes('void _load(){'));
    assert.ok(page.includes('if(_revoked)return;'));
    assert.ok(page.includes('if(_revoked)return Scaffold('));
    assert.ok(page.includes('_controller.invalidate();'));
    assert.ok(page.includes('void _bind({bool readAllowed=true}){\n    _revoked=!readAllowed;'));
  }
});
test('RC338 generated POST cannot submit or reset under revoked signed project',()=>{
  const page=generated('single','POST');
  assert.ok(page.includes('if(_revoked || _confirming || _controller.state is InventoryCiCreateLoading)return;'));
  assert.ok(page.includes('if(_revoked)return Scaffold('));
  assert.ok(page.includes('_revoked=true;'));
  assert.ok(page.includes('_identityEpoch++;'));
  assert.ok(page.includes('originalIdentity!=_identityEpoch'));
});

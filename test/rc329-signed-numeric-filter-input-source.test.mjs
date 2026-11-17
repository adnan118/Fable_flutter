import test from 'node:test';
import assert from 'node:assert/strict';
import {renderTypedFeature} from '../tools/render-typed-feature-rc116.mjs';

const plan={
  featureId:'inventory_ci',projectId:'source-only',
  contractHash:'a'.repeat(64),
  operations:[{
    operationId:'inventory_ci.list.paginated',
    method:'GET',path:'/inventory_ci',
    contractHash:'b'.repeat(64),
    className:'InventoryCiListPaginated',
    fields:[
      {name:'amount',type:'double',required:true},
      {name:'count',type:'int',required:true},
      {name:'title',type:'String',required:true},
    ],
    params:[],bodyFields:[],resultKind:'paginated-list',
    supportsSearch:false,sortFields:[],
    filters:[
      {name:'amountMin',type:'decimal'},
      {name:'amountMax',type:'decimal'},
      {name:'countMin',type:'int'},
      {name:'countMax',type:'int'},
      {name:'title',type:'text'},
    ],
  }],
};

test('RC329 generated filter fields match signed Backend type precision limits',()=>{
  const files=renderTypedFeature(plan);
  const prefix='packages/features/fable_inventory_ci/lib/src/';
  const page=files.get(prefix+'presentation/inventory_ci_list_paginated_page.dart');
  assert.ok(page.includes('controller:_filteramountMin,maxLength:67'));
  assert.ok(page.includes('controller:_filteramountMax,maxLength:67'));
  assert.ok(page.includes('controller:_filtercountMin,maxLength:11'));
  assert.ok(page.includes('controller:_filtercountMax,maxLength:11'));
  assert.ok(page.includes('controller:_filtertitle,maxLength:191'));
  assert.ok(page.includes('decimal:true'));
  assert.ok(page.includes('decimal:false'));
  const adapter=files.get(prefix+'data/fable_inventory_ci_list_paginated_repository.dart');
  assert.ok(adapter.includes('[0-9]{1,30}'));
  assert.ok(adapter.includes('int.tryParse(countMin.trim())'));
});

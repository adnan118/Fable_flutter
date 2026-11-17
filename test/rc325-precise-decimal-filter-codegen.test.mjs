import test from 'node:test';
import assert from 'node:assert/strict';
import {renderTypedFeature} from '../tools/render-typed-feature-rc116.mjs';

const root='packages/features/fable_orders_ci/';
function render(filters){
 const plan={
  featureId:'orders_ci',projectId:'offline-acceptance-fixture',
  contractHash:'a'.repeat(64),
  operations:[{
    operationId:'orders_ci.list.paginated',method:'GET',path:'/orders_ci',
    contractHash:'b'.repeat(64),className:'OrdersCiListPaginated',
    fields:[{name:'id',type:'String',required:true}],
    params:[],bodyFields:[],resultKind:'paginated-list',
    supportsSearch:false,sortFields:[],filters,
  }],
 };
 return renderTypedFeature(plan).get(root+
   'lib/src/data/fable_orders_ci_list_paginated_repository.dart');
}
test('RC325 typed Flutter Decimal filters preserve exact 65-digit bounds and order',()=>{
 const source=render([
  {name:'amountMin',type:'decimal'},{name:'amountMax',type:'decimal'},
  {name:'countMin',type:'int'},{name:'countMax',type:'int'},
 ]);
 assert.ok(source.includes('int _compareExactDecimal(String a,String b)'));
 assert.ok(source.includes('BigInt.parse('));
 assert.ok(source.includes('_compareExactDecimal(amountMin.trim(),amountMax.trim())>0'));
 assert.ok(source.includes('int.parse(countMin.trim())>int.parse(countMax.trim())'));
 assert.ok(source.includes('[1-9][0-9]{0,34}'));
 assert.ok(source.includes('[0-9]{1,30}'));
 assert.ok(!source.includes('double.tryParse(amountMin'));
 assert.ok(!source.includes('double.parse(amountMin'));
 assert.ok(source.includes('query:<String,dynamic>'));
 assert.ok(source.includes('"amountMin":amountMin.trim()'));
});
test('RC325 integer-only selected operations do not include unused decimal comparison helper',()=>{
 const source=render([{name:'countMin',type:'int'},{name:'countMax',type:'int'}]);
 assert.ok(!source.includes('int _compareExactDecimal('));
 assert.ok(source.includes('int.tryParse(countMin.trim())'));
});

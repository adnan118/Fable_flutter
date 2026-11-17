import test from 'node:test';
import assert from 'node:assert/strict';
import {signedPaginatedListFields} from '../tools/plan-typed-feature-rc116.mjs';

const metadata=(mode,fields)=>({
 type:'object',
 properties:{mode:{const:mode},...Object.fromEntries(
   fields.map(name=>[name,{type:'integer'}]))},
 required:['mode',...fields],
});
const pageFields=['page','limit','total','totalPages'];
const searchFields=[...pageFields,'count'];
function fixture(decimalType='string',openApiType=decimalType){
 const query=[
  {key:'page',type:'integer',minimum:1},
  {key:'limit',type:'integer',minimum:1,maximum:100},
  {key:'mode',type:'string',enum:['page','search']},
  ...['amount','amountMin','amountMax'].map(key=>({key,type:decimalType})),
  ...['quantity','quantityMin','quantityMax'].map(key=>({key,type:'integer'})),
 ];
 const op={
  operationId:'catalog_ci.list.paginated',method:'GET',
  recordAccess:'permission-wide',
  request:{query,headers:[]},
  response:{kind:'fable-success-envelope',data:{
   type:'list-result',
   item:{type:'object',fields:[
     {name:'id',type:'uuid',optional:false},
     {name:'amount',type:'decimal',optional:false},
     {name:'quantity',type:'int',optional:false},
   ]},
   meta:{
     modes:['page','search'],
     page:Object.fromEntries(pageFields.map(x=>[x,'integer'])),
     search:Object.fromEntries(searchFields.map(x=>[x,'integer'])),
   },
  }},
 };
 const schema={
  type:'object',
  properties:{
   items:{type:'array',items:{
     type:'object',properties:{
       id:{type:'string',format:'uuid'},
       amount:{type:'string'},
       quantity:{type:'integer'},
     },required:['id','amount','quantity'],
   }},
   meta:{oneOf:[
     metadata('page',pageFields),
     metadata('search',searchFields),
   ]},
  },
  required:['items','meta'],
 };
 const route={parameters:query.map(x=>({
   name:x.key,in:'query',required:false,
   schema:{type:x.key.startsWith('amount')?openApiType:x.type,
     ...(x.minimum===undefined?{}:{minimum:x.minimum}),
     ...(x.maximum===undefined?{}:{maximum:x.maximum}),
     ...(x.enum===undefined?{}:{enum:x.enum})},
 }))};
 return {op,schema,route};
}
test('RC348 exact signed Decimal strings permit typed min/max page filtering without JS float coercion',()=>{
 const x=fixture();
 const plan=signedPaginatedListFields(x.op,x.schema,x.route);
 assert.deepEqual(plan.filters,[
   {name:'amountMin',type:'decimal'},
   {name:'amountMax',type:'decimal'},
 ]);
 assert.equal(plan.fields.find(f=>f.name==='amount')?.decimal,true);
});
test('RC350 source-signed Int32 range filters require integer not floating-point schema',()=>{
 const x=fixture();
 const result=signedPaginatedListFields(x.op,x.schema,x.route);
 assert.ok(result.filters.every(f=>f.type!=='int') ||
   result.filters.some(f=>f.name==='quantityMin'));
 const wrong=fixture();
 const ref=wrong.op.request.query.find(q=>q.key==='quantityMin');
 ref.type='number';
 const query=wrong.route.parameters.find(q=>q.name==='quantityMin');
 query.schema.type='number';
 const legacy=signedPaginatedListFields(wrong.op,wrong.schema,wrong.route);
 assert.ok(!legacy.filters.some(f=>f.name==='quantityMin'));
});

test('RC348 legacy numeric Decimal contracts cannot quietly become precise filters',()=>{
 const x=fixture('number','number');
 const plan=signedPaginatedListFields(x.op,x.schema,x.route);
 assert.ok(plan.filters.every(f=>f.type!=='decimal'));
});
test('RC348 mismatch of independently source-signed and OpenAPI types fails closed',()=>{
 const x=fixture('string','number');
 assert.throws(()=>signedPaginatedListFields(x.op,x.schema,x.route),
   /paginated query schema differs from signed Backend/);
});

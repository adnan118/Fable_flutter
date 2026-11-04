import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,mkdirSync,writeFileSync,rmSync,existsSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join,dirname} from 'node:path';
import {planTypedFeature} from '../tools/plan-typed-feature-rc116.mjs';
import {renderTypedFeature} from '../tools/render-typed-feature-rc116.mjs';
import {auditFeatureArchitectures} from '../tools/enforce-feature-architecture-rc115.mjs';
import {generatePinnedTypedFeature} from '../tools/generate-typed-feature-rc116.mjs';

const hash='a'.repeat(64),opHash='c'.repeat(64);
const idA='orders_ci.item.get',idB='orders_ci.summary.get';
const props={
  id:{type:'string'},quantity:{type:'integer'},total:{type:'number'},
  active:{type:'boolean'},note:{type:'string'},
};
const response={type:'object',properties:{
  success:{const:true},
  data:{type:'object',properties:props,
    required:['id','quantity','total','active']},
},required:['success','data']};
const op=(id,path)=>({
  operationId:id,method:'GET',path,feature:'orders_ci',
  public:false,permissions:['orders.read'],contractHash:opHash,
  request:{params:path.includes(':id')?[{name:'id',type:'string',required:true}]:[]},
  response:{kind:'fable-success-envelope',data:{type:'object',fields:[
    {name:'id',type:'string',optional:false},
    {name:'quantity',type:'int',optional:false},
    {name:'total',type:'decimal',optional:false},
    {name:'active',type:'boolean',optional:false},
    {name:'note',type:'string',optional:true},
  ]}},
});
export function mockTypedFeatureInput(){
  const operations=[op(idA,'/orders/:id'),op(idB,'/orders/summary')];
  return {
    featureId:'orders_ci',
    contract:{kind:'fable.client-contract',
      project:{id:'synthetic-only-project'},contractHash:hash,operations},
    openapi:{openapi:'3.1.0',paths:{
      '/orders/{id}':{get:{
        operationId:idA,'x-fable-public':false,'x-fable-contract-hash':opHash,
        security:[{bearerAuth:[]}],
        parameters:[{name:'id',in:'path',required:true,schema:{type:'string'}}],
        responses:{'200':{content:{'application/json':{schema:structuredClone(response)}}}},
      }},
      '/orders/summary':{get:{
        operationId:idB,'x-fable-public':false,'x-fable-contract-hash':opHash,
        security:[{bearerAuth:[]}],parameters:[],
        responses:{'200':{content:{'application/json':{schema:structuredClone(response)}}}},
      }},
    }},
    requirements:{
      schemaVersion:1,kind:'fable.feature-integration-requirements',
      features:{orders_ci:{needsBackend:true,operations:[
        {operationId:idA,method:'GET',path:'/orders/:id'},
        {operationId:idB,method:'GET',path:'/orders/summary'},
      ]}},
    },
    selectedFeatures:['orders_ci'],
  };
}
const save=(root,path,s)=>{
  const to=join(root,path);mkdirSync(dirname(to),{recursive:true});
  writeFileSync(to,s);
};
function fixtureFiles(root,files){
  for(const [path,data] of files)save(root,path,data);
}
function withTemp(fn){
  const root=mkdtempSync(join(tmpdir(),'fable-rc116-'));
  try{return fn(root);}
  finally{rmSync(root,{recursive:true,force:true});}
}
test('RC116 generates two independent typed GET contracts with required and optional DTO fields',()=>{
  const plan=planTypedFeature(mockTypedFeatureInput());
  assert.equal(plan.operations.length,2);
  assert.deepEqual(plan.operations[0].params,['id']);
  assert.equal(plan.operations[0].fields.length,5);
  const files=renderTypedFeature(plan);
  assert.ok(files.size>=18);
  const prefix='packages/features/fable_orders_ci/lib/src/';
  const domain=files.get(prefix+'domain/orders_ci_item_get_entity.dart');
  const dto=files.get(prefix+'data/orders_ci_item_get_dto.dart');
  const adapter=files.get(prefix+'data/fable_orders_ci_item_get_repository.dart');
  const app=files.get(prefix+'application/orders_ci_item_get_use_case.dart');
  const presenter=files.get(prefix+'presentation/orders_ci_item_get_controller.dart');
  assert.match(domain,/final String id;/);
  assert.match(domain,/final String\? note;/);
  assert.match(domain,/final int quantity;/);
  assert.match(domain,/final double total;/);
  assert.match(dto,/FormatException/);
  assert.match(dto,/num/);
  assert.match(adapter,/FableAuthGateway/);
  assert.match(adapter,/op\.contractHash/);
  assert.match(adapter,/path:\{"id": id\}/);
  assert.match(adapter,/TypedReadFailureKind\.invalidResponse/);
  assert.match(app,/TypedReadResult<OrdersCiItemGetEntity>/);
  assert.doesNotMatch(app,/Map<String,dynamic>|Dio|FableAuthGateway/);
  assert.match(presenter,/extends ChangeNotifier/);
  assert.doesNotMatch(presenter,/Dio|Map<String,dynamic>|FableAuthGateway/);
});
test('RC116 generated source passes generic RC115 dependency gate for any custom feature',()=>{
  withTemp(root=>{
    const plan=planTypedFeature(mockTypedFeatureInput());
    fixtureFiles(root,renderTypedFeature(plan));
    const audit=auditFeatureArchitectures(root);
    assert.deepEqual(audit.findings,[]);
    assert.deepEqual(audit.adopted,['orders_ci']);
  });
});
test('RC116 fails closed on missing/ambiguous response schema or unsupported property',()=>{
  for(const mutation of [
    x=>{delete x.openapi.paths['/orders/{id}'].get.responses['200'].content['application/json'].schema.properties.data;},
    x=>{x.openapi.paths['/orders/{id}'].get.responses['200'].content['application/json'].schema.properties.data={};},
    x=>{x.openapi.paths['/orders/{id}'].get.responses['200'].content['application/json'].schema.properties.data.properties.total={type:'array',items:{type:'string'}};},
    x=>{x.openapi.paths['/orders/{id}'].get.responses['200'].content['application/json'].schema.properties.data.properties.note={type:'object'};},
    x=>{x.openapi.paths['/orders/{id}'].get.responses['200'].content['application/json'].schema.properties.data.properties['bad-name']={type:'string'};},
    x=>{x.openapi.paths['/orders/{id}'].get.responses['200'].content['application/json'].schema.properties.data.required.push('notDeclared');},
  ]){
    const x=mockTypedFeatureInput();
    mutation(x);
    assert.throws(()=>planTypedFeature(x),/RC116 typed feature/);
  }
});
test('RC116 rejects unverified routes, wrong hash, public auth, unknown permissions and unsafe paths',()=>{
  for(const mutation of [
    x=>{x.openapi.paths['/orders/{id}'].get['x-fable-contract-hash']='d'.repeat(64);},
    x=>{x.openapi.paths['/orders/{id}'].get['x-fable-public']=true;},
    x=>{x.contract.operations[0].permissions=[];},
    x=>{x.requirements.features.orders_ci.operations[0].method='POST';},
    x=>{x.requirements.features.orders_ci.operations[0].path='/users/../admin';},
    x=>{x.openapi.paths['/orders/{id}'].get.security=[];},
    x=>{x.openapi.paths['/orders/{id}'].get.parameters=[];},
    x=>{x.selectedFeatures=[];},
    x=>{x.contract.operations[0].feature='someone_else';},
    x=>{x.openapi.paths['/orders/{id}'].get.responses['200'].content['application/json'].schema.properties.data.properties.total={type:'integer'};},
    x=>{x.contract.operations[0].response.data.fields[2].type='json';},
  ]){
    const x=mockTypedFeatureInput();
    mutation(x);
    assert.throws(()=>planTypedFeature(x),/RC116 typed feature/);
  }
});
test('RC116 cannot be applied using fixture or Other Backend regardless of matching labels',()=>{
  withTemp(root=>{
    assert.throws(()=>generatePinnedTypedFeature(root,{
      featureId:'orders_ci',expectedProjectId:'synthetic-only-project',
      expectedContractHash:hash,apply:true,
    }));
    assert.equal(existsSync(join(root,'packages/features/fable_orders_ci')),false);
  });
});
test('RC116 no mutation for planning or rejected source and no fabricated APIs',()=>{
  const x=mockTypedFeatureInput();
  const plan=planTypedFeature(x);
  assert.equal(plan.liveE2EVerified,false);
  assert.match(plan.unsupportedMethods,/POST/);
  const files=renderTypedFeature(plan);
  for(const source of files.values()){
    assert.doesNotMatch(source,/token=|playbackToken|FirebaseAuth/);
  }
});

import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {planTypedFeature} from '../tools/plan-typed-feature-rc116.mjs';
import {renderTypedFeature} from '../tools/render-typed-feature-rc116.mjs';

const scope='managed-entity:company';
const featureId='catalog_ci',operationId=featureId+'.list.unpaginated';
const path='/'+featureId+'/all',hash='a'.repeat(64),opHash='b'.repeat(64);
function fixture(){
 const item={type:'object',properties:{
   id:{type:'string',format:'uuid'},
   title:{type:'string'},
 },required:['id','title']};
 const result={type:'object',properties:{
   items:{type:'array',items:item},
   meta:{type:'object',properties:{
     mode:{const:'unpaginated'},count:{type:'integer'},
     maxRows:{type:'integer'},limitExceeded:{type:'boolean'},
   },required:['mode','count','maxRows','limitExceeded']},
 },required:['items','meta']};
 const query=[{key:'createdAtFrom',type:'string',format:'date-time'}];
 const op={operationId,method:'GET',path,feature:featureId,
   public:false,permissions:[featureId+'.list.unpaginated'],
   contractHash:opHash,recordAccess:scope,
   request:{params:[],headers:[],query},
   response:{kind:'fable-success-envelope',data:{
     type:'list-result',item:{type:'object',fields:[
       {name:'id',type:'uuid',optional:false},
       {name:'title',type:'string',optional:false},
     ]},
     meta:{modes:['unpaginated'],unpaginated:{
       count:'integer',maxRows:'integer',limitExceeded:'boolean',
     }},
   }},
 };
 return {
   featureId,selectedFeatures:[featureId],
   contract:{kind:'fable.client-contract',
     project:{id:'managed-source-only'},contractHash:hash,operations:[op]},
   openapi:{openapi:'3.1.0',paths:{[path]:{get:{
     operationId,'x-fable-contract-hash':opHash,
     'x-fable-public':false,'x-fable-record-access':scope,
     security:[{bearerAuth:[]}],
     parameters:[{name:'createdAtFrom',in:'query',required:false,
       schema:{type:'string',format:'date-time'}}],
     responses:{'200':{content:{'application/json':{schema:{
       type:'object',properties:{success:{const:true},data:result},
       required:['success','data'],
     }}}},
   }}}}},
   requirements:{kind:'fable.feature-integration-requirements',schemaVersion:1,
     features:{[featureId]:{needsBackend:true,operations:[{
       operationId,method:'GET',path,
     }]}}},
 };
}

test('RC334 managed source-signed unpaginated list renders only via bound entity gateway',()=>{
 const plan=planTypedFeature(fixture());
 const op=plan.operations[0];
 assert.equal(op.resultKind,'unpaginated-list');
 assert.equal(op.managedScoped,true);
 assert.equal(op.recordAccess,scope);
 const files=renderTypedFeature(plan);
 const root='packages/features/fable_catalog_ci/lib/src/';
 const nav=files.get(root+'project_feature.dart');
 const repo=files.get(root+'data/fable_catalog_ci_list_unpaginated_repository.dart');
 assert.ok(nav.includes('FableManagedEntityPinnedGateway'));
 assert.ok(nav.includes('bound.scopeEvents'));
 assert.ok(repo.includes('final FableManagedEntityPinnedGateway gateway;'));
 assert.ok(repo.includes('op.recordAccess!="'+scope+'"'));
 assert.ok(repo.includes('gateway.execute("'+operationId+'")'));
 assert.ok(!repo.includes('query:<String,dynamic>'));
});

test('RC334 managed unpaginated list rejects privilege/scope and signature drift',()=>{
 const changes=[
   f=>{f.contract.operations[0].recordAccess='owner:user';},
   f=>{f.openapi.paths[path].get['x-fable-record-access']='permission-wide';},
   f=>{f.contract.operations[0].permissions=['catalog_ci.read'];},
   f=>{f.contract.operations[0].path='/catalog_ci';},
   f=>{f.contract.operations[0].request.headers=['X-Admin'];},
   f=>{f.contract.operations[0].request.query[0].required=true;},
   f=>{f.openapi.paths[path].get.parameters[0].required=true;},
   f=>{f.openapi.paths[path].get.parameters[0].schema.format='uuid';},
   f=>{f.contract.operations[0].contractHash='c'.repeat(64);},
 ];
 for(const change of changes){
   const f=fixture();change(f);
   assert.throws(()=>planTypedFeature(f),/RC116 typed feature/);
 }
});

test('RC334 runtime entity gateway requires exact /feature/all signed GET',()=>{
 const gateway=readFileSync(new URL(
   '../packages/fable_core/lib/src/fable_managed_entity_pinned_gateway.dart',
   import.meta.url),'utf8');
 assert.ok(gateway.includes("item.key.endsWith('.list.unpaginated')"));
 assert.ok(gateway.includes("item.key.split('.').first+'/all'"));
 assert.ok(gateway.includes('op.contractHash!=item.value'));
 assert.ok(gateway.includes('store.isBoundToCredentials(session)'));
 assert.ok(gateway.includes('store.isBoundToBackend(managedEntityBackendIdentity)'));
 assert.ok(gateway.includes('store.selectionRevision==revision'));
 assert.ok(gateway.includes('session.identityRevision==account'));
});

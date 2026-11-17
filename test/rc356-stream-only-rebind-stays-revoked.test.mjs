import test from 'node:test';
import assert from 'node:assert/strict';
import {renderTypedFeature} from '../tools/render-typed-feature-rc116.mjs';

const hash='a'.repeat(64),opHash='b'.repeat(64),readHash='c'.repeat(64);
const field={name:'title',type:'String',required:true};
function source(method,kind){
 const name=method==='PATCH'?'update':method==='DELETE'?'delete':
   method==='POST'?'create':kind==='paginated-list'?'list.paginated':'get';
 const id='notes_ci.'+name;
 const op={operationId:id,method,path:kind==='paginated-list'
    ?'/notes_ci':method==='POST'?'/notes_ci':'/notes_ci/:id',
   className:'NotesCi'+(name==='list.paginated'?'ListPaginated':
     name[0].toUpperCase()+name.slice(1)),
   contractHash:opHash,params:method==='POST'||kind==='paginated-list'?[]:['id'],
   fields:method==='DELETE'?[]:[field],
   bodyFields:method==='PATCH'?[{name:'title',type:'String',
     required:false,maxLength:191}]:
     method==='POST'?[field]:[],
   resultKind:method==='DELETE'?'confirmed-delete':kind,
   filters:[],sortFields:[],supportsSearch:false,
   ...(method==='PATCH'||method==='DELETE'?{
     preconditionRead:{operationId:'notes_ci.get',contractHash:readHash,
       path:'/notes_ci/:id'},
   }:{}),
 };
 const files=renderTypedFeature({featureId:'notes_ci',projectId:'source-rebind',
   contractHash:hash,operations:[op]});
 return files.get('packages/features/fable_notes_ci/lib/src/presentation/'+
   id.replaceAll('.','_')+'_page.dart');
}
test('RC356 changing just the event stream never reactivates old source-bound route',()=>{
 for(const [method,kind] of [
   ['GET','single'],['GET','paginated-list'],
   ['POST','single'],['PATCH','single'],['DELETE','single'],
 ]){
   const page=source(method,kind);
   assert.ok(page.includes('_bind({bool readAllowed=true})'),method);
   assert.ok(page.includes('_revoked=!readAllowed;'),method);
   assert.ok(page.includes(
     'final freshRepository=!identical(old.repository,widget.repository);'
   ),method);
   assert.ok(page.includes('_bind(readAllowed:freshRepository);'),method);
   assert.ok(page.includes('if(_revoked'),method);
 }
});
test('RC356 infinite lists do not schedule an old gateway request on event-only rebinding',()=>{
 const page=source('GET','paginated-list');
 assert.ok(page.includes('if(mounted && !_revoked && _identityEpoch==bindingIdentity)'));
 assert.ok(page.includes('if(_revoked || !_scroll.hasClients'));
 assert.ok(page.includes('Project or login context changed. Reopen this screen'));
});

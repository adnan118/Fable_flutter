import test from 'node:test';
import assert from 'node:assert/strict';
import {renderTypedFeature} from '../tools/render-typed-feature-rc116.mjs';

const H='a'.repeat(64),O='b'.repeat(64),G='c'.repeat(64);
const base={
 path:'/notes_ci/:id',params:['id'],
 preconditionRead:{operationId:'notes_ci.get',contractHash:G,path:'/notes_ci/:id'},
 contractHash:O,fields:[],sortFields:[],
};
function generated(method,managedScoped=false){
 const isPatch=method==='PATCH',operationId='notes_ci.'+(isPatch?'update':'delete');
 const plan={featureId:'notes_ci',projectId:'signed-writes-fixture',contractHash:H,
  operations:[{...base,
    operationId,className:'NotesCi'+(isPatch?'Update':'Delete'),
    method,resultKind:isPatch?'single':'confirmed-delete',
    bodyFields:isPatch?[{name:'title',type:'String',required:false,maxLength:191}]:[],
    ...(managedScoped?{managedScoped:true,recordAccess:'managed-entity:company'}:{}),
  }]};
 return renderTypedFeature(plan).get(
   'packages/features/fable_notes_ci/lib/src/presentation/'+
   operationId.replaceAll('.','_')+'_page.dart');
}
for(const method of ['PATCH','DELETE']){
 for(const managedScoped of [false,true]){
  test('RC342 '+method+' '+(managedScoped?'managed':'owner')+' route blocks stale POST-invalidation mutation',()=>{
   const page=generated(method,managedScoped);
   assert.ok(page.includes('bool _revoked=false;'));
   assert.ok(page.includes('void _bind({bool readAllowed=true}){_revoked=!readAllowed;'));
   assert.ok(page.includes('_epoch++;_revoked=true;'));
   assert.ok(page.includes('if(_revoked||_confirming||_controller.state is!'));
   assert.ok(page.includes('if(_revoked)return Scaffold('));
   assert.ok(page.includes('Reopen this verified operation before'));
   assert.ok(page.includes('unawaited(_identity?.cancel());'));
   assert.ok(page.includes('_controller.invalidate();'));
   assert.ok(page.includes('revision!=_epoch')||page.includes('epoch!=_epoch'));
   assert.ok(!page.includes('onPressed:_revoked?null:_controller.invalidate()'));
  });
 }
}

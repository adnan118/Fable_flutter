import test from 'node:test';
import assert from 'node:assert/strict';
import {renderTypedFeature} from '../tools/render-typed-feature-rc116.mjs';

function render(managed=false){
 const f='notes_ci';
 const plan={featureId:f,projectId:'project-source-only',
   contractHash:'a'.repeat(64),operations:[{
     operationId:'notes_ci.get',method:'GET',path:'/notes_ci/{id}',
     contractHash:'b'.repeat(64),className:'NotesCiGet',
     fields:[{name:'id',type:'String',required:true}],
     params:['id'],bodyFields:[],resultKind:'single',
     ...(managed?{managedScoped:true,recordAccess:'managed-entity:company'}:{}),
   }]};
 const files=renderTypedFeature(plan);
 return files.get('packages/features/fable_notes_ci/lib/src/project_feature.dart');
}

test('RC332 stale generated route is notified on signed contract replacement',()=>{
 for(const managed of [false,true]){
   const src=render(managed);
   assert.ok(src.includes("import 'dart:async';"));
   assert.ok(src.includes('StreamController<Object?>.broadcast(sync:true)'));
   assert.ok(src.includes('Stream<Object?> _eventsFor(Stream<Object?> source)'));
   assert.ok(src.includes('Stream<Object?>.multi((controller)'));
   assert.ok(src.includes('_contractChanges.stream.listen(controller.add'));
   assert.ok(src.includes('await identity.cancel();await contract.cancel();'));
   const update=src.slice(src.indexOf('didUpdateWidget('),src.indexOf('@override void dispose()'));
   assert.ok(update.includes('_contractChanges.add(Object());'));
   assert.ok(src.includes('unawaited(_contractChanges.close())'));
 }
});
test('RC332 generated unscoped routes preserve both auth and contract invalidations',()=>{
 const src=render();
 assert.ok(src.includes('identityEvents:_eventsFor(bound.session.identityEvents)'));
 assert.ok(src.includes('final bound=_gateway;'));
});
test('RC332 generated managed routes invalidate on selected store and contract changes',()=>{
 const src=render(true);
 assert.ok(src.includes('identityEvents:_eventsFor(bound.scopeEvents)'));
 const scope=src.slice(src.indexOf('didChangeDependencies()'),src.indexOf('@override void dispose()'));
 assert.ok(scope.includes('_contractChanges.add(Object());'));
 assert.ok(scope.includes('_managedGateway?.dispose();_managedGateway=null;'));
 assert.ok(src.includes('_tryBindManaged()'));
});

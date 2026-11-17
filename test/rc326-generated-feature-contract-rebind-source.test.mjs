import test from 'node:test';
import assert from 'node:assert/strict';
import {renderTypedFeature} from '../tools/render-typed-feature-rc116.mjs';

const feature='packages/features/fable_notes_ci/';
function navigation(managed=false){
  const plan={
    featureId:'notes_ci',projectId:'contract-rebind-fixture',
    contractHash:'a'.repeat(64),
    operations:[{
      operationId:'notes_ci.get',method:'GET',path:'/notes_ci/{id}',
      contractHash:'b'.repeat(64),className:'NotesCiGet',
      fields:[{name:'id',type:'String',required:true}],
      params:['id'],bodyFields:[],resultKind:'single',
      ...(managed?{managedScoped:true,recordAccess:'managed-entity:company'}:{}),
    }],
  };
  return renderTypedFeature(plan).get(feature+'lib/src/project_feature.dart');
}

test('RC326 unscoped project-home rebinds when FableContract object is replaced',()=>{
  const src=navigation();
  assert.ok(src.includes('void _installGateway(){'));
  assert.ok(src.includes('if(!notesCiProjectFeature.canLaunchFable(widget.contract))return;'));
  assert.ok(src.includes('didUpdateWidget(covariant FableNotesCiHome old)'));
  assert.ok(src.includes('if(identical(old.contract,widget.contract))return;'));
  assert.ok(src.includes('_gateway?.dispose();_gateway=null;'));
  assert.ok(src.includes('_installGateway();'));
  assert.ok(src.includes('final bound=_gateway;'));
  assert.ok(src.includes('repository:FableNotesCiGetRepository(bound)'));
  assert.ok(src.includes('bound.session.identityEvents'));
  assert.ok(!src.includes('FableNotesCiGetRepository(_gateway!)'));
});

test('RC326 managed project rechecks signed entity binding during contract replacement',()=>{
  const src=navigation(true);
  assert.ok(src.includes('_managedGateway?.dispose();_managedGateway=null;'));
  assert.ok(src.includes('void _tryBindManaged(){'));
  assert.ok(src.includes('if(!notesCiProjectFeature.canLaunchFable(widget.contract))return;'));
  assert.ok(src.includes('if(!store.isBoundToCredentials(source.session)||'));
  assert.ok(src.includes('FableAuthGateway.managedEntityBackendIdentityFor(base,widget.contract)'));
  assert.ok(src.includes('_tryBindManaged();'));
  assert.ok(src.includes('final bound=_managedGateway;'));
  assert.ok(src.includes('repository:FableNotesCiGetRepository(bound)'));
  assert.ok(src.includes('bound.scopeEvents'));
  assert.ok(!src.includes('FableNotesCiGetRepository(_managedGateway!)'));
});

test('RC326 scoped and unscoped homes preserve signed HTTPS / debug-loopback policy',()=>{
  for(const managed of [false,true]){
    const src=navigation(managed);
    assert.ok(src.includes('_acceptOrigin(Uri? base)'));
    assert.ok(src.includes('base.scheme=="https"'));
    assert.ok(src.includes('kDebugMode && base.scheme=="http"'));
    assert.ok(src.includes('allowHttpForLocalDevelopment:kDebugMode'));
  }
});

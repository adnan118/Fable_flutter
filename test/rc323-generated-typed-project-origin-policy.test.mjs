import test from 'node:test';
import assert from 'node:assert/strict';
import {renderTypedFeature} from '../tools/render-typed-feature-rc116.mjs';

const hash='a'.repeat(64),opHash='b'.repeat(64);
const feature='packages/features/fable_notes_ci/';
function files(managed=false){
  const plan={
    featureId:'notes_ci',projectId:'source-test',contractHash:hash,
    operations:[{
      operationId:'notes_ci.get',method:'GET',path:'/notes_ci/{id}',
      contractHash:opHash,className:'NotesCiGet',params:['id'],
      fields:[{name:'title',type:'String',required:true}],
      bodyFields:[],resultKind:'single',
      ...(managed?{managedScoped:true,recordAccess:'managed-entity:company'}:{}),
    }],
  };
  return renderTypedFeature(plan);
}
test('RC323 generated project home only accepts HTTPS or debug loopback with bare origin',()=>{
  const source=files().get(feature+'lib/src/project_feature.dart');
  assert.ok(source.includes('kDebugMode'));
  assert.ok(source.includes('base.userInfo.isNotEmpty'));
  assert.ok(source.includes('base.hasQuery||base.hasFragment'));
  assert.ok(source.includes('(base.path.isNotEmpty&&base.path!="/")'));
  assert.ok(source.includes('base.scheme=="https"'));
  assert.ok(source.includes('kDebugMode && base.scheme=="http"'));
  for(const host of ['localhost','127.0.0.1','10.0.2.2','::1']){
    assert.ok(source.includes('"'+host+'"'));
  }
  assert.ok(source.includes('allowHttpForLocalDevelopment:kDebugMode'));
  assert.ok(!source.includes('base.scheme=="http" || base.scheme=="https"'));
});
test('RC323 managed factory forwards the same dev-only loopback allowance',()=>{
  const source=files(true).get(feature+'lib/src/project_feature.dart');
  const factory=files(true).get(feature+'lib/src/data/notes_ci_managed_binding.dart');
  assert.ok(source.includes('if(base==null||!_acceptOrigin(base))return;'));
  assert.ok(source.includes('allowHttpForLocalDevelopment:kDebugMode'));
  assert.ok(factory.includes('bool allowHttpForLocalDevelopment=false'));
  assert.ok(factory.includes('allowHttpForLocalDevelopment:allowHttpForLocalDevelopment'));
  assert.ok(factory.includes('required FableManagedEntityStore store'));
  assert.ok(factory.includes('approvedOperationHashes:approvedHashes'));
});

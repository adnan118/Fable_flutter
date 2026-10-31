import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,mkdirSync,writeFileSync,rmSync} from 'node:fs';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {auditBackendFeatureParity,featureOfOperation} from '../tools/audit-backend-feature-parity.mjs';

test('Auth integration audit separates source wiring, missing flows and live verification',()=>{
  const report=auditBackendFeatureParity(process.cwd());
  assert.equal(report.kind,'fable.flutter-feature-parity-audit');
  assert.equal(report.productionReady,false);
  assert.ok(report.operations.length>0);
  const login=report.operations.find(x=>x.id==='auth.login');
  const sessions=report.operations.find(x=>x.id==='auth.sessions');
  assert.equal(login?.status,'SOURCE_WIRED_NOT_LIVE_TESTED');
  assert.equal(sessions?.status,'SOURCE_WIRED_NOT_LIVE_TESTED');
  assert.equal(sessions?.presentationEvidence,'SCREEN_WIRED_NOT_LIVE_TESTED');
  assert.ok(sessions?.viewSource?.endsWith('sessions_page.dart'));
  assert.equal(report.productionReady,false);
  assert.equal(report.projectBound,false);
  assert.ok(report.operations.some(x=>x.status==='NOT_MAPPED'));
  // The reusable ci_fable contract is a 9-operation test sample; 17
  // installed packages must not be presented as 17 verified integrations.
  assert.equal(report.operationCount,9);
  assert.equal(report.auditScope.importedContractKind,'CI_STARTER_DEMO_CONTRACT');
  assert.equal(report.auditScope.backendFeatureInventoryPresent,false);
  assert.equal(report.auditScope.exhaustiveBackendFeatureAudit,false);
  assert.equal(report.auditScope.featureCount,17);
  assert.equal(report.featureMatrix.length,17);
  assert.equal(report.featureMatrix.filter(f=>f.liveVerified).length,0);
  assert.ok(report.auditScope.featuresWithoutImportedOperations.includes('payments'));
  assert.ok(report.auditScope.featuresWithoutImportedOperations.includes('notifications'));
  assert.ok(report.auditScope.featuresWithoutImportedOperations.includes('localization'));
  assert.equal(report.featureMatrix.find(f=>f.id==='payments')?.status,
    'NOT_AUDITED_NO_IMPORTED_OPERATIONS');
  assert.equal(report.featureMatrix.find(f=>f.id==='auth')?.ownership,'server');
});
test('Project binding cannot be asserted without independently trusted backend hash',()=>{
  assert.throws(()=>auditBackendFeatureParity(process.cwd(),{
    requireProjectBinding:true,expectedProjectId:'different',expectedContractHash:'0'.repeat(64)
  }),/Invalid imported Backend contract/);
});

test('External Backend audit must not read a stale Fable contract or infer its routes',()=>{
  const root=mkdtempSync(join(tmpdir(),'fable-external-parity-'));
  try{
    mkdirSync(join(root,'assets/config'),{recursive:true});
    writeFileSync(join(root,'assets/config/backend.json'),JSON.stringify({
      schemaVersion:1,kind:'fable.mobile-backend-configuration',
      backend:{kind:'other',adapter:'openapi',status:'ready'},contractImported:true,
    }));
    assert.throws(()=>auditBackendFeatureParity(root),/non-Fable Backend/);
    writeFileSync(join(root,'assets/config/backend.json'),JSON.stringify({
      schemaVersion:1,kind:'fable.mobile-backend-configuration',
      backend:{kind:'fable',adapter:'fable-contract',status:'pending'},contractImported:false,
    }));
    assert.throws(()=>auditBackendFeatureParity(root),/unverified or non-Fable Backend/);
  }finally{rmSync(root,{recursive:true,force:true});}
});

test('Feature ownership maps real optional Backend operation families, not just UI packages',()=>{
  for(const [id,feature] of Object.entries({
    'languages.clientCopy':'localization',
    'content.page.accept':'content',
    'managed-entities.list':'profile',
    'managed-accounts.create':'profile',
    'permissions.me':'access_control',
    'auth.social.apple':'social',
    'passkeys.authentication.verify':'biometrics',
    'media.upload.prepare':'media',
    'notifications.read':'notifications',
  })){
    assert.equal(featureOfOperation({id}),feature);
  }
  assert.equal(featureOfOperation({id:'unknown.private'}),null);
});

test('Feature audit cannot mistake an installed package for a complete native workflow',()=>{
  const report=auditBackendFeatureParity(process.cwd());
  assert.equal(report.featureMatrix.length,17);
  const auth=report.featureMatrix.find(f=>f.id==='auth');
  const content=report.featureMatrix.find(f=>f.id==='content');
  const payments=report.featureMatrix.find(f=>f.id==='payments');
  assert.equal(auth.nativeScreen.customFableScreen,true);
  assert.equal(content.nativeScreen.customFableScreen,true);
  assert.equal(payments.nativeScreen.customFableScreen,false);
  for(const feature of report.featureMatrix){
    assert.equal(feature.completeFeature,false);
    assert.equal(feature.liveVerified,false);
    assert.ok(Array.isArray(feature.missingOperationIds));
    assert.ok(feature.nativeScreen.source);
  }
  assert.equal(auth.contractOperationCoverage.total,report.operations
    .filter(op=>op.id.startsWith('auth.')&&!op.id.startsWith('auth.social.')).length);
  assert.equal(payments.contractOperationCoverage,null);
});

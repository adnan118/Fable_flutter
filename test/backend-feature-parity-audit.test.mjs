import test from 'node:test';
import assert from 'node:assert/strict';
import {auditBackendFeatureParity} from '../tools/audit-backend-feature-parity.mjs';

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

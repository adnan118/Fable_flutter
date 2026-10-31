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
  assert.equal(report.projectBound,false);
  assert.ok(report.operations.some(x=>x.status==='NOT_MAPPED'));
});
test('Project binding cannot be asserted without independently trusted backend hash',()=>{
  assert.throws(()=>auditBackendFeatureParity(process.cwd(),{
    requireProjectBinding:true,expectedProjectId:'different',expectedContractHash:'0'.repeat(64)
  }),/Invalid imported Backend contract/);
});

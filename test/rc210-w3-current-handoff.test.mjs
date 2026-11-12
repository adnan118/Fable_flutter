import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {compareW3CurrentHandoff,W3_REQUIRED_DOCUMENTS} from '../tools/w3-handoff-integrity.mjs';
import {parseW3Options} from '../tools/verify-current-w3-handoff.mjs';

const sha=value=>createHash('sha256').update(JSON.stringify(value)).digest('hex');
const canonical=value=>Array.isArray(value)?value.map(canonical):
  value&&typeof value==='object'?Object.fromEntries(
    Object.entries(value).sort(([a],[b])=>a.localeCompare(b))
      .map(([k,v])=>[k,canonical(v)])):value;
const hash=value=>sha(canonical(value));
const backendCommit='a'.repeat(40);
function fixture(){
  const contract={schemaVersion:2,kind:'fable.client-contract',
    project:{id:'00000000-0000-4000-8000-000000000210',name:'production-example'},
    core:{},environments:{},operations:[],features:[],
    permissions:[],errors:[],success:[],messages:[]};
  contract.contractHash=hash(contract);
  const handoff={schemaVersion:1,kind:'fable.flutter-handoff',client:'flutter',
    backend:{project:contract.project,contractHash:contract.contractHash},
    selection:{},featureCatalog:[]};
  handoff.manifestHash=sha(handoff);
  const mobile={schemaVersion:1,kind:'fable.mobile-core-operations',
    backendContractHash:contract.contractHash,operations:[]};
  mobile.operationsHash=sha(mobile.operations);
  const doc={
    'contract.json':contract,
    'flutter-handoff.json':handoff,
    'openapi.json':{openapi:'3.1.0',paths:{}},
    'mobile-core-operations.json':mobile,
    'manifest.json':{kind:'fable.client-contract',schemaVersion:2,
      client:'all',project:contract.project,contractHash:contract.contractHash,
      operationCount:0,featureCount:0},
  };
  const frontend=Object.fromEntries(W3_REQUIRED_DOCUMENTS.map(k=>[k,structuredClone(doc[k])]));
  const verified={ok:true,mode:'project',projectBound:true,
    projectId:contract.project.id,contractHash:contract.contractHash,productionReady:false};
  return {backend:doc,frontend,verified};
}
function check(change, options={}){
  const f=fixture();change?.(f);
  return compareW3CurrentHandoff(f.backend,f.frontend,{
    frontendVerification:f.verified,
    backendSourceCommit:backendCommit,sourcePinVerified:true,...options,
  });
}
const failures=result=>result.issues.join('\n');
test('RC210 W3 accepts exactly matching independent Backend export and Flutter project import',()=>{
  const r=check();
  assert.equal(r.passed,true,failures(r));
  assert.equal(r.documentsCompared,4);
  assert.equal(r.backendSourcePinned,true);
  assert.equal(r.productionApproved,false);
});
test('RC210 W3 detects Flutter-imported operation drift even when Backend hash stays valid',()=>{
  const r=check(f=>{f.frontend['contract.json'].operations.push({operationId:'forged.route'});});
  assert.equal(r.passed,false);
  assert.match(failures(r),/backend_flutter_artifact_drift:contract.json/);
});
test('RC210 W3 detects mismatched imported OpenAPI and mobile core',()=>{
  const r=check(f=>{
    f.frontend['openapi.json'].paths['/invented']={get:{operationId:'unknown'}};
    f.frontend['mobile-core-operations.json'].operations.push({operationId:'unknown'});
  });
  assert.match(failures(r),/openapi.json/);
  assert.match(failures(r),/mobile-core-operations.json/);
});
test('RC210 W3 rejects a modified signed Backend project contract',()=>{
  const r=check(f=>{f.backend['contract.json'].project.name='changed';});
  assert.match(failures(r),/backend_contract_integrity_mismatch/);
  assert.match(failures(r),/backend_export_manifest_mismatch/);
});
test('RC210 W3 rejects unsigned or forged Backend handoff, even if Flutter agrees',()=>{
  const r=check(f=>{
    f.backend['flutter-handoff.json'].selection.test=true;
    f.frontend['flutter-handoff.json'].selection.test=true;
  });
  assert.match(failures(r),/backend_flutter_handoff_integrity_mismatch/);
});
test('RC210 W3 rejects incomplete mobile operation fingerprint',()=>{
  const r=check(f=>{
    f.backend['mobile-core-operations.json'].operations.push({operationId:'fake'});
    f.frontend['mobile-core-operations.json'].operations.push({operationId:'fake'});
  });
  assert.match(failures(r),/backend_mobile_core_integrity_mismatch/);
});
test('RC210 W3 rejects stale backend export manifest count and missing exported artifacts',()=>{
  const count=check(f=>{f.backend['manifest.json'].operationCount=3;});
  assert.match(failures(count),/backend_export_manifest_mismatch/);
  const missing=check(f=>{delete f.backend['openapi.json'];});
  assert.match(failures(missing),/missing_export_or_import:openapi.json/);
});
test('RC210 W3 rejects starter fixture even with otherwise matching fingerprints',()=>{
  const r=check(f=>{
    const contract=f.backend['contract.json'];
    contract.project.id='test-project';
    contract.project.name='fable-test';
    const {contractHash,...unsigned}=contract;
    contract.contractHash=hash(unsigned);
    const handoff=f.backend['flutter-handoff.json'];
    handoff.backend.project=contract.project;
    handoff.backend.contractHash=contract.contractHash;
    const {manifestHash,...unsignedHandoff}=handoff;
    handoff.manifestHash=sha(unsignedHandoff);
    const mobile=f.backend['mobile-core-operations.json'];
    mobile.backendContractHash=contract.contractHash;
    f.backend['manifest.json'].project=contract.project;
    f.backend['manifest.json'].contractHash=contract.contractHash;
    for(const name of W3_REQUIRED_DOCUMENTS)
      f.frontend[name]=structuredClone(f.backend[name]);
    f.verified.projectId=contract.project.id;
    f.verified.contractHash=contract.contractHash;
  });
  assert.match(failures(r),/fixture_backend_project_not_accepted/);
});
test('RC210 W3 requires independent Flutter project-mode verification',()=>{
  const r=check(f=>{f.verified={ok:false,mode:'source',projectBound:false};});
  assert.match(failures(r),/flutter_independent_project_verification_failed/);
});
test('RC210 W3 does not substitute arbitrary Git SHAs or unpinned sources',()=>{
  const a=check(null,{backendSourceCommit:null});
  assert.match(failures(a),/backend_source_sha_not_independently_pinned/);
  const b=check(null,{sourcePinVerified:false});
  assert.match(failures(b),/backend_source_sha_not_independently_pinned/);
});
test('RC210 W3 rejects malformed/missing contract source',()=>{
  const r=check(f=>{f.backend['contract.json'].schemaVersion=1;});
  assert.match(failures(r),/invalid_backend_contract/);
});
test('RC210 W3 requires complete CLI options and forbids duplicates',()=>{
  assert.throws(()=>parseW3Options([]),/Required W3 option/);
  assert.throws(()=>parseW3Options(['--backend-export','/tmp/export',
    '--backend-repo','/tmp/backend','--expected-backend-sha','abc']),/full 40-char/);
  assert.throws(()=>parseW3Options(['--json','--json']),/duplicate/);
  assert.throws(()=>parseW3Options(['--backend-export','/tmp/export',
    '--backend-repo','/tmp/backend','--expected-backend-sha',backendCommit,
    '--unknown']),/Unknown/);
});

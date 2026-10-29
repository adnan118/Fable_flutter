import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync,writeFileSync,mkdtempSync,mkdirSync,rmSync,copyFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {createHash} from 'node:crypto';
import {verifyFableContract} from '../tools/verify-fable-contract.mjs';

const app=process.env.FABLE_CONTRACT_TEST_APP || process.cwd();
const files=['assets/config/backend.json','assets/contracts/contract.json','assets/contracts/flutter-handoff.json','assets/contracts/openapi.json','assets/contracts/mobile-core-operations.json'];
const sha=o=>createHash('sha256').update(JSON.stringify(o)).digest('hex');
const canonical = v => Array.isArray(v)?v.map(canonical):v&&typeof v==='object'?
 Object.fromEntries(Object.entries(v).sort(([a],[b])=>a.localeCompare(b)).map(([k,w])=>[k,canonical(w)])):v;
function rebindProject(root,id,name){
 let hash;
 change(root,'assets/contracts/contract.json',c=>{c.project.id=id;c.project.name=name;delete c.contractHash;hash=sha(canonical(c));c.contractHash=hash;});
 change(root,'assets/contracts/flutter-handoff.json',h=>{h.backend.project.id=id;h.backend.project.name=name;h.backend.contractHash=hash;delete h.manifestHash;h.manifestHash=sha(h);});
 change(root,'assets/contracts/mobile-core-operations.json',c=>c.backendContractHash=hash);
}
const fixture=()=>{
 const root=mkdtempSync(join(tmpdir(),'fable-contract-accept-'));
 for(const file of files){const to=join(root,file);mkdirSync(join(to,'..'),{recursive:true});copyFileSync(join(app,file),to);}return root;
};
const change=(root,path,fn)=>{const p=join(root,path);const o=JSON.parse(readFileSync(p,'utf8'));fn(o);writeFileSync(p,JSON.stringify(o));};
const verify=(root,opts)=>verifyFableContract(root,opts);

test('Starter graph can be structurally valid without being a real project approval',()=>{
 const root=fixture();try{
  const source=verify(root,{mode:'source'}),project=verify(root,{mode:'project',expectedProjectId:'test-project'});
  assert.equal(source.ok,true,JSON.stringify(source.failures));assert.equal(source.productionReady,false);
  assert.equal(source.projectBound,false);assert.equal(project.ok,false);
  assert.ok(project.failures.includes('fixture_project_not_accepted'));
 }finally{rmSync(root,{recursive:true,force:true});}
});
test('A project gate must pin the exact non-fixture backend project id',()=>{
 const root=fixture();try{
  rebindProject(root,'real-project-123','my-app');
  const expectedHash=JSON.parse(readFileSync(join(root,'assets/contracts/contract.json'))).contractHash;
  const missing=verify(root,{mode:'project'});
  const wrong=verify(root,{mode:'project',expectedProjectId:'another-project',expectedContractHash:expectedHash});
  const noHash=verify(root,{mode:'project',expectedProjectId:'real-project-123'});
  const wrongHash=verify(root,{mode:'project',expectedProjectId:'real-project-123',expectedContractHash:'0'.repeat(64)});
  const correct=verify(root,{mode:'project',expectedProjectId:'real-project-123',expectedContractHash:expectedHash});
  assert.ok(missing.failures.includes('expected_project_id_required'));
  assert.ok(noHash.failures.includes('expected_backend_export_hash_required'));
  assert.ok(wrongHash.failures.includes('expected_backend_export_hash_mismatch'));
  assert.ok(wrong.failures.includes('expected_project_id_mismatch'));
  assert.equal(correct.ok,true,JSON.stringify(correct.failures));
  assert.equal(correct.projectBound,true);
  assert.equal(correct.productionReady,false);
 }finally{rmSync(root,{recursive:true,force:true});}
});
test('Tampering with contract hash, project identity or handoff signature fails closed',()=>{
 const root=fixture();try{
  change(root,'assets/contracts/contract.json',c=>c.contractHash='0'.repeat(64));
  assert.ok(verify(root).failures.includes('handoff_backend_identity_mismatch'));
  assert.ok(verify(root).failures.includes('contract_content_hash_mismatch'));
  change(root,'assets/contracts/contract.json',c=>c.contractHash=JSON.parse(readFileSync(join(app,'assets/contracts/contract.json'))).contractHash);
  change(root,'assets/contracts/flutter-handoff.json',h=>h.backend.project.id='different');
  assert.ok(verify(root).failures.includes('handoff_integrity_mismatch'));
  assert.ok(verify(root).failures.includes('handoff_backend_identity_mismatch'));
 }finally{rmSync(root,{recursive:true,force:true});}
});
test('Corrupt mobile core hash and duplicate operation IDs are rejected',()=>{
 const root=fixture();try{
  change(root,'assets/contracts/mobile-core-operations.json',c=>c.operations[0].path='/wrong');
  assert.ok(verify(root).failures.includes('mobile_core_integrity_mismatch'));
  change(root,'assets/contracts/mobile-core-operations.json',c=>{c.operations[0].path='/auth/login';c.operations[1].operationId=c.operations[0].operationId;c.operationsHash=sha(c.operations)});
  assert.ok(verify(root).failures.includes('invalid_mobile_core_operation'));
 }finally{rmSync(root,{recursive:true,force:true});}
});
test('Backend readiness flag without imported contract is rejected',()=>{
 const root=fixture();try{
  change(root,'assets/config/backend.json',c=>c.contractImported=false);
  assert.ok(verify(root).failures.includes('backend_configuration_not_imported'));
 }finally{rmSync(root,{recursive:true,force:true});}
});
test('A genuine empty-business-API application can pass with an explicitly pinned project',()=>{
 const root=fixture();try{
  rebindProject(root,'auth-only-production','auth-only');
  const expectedHash=JSON.parse(readFileSync(join(root,'assets/contracts/contract.json'))).contractHash;
  const result=verify(root,{mode:'project',expectedProjectId:'auth-only-production',expectedContractHash:expectedHash});
  assert.equal(result.ok,true,JSON.stringify(result));
  assert.equal(result.operationCount,0);
 }finally{rmSync(root,{recursive:true,force:true});}
});

test('Contract mutation with unchanged backend digest must fail even when handoff is untouched',()=>{
 const root=fixture();try{
  change(root,'assets/contracts/contract.json',c=>c.project.name='modified-without-resigning');
  assert.ok(verify(root).failures.includes('contract_content_hash_mismatch'));
 }finally{rmSync(root,{recursive:true,force:true});}
});
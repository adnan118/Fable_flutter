import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,mkdirSync,copyFileSync,readFileSync,writeFileSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join,dirname} from 'node:path';
import {createHash} from 'node:crypto';
import {spawnSync} from 'node:child_process';
import {verifyStage4FeatureBinding} from '../tools/verify-stage4-feature-binding.mjs';

const files=[
 'assets/config/backend.json',
 'assets/contracts/contract.json',
 'assets/contracts/flutter-handoff.json',
 'assets/contracts/openapi.json',
 'assets/contracts/mobile-core-operations.json',
 '.fable/mobile-features.json',
];
const sha=o=>createHash('sha256').update(JSON.stringify(o)).digest('hex');
const canonical=v=>Array.isArray(v)?v.map(canonical):
 v&&typeof v==='object'?
 Object.fromEntries(Object.entries(v).sort(([a],[b])=>a.localeCompare(b))
 .map(([k,x])=>[k,canonical(x)])):v;
function fixture(){
 const root=mkdtempSync(join(tmpdir(),'fable-rc153-'));
 for(const file of files){
   const target=join(root,file);mkdirSync(dirname(target),{recursive:true});
   copyFileSync(file,target);
 }
 return root;
}
const read=(root,path)=>JSON.parse(readFileSync(join(root,path),'utf8'));
function write(root,path,object){
 const dest=join(root,path);mkdirSync(dirname(dest),{recursive:true});
 writeFileSync(dest,JSON.stringify(object,null,2)+'\n');
}
function change(root,path,fn){const x=read(root,path);fn(x);write(root,path,x);}
function realProject(root,id='rc153-synthetic-project'){
 let hash;
 change(root,'assets/contracts/contract.json',c=>{
   c.project.id=id;c.project.name='isolated-stage4-fixture';
   delete c.contractHash;hash=sha(canonical(c));c.contractHash=hash;
 });
 change(root,'assets/contracts/flutter-handoff.json',h=>{
   h.backend.project.id=id;h.backend.project.name='isolated-stage4-fixture';
   h.backend.contractHash=hash;
   delete h.manifestHash;h.manifestHash=sha(h);
 });
 change(root,'assets/contracts/mobile-core-operations.json',c=>{
   c.backendContractHash=hash;
 });
 change(root,'.fable/mobile-features.json',m=>{
   m.backendContractHash=hash;
   m.selectionSource='verified-backend-project:'+id;
 });
 write(root,'.fable/frontend-setup.json',{
   kind:'fable.flutter-frontend-setup',source:'backend-contract-export',
   backendAuthority:true,projectBound:true,projectId:id,contractHash:hash,
 });
 write(root,'.fable/last-feature-sync.json',{
   kind:'fable.flutter-feature-sync',projectId:id,contractHash:hash,
 });
 return {id,hash};
}
test('RC153 starter preserves all 17 optional packages without claiming live backend',()=>{
 const root=fixture();try{
   const r=verifyStage4FeatureBinding(root,{mode:'source'});
   assert.equal(r.ok,true,JSON.stringify(r.failures));
   assert.equal(r.selectedFeatureCount,17);
   assert.equal(r.fixture,true);
   assert.equal(r.projectBound,false);
   assert.equal(r.productionReady,false);
   assert.equal(r.liveE2EVerified,false);
   assert.equal(r.contractHash,read(root,'assets/contracts/contract.json').contractHash);
 }finally{rmSync(root,{recursive:true,force:true});}
});
test('RC153 rejects fake project approval even with fixture expected ID and hash',()=>{
 const root=fixture();try{
   const c=read(root,'assets/contracts/contract.json');
   const r=verifyStage4FeatureBinding(root,{
     mode:'project',expectedProjectId:c.project.id,expectedContractHash:c.contractHash,
   });
   assert.equal(r.ok,false);
   assert.ok(r.failures.includes('fixture_project_not_accepted'));
   assert.equal(r.projectBound,false);
 }finally{rmSync(root,{recursive:true,force:true});}
});
test('RC153 rejects stale or malformed selected-feature hash',()=>{
 const root=fixture();try{
   change(root,'.fable/mobile-features.json',m=>m.backendContractHash='0'.repeat(64));
   const stale=verifyStage4FeatureBinding(root);
   assert.ok(stale.failures.includes('mobile_feature_contract_hash_mismatch'));
   change(root,'.fable/mobile-features.json',m=>m.backendContractHash='invalid');
   assert.ok(verifyStage4FeatureBinding(root).failures.includes('invalid_mobile_feature_contract_hash'));
 }finally{rmSync(root,{recursive:true,force:true});}
});
test('RC153 rejects duplicated or contradictory optional selection',()=>{
 const root=fixture();try{
   change(root,'.fable/mobile-features.json',m=>m.features.push('auth'));
   assert.ok(verifyStage4FeatureBinding(root).failures.includes('invalid_mobile_features'));
   change(root,'.fable/mobile-features.json',m=>{
     m.features=m.features.filter((v,i)=>i!==m.features.length-1);
     m.capabilities=['auth'];
   });
   assert.ok(verifyStage4FeatureBinding(root).failures.includes('capabilities_features_mismatch'));
 }finally{rmSync(root,{recursive:true,force:true});}
});
test('RC153 real project requires all independent binding and wizard provenance',()=>{
 const root=fixture();try{
   const {id,hash}=realProject(root);
   const opts={mode:'project',expectedProjectId:id,expectedContractHash:hash};
   let r=verifyStage4FeatureBinding(root,opts);
   assert.equal(r.ok,true,JSON.stringify(r.failures));
   assert.equal(r.projectBound,true);
   assert.equal(r.productionReady,false);
   assert.equal(r.liveE2EVerified,false);
   change(root,'.fable/mobile-features.json',m=>m.backendContractHash=null);
   r=verifyStage4FeatureBinding(root,opts);
   assert.ok(r.failures.includes('mobile_feature_contract_unpinned'));
   change(root,'.fable/mobile-features.json',m=>m.backendContractHash=hash);
   change(root,'.fable/last-feature-sync.json',m=>m.contractHash='f'.repeat(64));
   r=verifyStage4FeatureBinding(root,opts);
   assert.ok(r.failures.includes('feature_sync_provenance_missing_or_stale'));
 }finally{rmSync(root,{recursive:true,force:true});}
});
test('RC153 cannot self-approve a real project with an unrelated expected hash',()=>{
 const root=fixture();try{
   const {id}=realProject(root);
   const r=verifyStage4FeatureBinding(root,{
     mode:'project',expectedProjectId:id,expectedContractHash:'0'.repeat(64),
   });
   assert.ok(r.failures.includes('fable:expected_backend_export_hash_mismatch'));
   assert.equal(r.projectBound,false);
 }finally{rmSync(root,{recursive:true,force:true});}
});
test('RC153 Other Backend never inherits a Fable hash or is falsely accepted',()=>{
 const root=fixture();try{
   change(root,'assets/config/backend.json',c=>{
     c.backend={kind:'other',adapter:'openapi',status:'ready'};
   });
   const source=verifyStage4FeatureBinding(root);
   assert.equal(source.ok,true,JSON.stringify(source.failures));
   assert.equal(source.backendKind,'other');
   assert.equal(source.projectBound,false);
   assert.equal(source.contractHash,null);
   const project=verifyStage4FeatureBinding(root,{mode:'project'});
   assert.ok(project.failures.includes('other_backend_independent_project_gate_required'));
   change(root,'.fable/mobile-features.json',m=>m.backendContractHash='1'.repeat(64));
   assert.ok(verifyStage4FeatureBinding(root).failures.includes('other_backend_must_not_use_fable_contract_hash'));
 }finally{rmSync(root,{recursive:true,force:true});}
});
test('RC153 CLI returns nonzero for unpinned project instead of a green deploy claim',()=>{
 const root=fixture();try{
   const command=spawnSync(process.execPath,['tools/verify-stage4-feature-binding.mjs','--root',root,'--mode','project',
      '--expected-project-id','test-project','--expected-contract-hash','1'.repeat(64)],{encoding:'utf8'});
   assert.equal(command.status,2,command.stderr);
   assert.equal(JSON.parse(command.stdout).productionReady,false);
 }finally{rmSync(root,{recursive:true,force:true});}
});

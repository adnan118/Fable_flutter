import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const read=p=>JSON.parse(readFileSync(new URL('../'+p,import.meta.url),'utf8'));
const ledger=read('docs/integrations/FABLE-FLUTTER-PARITY-MASTER.json');
const gaps=read('docs/integrations/FABLE-FINAL-CLOSURE-W0-GAP-REGISTER.json');
test('01 closeout inventory schema and source lineage are explicit',()=>{
 assert.equal(gaps.schemaVersion,1);
 assert.equal(gaps.kind,'fable.final-project-closure-gap-register');
 assert.equal(gaps.authoritativeSources.flutterLedgerPath,'docs/integrations/FABLE-FLUTTER-PARITY-MASTER.json');
});
test('02 exactly all 17 families are present and unique',()=>{
 const ids=gaps.familyRows.map(f=>f.id);
 assert.equal(ids.length,17);assert.equal(new Set(ids).size,17);
 assert.deepEqual([...ids].sort(),ledger.features.map(f=>f.id).sort());
});
test('03 none of 17 family completion flags is promoted by inventory creation',()=>{
 for(const f of gaps.familyRows){
  const actual=ledger.features.find(x=>x.id===f.id);
  assert.equal(f.complete,actual.complete);assert.equal(f.liveE2EVerified,actual.liveE2EVerified);
  assert.equal(f.complete,false);assert.equal(f.liveE2EVerified,false);
 }
});
test('04 all known ledger gaps are represented with concrete stable IDs and OPEN status',()=>{
 for(const row of gaps.familyRows){
  const old=ledger.features.find(f=>f.id===row.id);
  assert.equal(row.gaps.length,old.gaps.length,row.id);
  for(let i=0;i<row.gaps.length;i++){
   const g=row.gaps[i];assert.equal(g.description,old.gaps[i]);
   assert.equal(g.status,'OPEN');
   assert.match(g.id,/^FAM-[A-Z_]+-\d{2}$/);
  }
 }
});
test('05 wizard source evidence and operation gaps remain unverified as recorded',()=>{
 for(const row of gaps.familyRows){
  const old=ledger.features.find(f=>f.id===row.id);
  assert.equal(row.wizardStatus,old.wizardStatus);
  assert.equal(row.operationCoverage,old.operationCoverage);
  assert.deepEqual(row.existingFrontendSources,old.frontendEvidence);
 }
});
test('06 each of 12 developer/agent Fable/Other fixture scenarios exists exactly once',()=>{
 const expected=new Set(['fable','other'].flatMap(b=>['developer','agent'].flatMap(i=>
  ['minimal','standard','complex'].map(p=>[b,i,p].join(':')))));
 const actual=gaps.generatedProjectMatrix.map(r=>[r.backend,r.initiator,r.profile].join(':'));
 assert.equal(actual.length,12);assert.equal(new Set(actual).size,12);
 assert.deepEqual(new Set(actual),expected);
});
test('07 no generated-project scenario claims acceptance or real build evidence',()=>{
 for(const p of gaps.generatedProjectMatrix){
  assert.equal(p.status,'PENDING');assert.equal(p.buildEvidence,null);
  assert.equal(p.contractEvidence,null);assert.equal(p.securityEvidence,null);
 }
});
test('08 known generator and wizard binding gaps are explicitly in the global backlog',()=>{
 const ids=new Set(gaps.crossCuttingOpen.map(g=>g.id));
 for(const id of ['WIZ-FRONT-BINDINGS','WIZ-FRONT-GUIDED-AGENT',
  'WIZ-BACK-GUIDED-AGENT','GEN-BACKEND-OUTPUT','HANDOFF-FINGERPRINT'])
 assert.ok(ids.has(id),id);
});
test('09 live toolchain/provider checks have user ownership, not fake assistant PASS',()=>{
 const expected=['TOOLCHAIN-BACKEND','TOOLCHAIN-FLUTTER','REAL-BACKEND-PROVIDERS'];
 for(const key of expected){
  const row=gaps.crossCuttingOpen.find(x=>x.id===key);
  assert.equal(row.owner,'user');assert.equal(row.status,'NEEDS_OWNER_EXECUTION');
 }
});
test('10 production human authorization remains separate and unverified',()=>{
 const row=gaps.crossCuttingOpen.find(x=>x.id==='HUMAN-PRODUCTION-APPROVAL');
 assert.equal(row.status,'NEEDS_INDEPENDENT_APPROVAL');
 assert.equal(gaps.acceptancePolicy.productionHumanApprovalSeparate,true);
 assert.equal(gaps.acceptancePolicy.simulatedIsNotLiveE2E,true);
});
test('11 Fable and Other Backend maintain incompatible DPoP policies',()=>{
 assert.equal(gaps.acceptancePolicy.fableFlutterDpopDefault,'required');
 assert.equal(gaps.acceptancePolicy.otherBackendFableDpop,'forbidden');
 assert.equal(gaps.acceptancePolicy.generatedOperationsMayBeInvented,false);
});
test('12 no unknown family omissions or fabricated successful tests are present',()=>{
 assert.equal(gaps.familyCount,ledger.featureCount);
 assert.ok(gaps.familyRows.every(f=>f.functionalAcceptanceEvidence.length===0&&
   f.userRealEnvironmentEvidence.length===0));
 assert.ok(gaps.crossCuttingOpen.every(f=>f.status!=='PASS'));
});

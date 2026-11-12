import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {auditClosureRegister} from '../tools/closure-gap-audit.mjs';
import {runClosureAudit} from '../tools/closure-gap-audit-cli.mjs';
const read=name=>JSON.parse(readFileSync(new URL('../docs/integrations/'+name,import.meta.url),'utf8'));
const source=read('FABLE-FLUTTER-PARITY-MASTER.json');
const register=read('FABLE-FINAL-CLOSURE-W0-GAP-REGISTER.json');
const copy=x=>JSON.parse(JSON.stringify(x));
const mutate=(fn)=>{const a=copy(source),b=copy(register);fn(a,b);return()=>auditClosureRegister(a,b)};
test('01 W0 register audits as BLOCKED (not completed)',()=>{
 const x=auditClosureRegister(source,register);
 assert.equal(x.counts.families,17);assert.equal(x.counts.sourceGapItems,60);
 assert.equal(x.counts.crossCuttingItems,10);assert.equal(x.counts.wizardScenarios,12);
 assert.equal(x.counts.outstanding,82);assert.equal(x.gateStatus,'BLOCKED');
});
test('02 W0 audit cannot approve production or live E2E',()=>{
 const x=auditClosureRegister(source,register);
 assert.equal(x.productionReady,false);assert.equal(x.liveE2EVerified,false);
 assert.equal(x.evidenceCryptographicallyVerified,false);assert.equal(x.releaseDecision,'NO_GO');
});
test('03 deletion of a feature gap from BOTH master and register is rejected by historical checksum',()=>{
 assert.throws(mutate((a,b)=>{a.features[0].gaps.pop();b.familyRows[0].gaps.pop()}),/HISTORICAL_60_GAPS_CHANGED/);
});
test('04 edited source and register gap descriptions cannot rewrite historical evidence',()=>{
 assert.throws(mutate((a,b)=>{a.features[0].gaps[0]+=' changed';b.familyRows[0].gaps[0].description+=' changed'}),/HISTORICAL_60_GAPS_CHANGED/);
});
test('05 missing or duplicate families refused',()=>{
 assert.throws(mutate((a,b)=>{b.familyRows[1].id=b.familyRows[0].id}),/FEATURE_DUPLICATE_OR_MISSING/);
 assert.throws(mutate((a,b)=>{b.familyRows.pop()}),/FAMILIES_INCOMPLETE/);
});
test('06 accepted gap needs actual source/test/artifact/reviewer PASS evidence',()=>{
 assert.throws(mutate((a,b)=>{b.familyRows[0].gaps[0].status='ACCEPTED'}),/EVIDENCE_MISSING/);
});
test('07 evidence cannot be promoted using a bad SHA or failed test',()=>{
 assert.throws(mutate((a,b)=>{b.familyRows[0].gaps[0].status='ACCEPTED';
   b.familyRows[0].gaps[0].evidence=[{sourceCommit:'invalid',testCommand:'fake',artifactRef:'file',reviewer:'x',result:'PASS'}]}),/EVIDENCE_INCOMPLETE/);
});
test('08 feature completion cannot be switched on without updating master and evidence',()=>{
 assert.throws(mutate((a,b)=>{b.familyRows[0].complete=true}),/FEATURE_FLAG_DRIFT/);
});
test('09 no claimed live E2E without functional completion and separate proof',()=>{
 assert.throws(mutate((a,b)=>{b.familyRows[0].liveE2EVerified=true}),/FEATURE_FLAG_DRIFT/);
});
test('10 missing required Wizard/real-provider/human-approval work item rejected',()=>{
 assert.throws(mutate((a,b)=>{b.crossCuttingOpen=b.crossCuttingOpen.filter(v=>v.id!=='WIZ-BACK-GUIDED-AGENT')}),/CROSS_BASELINE_REMOVED/);
});
test('11 duplicated cross work item rejected',()=>{
 assert.throws(mutate((a,b)=>{b.crossCuttingOpen.push({...b.crossCuttingOpen[0]})}),/CROSS_DUPLICATE/);
});
test('12 missing project fixture cannot pass the Wizard matrix',()=>{
 assert.throws(mutate((a,b)=>{b.generatedProjectMatrix.pop()}),/WIZARD_CASES_INCOMPLETE/);
});
test('13 falsely accepted project needs build, contract and security evidence',()=>{
 assert.throws(mutate((a,b)=>{b.generatedProjectMatrix[0].status='ACCEPTED'}),/WIZARD_OUTPUT_MISSING/);
});
test('14 strict CLI reports outstanding 82 and exits nonzero',()=>{
 let printed;const code=runClosureAudit(['--strict'],v=>printed=JSON.parse(v));
 assert.equal(code,2);assert.equal(printed.counts.outstanding,82);
 assert.equal(printed.productionReady,false);
});
test('15 read-only report CLI rejects unknown and duplicate flags',()=>{
 assert.throws(()=>runClosureAudit(['--apply']),/UNSUPPORTED_ARGUMENTS/);
 assert.throws(()=>runClosureAudit(['--strict','--strict']),/UNSUPPORTED_ARGUMENTS/);
});

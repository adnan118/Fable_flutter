/**
 * W0.3 — read-only, fail-closed audit of the complete feature/Wizard register.
 * No generated-project, live E2E, human attestation or production authorization.
 */
const BASELINE_COUNT=60,BASELINE_FNV='f04b695d';
const FAMILIES=17,ROLES=new Set(['backend','flutter','both','user']);
const GATES=new Set(Array.from({length:9},(_,i)=>'W'+i));
const GAP_STATES=new Set(['OPEN','SOURCE_IMPLEMENTED','TESTED_AVAILABLE','NEEDS_OWNER_E2E','ACCEPTED']);
const CROSS_STATES=new Set(['CONFIRMED_OPEN','UNVERIFIED','NEEDS_FINAL_MATRIX_TEST','NEEDS_GENERATED_SCENARIOS','NEEDS_OWNER_EXECUTION','NEEDS_INDEPENDENT_APPROVAL','SOURCE_IMPLEMENTED','TESTED_AVAILABLE','ACCEPTED']);
const WIZ_STATES=new Set(['PENDING','GENERATED','TESTED_AVAILABLE','NEEDS_OWNER_E2E','ACCEPTED']);
const SHA=/^[a-f0-9]{40}$/;
const required=(condition,code)=>{if(!condition)throw Error('CLOSURE_AUDIT_INVALID:'+code);};
const fId=(family,index)=>'FAM-'+family.toUpperCase()+'-'+String(index+1).padStart(2,'0');
const BASE_CROSS=['WIZ-FRONT-BINDINGS','WIZ-BACK-GUIDED-AGENT','WIZ-FRONT-GUIDED-AGENT','GEN-BACKEND-OUTPUT',
 'HANDOFF-FINGERPRINT','OTHER-BACKEND-ISOLATION','TOOLCHAIN-BACKEND','TOOLCHAIN-FLUTTER',
 'REAL-BACKEND-PROVIDERS','HUMAN-PRODUCTION-APPROVAL'];
function evidence(records,label){
 required(Array.isArray(records)&&records.length>0,label+':EVIDENCE_MISSING');
 for(const x of records)required(x&&typeof x==='object'&&!Array.isArray(x)&&
  SHA.test(x.sourceCommit)&&typeof x.testCommand==='string'&&x.testCommand.length>3&&
  typeof x.artifactRef==='string'&&x.artifactRef.length>3&&
  typeof x.reviewer==='string'&&x.reviewer.length>1&&x.result==='PASS',label+':EVIDENCE_INCOMPLETE');
}
function frozenHash(rows){
 const sorted=[...rows].sort().join('\n');let n=2166136261;
 for(const c of sorted)n=Math.imul(n^c.charCodeAt(0),16777619)>>>0;
 return n.toString(16).padStart(8,'0');
}
export function auditClosureRegister(ledger,register){
 required(ledger&&typeof ledger==='object'&&register&&typeof register==='object','SOURCE_REQUIRED');
 required(register.schemaVersion===1&&register.kind==='fable.final-project-closure-gap-register','REGISTER_SCHEMA');
 required(Array.isArray(ledger.features)&&ledger.features.length===FAMILIES&&
  register.familyCount===FAMILIES&&Array.isArray(register.familyRows)&&register.familyRows.length===FAMILIES,'FAMILIES_INCOMPLETE');
 const byId=new Map(),seen=new Set(),gapEntries=[],blockers=[];
 for(const f of ledger.features){
  required(typeof f?.id==='string'&&!byId.has(f.id)&&Array.isArray(f.gaps),'LEDGER_DUPLICATE_OR_INVALID');
  byId.set(f.id,f);
  for(let i=0;i<f.gaps.length;i++)gapEntries.push(fId(f.id,i)+':'+f.gaps[i]);
 }
 // Even if both source ledger and register are wrongly edited, baseline is preserved.
 required(gapEntries.length===BASELINE_COUNT&&frozenHash(gapEntries)===BASELINE_FNV,'HISTORICAL_60_GAPS_CHANGED');
 for(const row of register.familyRows){
  const original=byId.get(row?.id);
  required(original&&!seen.has(row.id)&&Array.isArray(row.gaps),'FEATURE_DUPLICATE_OR_MISSING');
  seen.add(row.id);
  required(row.complete===original.complete&&row.liveE2EVerified===original.liveE2EVerified,'FEATURE_FLAG_DRIFT:'+row.id);
  required(row.gaps.length===original.gaps.length,'FEATURE_GAPS_REMOVED:'+row.id);
  for(let i=0;i<original.gaps.length;i++){
   const g=row.gaps[i],id=fId(row.id,i);
   required(g?.id===id&&g.description===original.gaps[i]&&GAP_STATES.has(g.status),'GAP_REWRITTEN_OR_UNRECOGNIZED:'+id);
   if(g.status!=='OPEN')evidence(g.evidence,id);
   if(g.status!=='ACCEPTED')blockers.push({id,gate:'W6',owner:'flutter',status:g.status});
  }
  if(row.complete){
   required(row.gaps.every(g=>g.status==='ACCEPTED'),'FEATURE_PREMATURE:'+row.id);
   evidence(row.functionalAcceptanceEvidence,'FEATURE:'+row.id);
  }
  if(row.liveE2EVerified){
   required(row.complete===true,'E2E_PREMATURE:'+row.id);
   evidence(row.userRealEnvironmentEvidence,'FEATURE_E2E:'+row.id);
  }
 }
 required(seen.size===byId.size,'FEATURE_OMITTED');
 required(Array.isArray(register.crossCuttingOpen),'CROSS_ITEMS_MISSING');
 const cross=new Set();
 for(const item of register.crossCuttingOpen){
  required(item&&typeof item.id==='string'&&!cross.has(item.id),'CROSS_DUPLICATE');
  required(GATES.has(item.gate)&&CROSS_STATES.has(item.status)&&ROLES.has(item.owner),'CROSS_INVALID:'+item.id);
  cross.add(item.id);
  if(item.status==='ACCEPTED')evidence(item.evidence,'CROSS:'+item.id);
  else blockers.push({id:item.id,gate:item.gate,owner:item.owner,status:item.status});
 }
 for(const id of BASE_CROSS)required(cross.has(id),'CROSS_BASELINE_REMOVED:'+id);
 required(Array.isArray(register.generatedProjectMatrix)&&register.generatedProjectMatrix.length===12,'WIZARD_CASES_INCOMPLETE');
 const wizard=new Set();
 for(const row of register.generatedProjectMatrix){
  const expected='WIZ-'+String(row?.backend).toUpperCase()+'-'+String(row?.initiator).toUpperCase()+'-'+String(row?.profile).toUpperCase();
  required(row?.id===expected&&['fable','other'].includes(row.backend)&&
   ['developer','agent'].includes(row.initiator)&&['minimal','standard','complex'].includes(row.profile)&&
   WIZ_STATES.has(row.status)&&!wizard.has(expected),'WIZARD_CASE_INVALID:'+expected);
  wizard.add(expected);
  if(row.status==='ACCEPTED'){
   required(typeof row.generatedProjectPath==='string'&&row.generatedProjectPath.length>3,'WIZARD_OUTPUT_MISSING:'+expected);
   evidence(row.buildEvidence,expected+':BUILD');
   evidence(row.contractEvidence,expected+':CONTRACT');
   evidence(row.securityEvidence,expected+':SECURITY');
  }else blockers.push({id:expected,gate:'W4',owner:'both',status:row.status});
 }
 for(const b of ['FABLE','OTHER'])for(const i of ['DEVELOPER','AGENT'])
  for(const p of ['MINIMAL','STANDARD','COMPLEX'])
   required(wizard.has('WIZ-'+b+'-'+i+'-'+p),'WIZARD_SCENARIO_REMOVED');
 blockers.sort((a,b)=>a.id.localeCompare(b.id,'en'));
 return {kind:'fable.final-closure-audit',schemaVersion:1,
  counts:{families:seen.size,sourceGapItems:gapEntries.length,crossCuttingItems:cross.size,
   wizardScenarios:wizard.size,outstanding:blockers.length},
  blockers,gateStatus:blockers.length?'BLOCKED':'SELF_REPORTED_REVIEW_REQUIRED',
  unverifiedRealEnvironment:register.crossCuttingOpen.filter(x=>x.owner==='user'&&x.status!=='ACCEPTED').map(x=>x.id).sort(),
  evidenceCryptographicallyVerified:false,fullWizardGeneratedProjectsVerified:false,
  liveE2EVerified:false,productionReady:false,releaseDecision:'NO_GO'};
}

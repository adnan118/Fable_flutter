import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,mkdirSync,readFileSync,writeFileSync,copyFileSync,rmSync,existsSync} from 'node:fs';
import {resolve,join,dirname} from 'node:path';
import {tmpdir} from 'node:os';
import {createHash} from 'node:crypto';
import {importBackendDecisions,manualFrontendDecisions,reconcileManualWithBackend,saveFrontendSetup} from '../tools/flutter-setup-wizard.mjs';

const digest=v=>createHash('sha256').update(JSON.stringify(v)).digest('hex');
const canonical=v=>Array.isArray(v)?v.map(canonical):v&&typeof v==='object'?
  Object.fromEntries(Object.entries(v).sort(([a],[b])=>a.localeCompare(b)).map(([k,w])=>[k,canonical(w)])):v;
const files=['contract.json','flutter-handoff.json','openapi.json','mobile-core-operations.json'];
const read=p=>JSON.parse(readFileSync(p,'utf8'));
const write=(p,x)=>writeFileSync(p,JSON.stringify(x,null,2));
function fixture(){
  const root=mkdtempSync(join(tmpdir(),'frontend-decisions-'));
  const dir=join(root,'backend-export');
  mkdirSync(dir,{recursive:true});
  for(const file of files)copyFileSync(resolve('assets/contracts',file),join(dir,file));
  const contract=read(join(dir,'contract.json'));
  const handoff=read(join(dir,'flutter-handoff.json'));
  const core=read(join(dir,'mobile-core-operations.json'));
  contract.project.id='real-project-demo';
  contract.project.name='demo';
  const session={mode:'multi',maxActive:0,overflow:'revoke-oldest',
    runtimeEndpoint:'/auth/session-policy',runtimeAuthoritative:true};
  const frontendSetup={
    schemaVersion:1,kind:'fable.frontend-setup-decisions',source:'backend-project-manifest',
    projectId:contract.project.id,
    decisions:{project:{id:contract.project.id,name:'demo'},
      authentication:{sessions:session},accounts:{identityModel:'multi-profile'}},
    steps:[{id:'authentication',frontendAction:'Sync auth from Backend',status:'required-review'}],
    authority:{backend:true}
  };
  contract.core.auth.sessionPolicy=session;
  contract.core.frontendSetup=frontendSetup;
  delete contract.contractHash;
  contract.contractHash=digest(canonical(contract));
  write(join(dir,'contract.json'),contract);
  handoff.backend.contractHash=contract.contractHash;
  handoff.backend.project={id:contract.project.id,name:contract.project.name};
  handoff.frontendSetup=frontendSetup;
  delete handoff.manifestHash;
  handoff.manifestHash=digest(handoff);
  write(join(dir,'flutter-handoff.json'),handoff);
  core.backendContractHash=contract.contractHash;
  core.operations.push({operationId:'auth.session-policy',method:'GET',
    path:'/auth/session-policy',public:true});
  core.operationsHash=digest(core.operations);
  write(join(dir,'mobile-core-operations.json'),core);
  return {root,dir,contract};
}
test('Automatic Backend → Flutter setup is verified, maps decisions and applies only when explicit',()=>{
  const f=fixture();
  try{
    const snapshot=importBackendDecisions(f.dir,{
      expectedProjectId:f.contract.project.id,expectedContractHash:f.contract.contractHash
    });
    assert.equal(snapshot.projectBound,true);
    assert.equal(snapshot.decisionSnapshot.decisions.authentication.sessions.maxActive,0);
    assert.equal(saveFrontendSetup(f.root,snapshot,{apply:false}).applied,false);
    assert.equal(existsSync(join(f.root,'assets/config/frontend-setup.json')),false);
    const result=saveFrontendSetup(f.root,snapshot,{apply:true,sourceDir:f.dir});
    assert.equal(result.applied,true);
    assert.deepEqual(read(join(f.root,'assets/config/frontend-setup.json')).decisionSnapshot,
      snapshot.decisionSnapshot);
    assert.equal(read(join(f.root,'assets/contracts/contract.json')).contractHash,f.contract.contractHash);
  }finally{rmSync(f.root,{recursive:true,force:true});}
});
test('Stale backend decisions, missing route and mismatched project pins are rejected',()=>{
  const f=fixture();
  try{
    assert.throws(()=>importBackendDecisions(f.dir,{expectedProjectId:'different',
      expectedContractHash:f.contract.contractHash}),/verification failed/);
    const handoff=read(join(f.dir,'flutter-handoff.json'));
    handoff.frontendSetup.decisions.accounts.identityModel='single';
    delete handoff.manifestHash;
    handoff.manifestHash=digest(handoff);
    write(join(f.dir,'flutter-handoff.json'),handoff);
    assert.throws(()=>importBackendDecisions(f.dir),/verification failed|conflicting/);
  }finally{rmSync(f.root,{recursive:true,force:true});}
});
test('Manual mode produces a clearly unverified frontend draft only',()=>{
  const manual=manualFrontendDecisions({
    kind:'manual.frontend-setup-decisions',schemaVersion:1,
    projectId:'other-backend',decisions:{localization:{supportedLocales:['ar']}},
    steps:[{id:'localization'}]
  });
  assert.equal(manual.backendAuthority,false);
  assert.equal(manual.projectBound,false);
  assert.equal(manual.implementation.status,'unverified-backend-bindings');
  assert.throws(()=>manualFrontendDecisions({projectId:'a',decisions:{},steps:[]}));
});

test('Manually entered Fable decisions must exactly match the imported Backend choices',()=>{
  const f=fixture();
  try{
    const verified=importBackendDecisions(f.dir);
    const accepted=manualFrontendDecisions({schemaVersion:1,
      kind:'manual.frontend-setup-decisions',projectId:f.contract.project.id,
      decisions:{authentication:{sessions:{mode:'multi',maxActive:0}}},
      steps:[{id:'authentication'}]});
    const result=reconcileManualWithBackend(accepted.decisionSnapshot,verified);
    assert.equal(result.backendAuthority,true);
    assert.equal(result.mode,'manual-review');
    const conflicting=manualFrontendDecisions({schemaVersion:1,
      kind:'manual.frontend-setup-decisions',projectId:f.contract.project.id,
      decisions:{authentication:{sessions:{mode:'single'}}},steps:[]});
    assert.throws(()=>reconcileManualWithBackend(conflicting.decisionSnapshot,verified),/conflicts/);
  }finally{rmSync(f.root,{recursive:true,force:true});}
});

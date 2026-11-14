import test from 'node:test';
import assert from 'node:assert/strict';
import {
  copyFileSync,mkdirSync,mkdtempSync,readFileSync,rmSync,writeFileSync,
} from 'node:fs';
import {createHash} from 'node:crypto';
import {join,resolve} from 'node:path';
import {tmpdir} from 'node:os';
import {
  w4ScenarioPlan,w4ScenarioId,w4OtherManifest,runW4WizardMatrix,
} from '../tools/w4-wizard-matrix.mjs';
import {parseW4MatrixArgs} from '../tools/run-w4-wizard-matrix.mjs';

const sha=x=>createHash('sha256').update(JSON.stringify(x)).digest('hex');
const canonical=x=>Array.isArray(x)?x.map(canonical):
  x&&typeof x==='object'?Object.fromEntries(Object.entries(x)
    .sort(([a],[b])=>a.localeCompare(b)).map(([k,v])=>[k,canonical(v)])):x;
const read=p=>JSON.parse(readFileSync(p,'utf8'));
function makeFableExport(base,profile){
  const dir=join(base,'fable-'+profile);
  mkdirSync(dir,{recursive:true});
  for(const name of ['contract.json','flutter-handoff.json',
    'openapi.json','mobile-core-operations.json'])
    copyFileSync(resolve('assets/contracts',name),join(dir,name));
  const contract=read(join(dir,'contract.json'));
  const handoff=read(join(dir,'flutter-handoff.json'));
  const mobile=read(join(dir,'mobile-core-operations.json'));
  const projectId='w4-fable-'+profile;
  contract.project.id=projectId;contract.project.name='W4 '+profile;
  const sessions={mode:'multi',maxActive:0,overflow:'revoke-oldest',
    runtimeEndpoint:'/auth/session-policy',runtimeAuthoritative:true};
  const enabled=['auth','profile','localization','access_control'];
  const disabled=['notifications','media','support','social','biometrics',
    'realtime','messaging','location','payments','analytics','content'];
  if(profile!=='minimal'){enabled.push('notifications');disabled.splice(disabled.indexOf('notifications'),1);}
  if(profile==='complex'){enabled.push('media');disabled.splice(disabled.indexOf('media'),1);}
  const setup={schemaVersion:1,kind:'fable.frontend-setup-decisions',
    source:'backend-project-manifest',projectId,
    decisions:{
      project:{id:projectId,name:contract.project.name,clients:['flutter'],capabilities:['auth']},
      localization:{defaultLocale:'ar',supportedLocales:['ar','en'],rtlLocales:['ar']},
      authentication:{sessions,identityMode:'email'},
      accounts:{identityModel:'multi-profile'},
      experience:{notifications:false,media:false},
      commercial:{mode:'FREE'},
      frontendFeatures:{schemaVersion:1,source:'backend-installed-capabilities',
        enabled,disabled,clientOnlyReview:['deeplinks','offline']},
      permissions:{source:'backend-contract-and-runtime',rolesFromRuntime:true},
    },
    steps:['identity','authentication','accounts','permissions','capabilities','commercial']
      .map((id,order)=>({id,order:order+1,frontendAction:'Sync '+id,status:'required-review'})),
    authority:{backend:true},
  };
  contract.core.auth.sessionPolicy=sessions;
  contract.core.frontendSetup=setup;
  delete contract.contractHash;contract.contractHash=sha(canonical(contract));
  writeFileSync(join(dir,'contract.json'),JSON.stringify(contract));
  handoff.backend.project={id:projectId,name:contract.project.name};
  handoff.backend.contractHash=contract.contractHash;
  handoff.frontendSetup=setup;
  handoff.selection={...handoff.selection,mode:'advisory',features:null};
  delete handoff.manifestHash;handoff.manifestHash=sha(handoff);
  writeFileSync(join(dir,'flutter-handoff.json'),JSON.stringify(handoff));
  mobile.backendContractHash=contract.contractHash;
  mobile.operations.push({operationId:'auth.session-policy',method:'GET',
    path:'/auth/session-policy',public:true});
  mobile.operationsHash=sha(mobile.operations);
  writeFileSync(join(dir,'mobile-core-operations.json'),JSON.stringify(mobile));
  return {source:dir,expectedProjectId:projectId,expectedContractHash:contract.contractHash};
}

test('RC212 W4 enumerates exactly twelve unique W0 Wizard cases',()=>{
  const list=w4ScenarioPlan();
  assert.equal(list.length,12);
  assert.equal(new Set(list.map(x=>x.id)).size,12);
  assert.equal(w4ScenarioId('fable','developer','minimal'),'WIZ-FABLE-DEVELOPER-MINIMAL');
  assert.equal(w4ScenarioId('other','agent','complex'),'WIZ-OTHER-AGENT-COMPLEX');
});
test('RC212 Other Backend scenarios never invent auth/session or activate Fable DPoP',()=>{
  for(const p of ['minimal','standard','complex']){
    const manual=w4OtherManifest(p);
    assert.equal(manual.decisions.authentication.status,'unverified-external-contract');
    assert.equal(manual.decisions.authentication.sessions,null);
    assert.equal(manual.decisions.accounts.identityModel,null);
    assert.equal(manual.backendAdapter==='openapi'||manual.backendAdapter==='custom',true);
  }
});
test('RC212 matrix reports six Fable paths as BLOCKED when no real exports exist',async()=>{
  const report=await runW4WizardMatrix();
  assert.equal(report.passed,false);
  assert.equal(report.counts.scenarios,12);
  assert.equal(report.counts.blocked,6);
  assert.equal(report.counts.generated,6,JSON.stringify(report.cases.filter(x=>!x.passed),null,2));
  assert.equal(report.counts.matchingPairs,3);
  assert.equal(report.productionApproved,false);
  assert.equal(report.nativeDpopVerified,false);
});
test('RC212 simulated pinned Fable handoffs and real Guided/Agent apply paths match for all six scenario pairs',async t=>{
  const root=mkdtempSync(join(tmpdir(),'fable-w4-test-'));
  t.after(()=>rmSync(root,{recursive:true,force:true}));
  const fableExports=Object.fromEntries(['minimal','standard','complex']
    .map(profile=>[profile,makeFableExport(root,profile)]));
  const report=await runW4WizardMatrix({fableExports});
  assert.equal(report.counts.scenarios,12);
  assert.equal(report.counts.blocked,0);
  assert.equal(report.counts.failed,0,JSON.stringify(report.cases.filter(x=>!x.passed),null,2));
  assert.equal(report.counts.generated,12);
  assert.equal(report.counts.matchingPairs,6);
  assert.equal(report.paired.every(x=>x.passed),true);
  // No complete Flutter source tree was copied; source-only results never
  // satisfy final W4 or production acceptance.
  assert.equal(report.passed,false);
  assert.equal(report.realFlutterBuildVerified,false);
  assert.equal(report.liveE2EVerified,false);
});
test('RC212 rejects reused Fable source hash across independent profile choices',async t=>{
  const root=mkdtempSync(join(tmpdir(),'fable-w4-reused-'));
  t.after(()=>rmSync(root,{force:true,recursive:true}));
  const sample={source:root,expectedProjectId:'x',expectedContractHash:'a'.repeat(64)};
  await assert.rejects(
    runW4WizardMatrix({fableExports:{minimal:sample,standard:sample,complex:sample}}),
    /independently distinct/,
  );
});
test('RC212 does not write source project inside its original Flutter repository',async()=>{
  await assert.rejects(runW4WizardMatrix({
    workspaceRoot:resolve('.'),flutterSourceRoot:resolve('.'),
  }),/workspace must not overlap/);
});
test('RC212 matrix CLI rejects partial Fable pins, invalid SHA and unsupported options',()=>{
  assert.throws(()=>parseW4MatrixArgs(['--fable-minimal-export','/tmp/contract']),/requires export/);
  assert.throws(()=>parseW4MatrixArgs([
    '--fable-complex-export','/tmp/contract','--fable-complex-project-id','real',
    '--fable-complex-contract-hash','bad',
  ]),/Invalid Fable/);
  assert.throws(()=>parseW4MatrixArgs(['--unknown']),/Unsupported/);
  assert.equal(parseW4MatrixArgs(['--plan']).planOnly,true);
});

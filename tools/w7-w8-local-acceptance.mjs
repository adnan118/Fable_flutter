/**
 * RC216 — one local W0–W8 acceptance command, without GitHub Actions.
 * A successful source check never proves Android/iOS, live provider E2E,
 * independent release review, or production readiness.
 */
import {spawnSync,execFileSync} from 'node:child_process';
import {readFileSync} from 'node:fs';
import {resolve,join,basename} from 'node:path';
import {auditClosureRegister} from './closure-gap-audit.mjs';

const SHA=/^[a-f0-9]{40}$/;
const D64=/^[a-f0-9]{64}$/;
export const RELEASE_PHASES=Object.freeze(
  Array.from({length:9},(_,i)=>'W'+i));
const REAL_GATES=Object.freeze([
  'REAL_BACKEND_DATABASE_AND_PROVIDERS',
  'FLUTTER_ANDROID_HARDWARE_E2E',
  'FLUTTER_IOS_HARDWARE_E2E',
  'REAL_MULTI_DEVICE_SECURITY_DPOP',
  'INDEPENDENT_HUMAN_PRODUCTION_SIGNOFF',
]);

export function buildLocalAcceptancePlan({
  flutterRoot='.',backendRoot=null,generatedFlutterRoot=null,
  backendExportRoot=null,expectedBackendSha=null,
  expectedFlutterSha=null,projectId=null,contractHash=null,
  fableProfiles=null,withFlutterToolchain=false,
}={}){
  if(typeof withFlutterToolchain!=='boolean')
    throw Error('INVALID_NATIVE_TEST_OPTION');
  const flutter=resolve(flutterRoot);
  const backend=backendRoot?resolve(backendRoot):null;
  // Fable's executable package is nested under the private repository.
  // W1/W2 run from that package; W3's source-check requires Git repo root.
  const backendCheckout=backend&&basename(backend)==='Fable-Backend-RC66'?
    resolve(backend,'..'):backend;
  const generated=generatedFlutterRoot?resolve(generatedFlutterRoot):null;
  const exportRoot=backendExportRoot?resolve(backendExportRoot):null;
  const pinsValid=SHA.test(expectedBackendSha??'')&&
    SHA.test(expectedFlutterSha??'');
  const verifiedProject=typeof projectId==='string'&&projectId.length>2&&
    D64.test(contractHash??'');
  const allProfiles=Boolean(fableProfiles&&
    ['minimal','standard','complex'].every(p=>{
      const x=fableProfiles[p];
      return x&&typeof x.source==='string'&&
        typeof x.expectedProjectId==='string'&&x.expectedProjectId.length>2&&
        D64.test(x.expectedContractHash??'');
    }));
  const steps=[
    {id:'W1_W2_REAL_GENERATION',gate:'W1',additionalGate:'W2',
      root:backend,args:['tools/fable-w1-w2-one-shot.mjs','--full','--json'],
      requires:backend&&pinsValid?null:'BACKEND_MAIN_AND_BOTH_SOURCE_SHA_PINS_REQUIRED',
      sourceOnly:true,timeoutMs:3600000},
    {id:'W3_REAL_EXPORT_FLUTTER_IMPORT',gate:'W3',root:flutter,
      args:exportRoot&&backend&&SHA.test(expectedBackendSha??'')?[
        'tools/verify-current-w3-handoff.mjs',
        '--backend-export',exportRoot,
        '--backend-repo',backendCheckout,'--flutter-root',generated??flutter,
        '--expected-backend-sha',expectedBackendSha,'--json']:[],
      requires:exportRoot&&backend&&pinsValid?'': 'INDEPENDENT_BACKEND_EXPORT_AND_SOURCE_PINS_REQUIRED',
      sourceOnly:true,timeoutMs:240000},
    {id:'W4_TWELVE_REAL_WIZARD_PROJECTS',gate:'W4',root:flutter,
      args:['tools/run-w4-wizard-matrix.mjs','--json','--materialize',
        ...(['minimal','standard','complex'].flatMap(p=>{
          const v=fableProfiles?.[p];
          return v?['--fable-'+p+'-export',v.source,
            '--fable-'+p+'-project-id',v.expectedProjectId,
            '--fable-'+p+'-contract-hash',v.expectedContractHash]:[];
        }))],
      requires:allProfiles&&pinsValid?null:'THREE_INDEPENDENT_FABLE_PROFILE_EXPORTS_REQUIRED',
      sourceOnly:true,timeoutMs:3600000},
    {id:'W5_COMPLETE_SELECTED_SOURCE_CHAIN',gate:'W5',root:flutter,
      args:generated?['tools/run-w5-feature-flow-audit.mjs','--root',generated,
        ...(verifiedProject?['--expected-project-id',projectId,
          '--expected-contract-hash',contractHash]:[]),'--json']:[],
      requires:generated&&verifiedProject&&pinsValid?null:
        'GENERATED_FLUTTER_PROJECT_AND_INDEPENDENT_CONTRACT_PINS_REQUIRED',
      sourceOnly:true,timeoutMs:300000},
    {id:'W6_SELECTED_FAMILY_SOURCE_REGRESSIONS',gate:'W6',root:flutter,
      args:['--test','test/rc213-w5-operation-flow-audit.test.mjs',
        'test/rc214-w6-auth-race-source.test.mjs',
        'test/rc215-w6-notification-races-source.test.mjs'],
      requires:pinsValid?null:'BOTH_SOURCE_SHA_PINS_REQUIRED',
      sourceOnly:true,timeoutMs:240000},
    {id:'W6_AUTH_NOTIFICATIONS_DART_WIDGET',gate:'W6',root:flutter,
      program:'flutter',args:['test',
        'packages/fable_core/test/auth_gateway_identity_regression_test.dart',
        'packages/features/fable_auth/test/mandatory_password_change_page_test.dart',
        'packages/features/fable_notifications/test/notification_identity_navigation_rc108_test.dart'],
      requires:!withFlutterToolchain?'FLUTTER_TOOLCHAIN_EXECUTION_NOT_REQUESTED':
        pinsValid?null:'SOURCE_SHA_PINS_REQUIRED',
      sourceOnly:false,timeoutMs:1200000},
    {id:'W7_FLUTTER_ANALYZE',gate:'W7',root:flutter,program:'flutter',
      args:['analyze'],
      requires:!withFlutterToolchain?'FLUTTER_TOOLCHAIN_EXECUTION_NOT_REQUESTED':
        pinsValid?null:'SOURCE_SHA_PINS_REQUIRED',
      sourceOnly:false,timeoutMs:1200000},
    {id:'W7_FLUTTER_TEST',gate:'W7',root:flutter,program:'flutter',
      args:['test'],
      requires:!withFlutterToolchain?'FLUTTER_TOOLCHAIN_EXECUTION_NOT_REQUESTED':
        pinsValid?null:'SOURCE_SHA_PINS_REQUIRED',
      sourceOnly:false,timeoutMs:1800000},
  ];
  return {schemaVersion:1,batch:'RC216-W0-W8',flutterRoot:flutter,
    backendRoot:backend,backendCheckoutRoot:backendCheckout,
    generatedFlutterRoot:generated,
    expectedBackendSha:SHA.test(expectedBackendSha??'')?expectedBackendSha:null,
    expectedFlutterSha:SHA.test(expectedFlutterSha??'')?expectedFlutterSha:null,
    steps,realGates:[...REAL_GATES],productionApproved:false};
}

export function checkLocalGitSource(root,expected,kind) {
  if(!root||!SHA.test(expected??''))return false;
  try {
    const command=(...args)=>execFileSync('git',args,{
      cwd:root,encoding:'utf8',timeout:7000,maxBuffer:512000}).trim();
    const head=command('rev-parse','HEAD'),branch=command('symbolic-ref','--short','HEAD');
    const status=command('status','--porcelain','--untracked-files=no');
    const origin=command('remote','get-url','origin').toLowerCase();
    const wanted=kind==='backend'?'fable':'fable_flutter';
    const provider=/^(https:\/\/github\.com\/|git@github\.com:|ssh:\/\/git@github\.com\/)adnan118\//;
    const suffix=origin.replace(/\.git$/,'').split('/').at(-1).split(':').at(-1);
    return head===expected&&branch==='main'&&!status&&
      provider.test(origin)&&suffix===wanted;
  }catch{return false;}
}

function defaultRunner(step){
  const started=Date.now();
  const child=spawnSync(step.program??process.execPath,step.args,{
    cwd:step.root,encoding:'utf8',windowsHide:true,
    stdio:['ignore','pipe','pipe'],timeout:step.timeoutMs,
    maxBuffer:5*1024*1024,env:process.env,
  });
  // Never expose stdout/stderr: provider logs and endpoint values may contain
  // private metadata. Owners can rerun the exact safe command locally.
  return {exitCode:child.status,signal:child.signal??null,
    error:child.error?.code??null,durationMs:Date.now()-started};
}
export function evaluateLocalAcceptance(plan,{
  inventory=null,checkout=null,runs=[],readinessEvidence=null,
}={}){
  const sourceChecks=[];
  const runMap=new Map(runs.map(x=>[x.id,x]));
  const requiresBackend=new Set([
    'W1_W2_REAL_GENERATION','W3_REAL_EXPORT_FLUTTER_IMPORT',
    'W4_TWELVE_REAL_WIZARD_PROJECTS','W5_COMPLETE_SELECTED_SOURCE_CHAIN',
  ]);
  for(const step of plan.steps){
    const run=runMap.get(step.id);
    const missing=step.requires||
      (requiresBackend.has(step.id)&&!checkout?.backendVerified?
        'BACKEND_MAIN_SHA_NOT_VERIFIED':null)||
      (!checkout?.flutterVerified?'FLUTTER_MAIN_SHA_NOT_VERIFIED':null);
    const state=missing?'BLOCKED':
      !run?'NOT_RUN':
      run.exitCode===0&&run.signal===null&&!run.error?
        (step.sourceOnly?'SOURCE_CHECK_PASS':'LOCAL_TEST_PASS'):'FAILED';
    sourceChecks.push({id:step.id,gate:step.gate,
      ...(step.additionalGate?{additionalGate:step.additionalGate}:{}),
      state,reason:missing||(
        state==='FAILED'?'EXIT_'+String(run?.exitCode??run?.signal??run?.error):null),
      exitCode:run?.exitCode??null,durationMs:run?.durationMs??null,
      sourceOnly:step.sourceOnly});
  }
  const baselineValid=inventory?.kind==='fable.final-closure-audit'&&
    inventory?.counts?.families===17&&
    inventory?.counts?.sourceGapItems===60&&
    inventory?.counts?.crossCuttingItems===10&&
    inventory?.counts?.wizardScenarios===12;
  const gates=RELEASE_PHASES.map(gate=>{
    const checks=sourceChecks.filter(x=>x.gate===gate||x.additionalGate===gate);
    const allPassed=checks.length>0&&checks.every(x=>
      x.state==='SOURCE_CHECK_PASS'||x.state==='LOCAL_TEST_PASS');
    return {gate,sourceChecksPassed:gate==='W0'?Boolean(baselineValid):allPassed,
      status:gate==='W0'&&baselineValid?'BASELINE_VERIFIED':
        allPassed?'SOURCE_OR_LOCAL_TESTS_PASS_ACCEPTANCE_OPEN':'BLOCKED_OR_NOT_TESTED'};
  });
  const outstanding=inventory?.counts?.outstanding??null;
  return {schemaVersion:1,batch:'RC216-W0-W8',status:'PRODUCTION_NO_GO',
    sourcePins:{backend:plan.expectedBackendSha,flutter:plan.expectedFlutterSha,
      verifiedBackend:Boolean(checkout?.backendVerified),
      verifiedFlutter:Boolean(checkout?.flutterVerified)},
    baseline:{verified:Boolean(baselineValid),families:17,gaps:60,
      crossCutting:10,wizardScenarios:12,outstanding,
      issuesByGate:inventory?.blockers?Object.fromEntries(RELEASE_PHASES.map(g=>
        [g,inventory.blockers.filter(x=>x.gate===g).length])):null},
    gateStatus:gates,sourceChecks,
    ownerRequired:plan.realGates.map(id=>({id,state:'OWNER_E2E_OR_APPROVAL_REQUIRED'})),
    providedReadinessEvidenceReviewed:false,
    independentArtifactValidation:false,
    actualAndroidDeviceVerified:false,actualIosDeviceVerified:false,
    liveProviderE2EVerified:false,independentProductionApproval:false,
    // An untrusted report, local source PASS, or Git HEAD alone never
    // authorizes publication or even makes a signed release archive.
    productionReady:false,releaseDecision:'NO_GO',
    hints:{
      rerunSourceChecks:'node tools/run-w7-w8-local-acceptance.mjs --help',
      nativeAndProviders:'Run real Flutter and provider/device E2E on owner machines',
      ledger:'Complete W0 register with independently reviewed evidence before W8 signoff',
    }};
}
export function runLocalAcceptance(plan,{runner=defaultRunner,gitChecker=checkLocalGitSource}={}){
  const flutterVerified=Boolean(plan.expectedFlutterSha&&
    gitChecker(plan.flutterRoot,plan.expectedFlutterSha,'flutter'));
  const backendVerified=Boolean(plan.expectedBackendSha&&plan.backendCheckoutRoot&&
    gitChecker(plan.backendCheckoutRoot,plan.expectedBackendSha,'backend'));
  const checkout={flutterVerified,backendVerified};
  let inventory=null;
  try {
    const read=name=>JSON.parse(readFileSync(
      join(plan.flutterRoot,'docs/integrations',name),'utf8'));
    inventory=auditClosureRegister(
      read('FABLE-FLUTTER-PARITY-MASTER.json'),
      read('FABLE-FINAL-CLOSURE-W0-GAP-REGISTER.json'));
  }catch{/* Invalid / missing historical ledger is not baseline acceptance. */}
  const runs=[];
  for(const step of plan.steps){
    if(step.requires||!flutterVerified||
       (new Set(['W1_W2_REAL_GENERATION','W3_REAL_EXPORT_FLUTTER_IMPORT',
         'W4_TWELVE_REAL_WIZARD_PROJECTS','W5_COMPLETE_SELECTED_SOURCE_CHAIN'])
         .has(step.id)&&!backendVerified))continue;
    try{runs.push({id:step.id,...runner(step)});}
    catch(error){runs.push({id:step.id,exitCode:null,
      signal:null,error:error?.code??'RUNNER_ERROR',durationMs:null});}
  }
  return evaluateLocalAcceptance(plan,{inventory,checkout,runs});
}

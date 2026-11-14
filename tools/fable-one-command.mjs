/**
 * RC217 — ONE pnpm command for the complete available Fable verification suite.
 * No commands copied into a shell; all subprocesses run with explicit argv.
 * Everything executable runs in a single invocation and continues after failures.
 * Missing real inputs remain BLOCKED, never silently PASS.
 */
import {execFileSync,spawnSync} from 'node:child_process';
import {existsSync,lstatSync,mkdirSync,readFileSync,writeFileSync} from 'node:fs';
import {basename,dirname,isAbsolute,join,resolve,sep} from 'node:path';
import {auditClosureRegister} from './closure-gap-audit.mjs';
import {readSafeFeatureEvidence} from './w5-safe-source-evidence.mjs';

const SHA=/^[a-f0-9]{40}$/;
const HASH=/^[a-f0-9]{64}$/;
const PROFILES=['minimal','standard','complex'];
const TIMEOUT={node:20*60*1000,backendFast:15*60*1000,
  backendFull:60*60*1000,flutter:40*60*1000};
const OWNER_GATES=[
  'ANDROID_REAL_DEVICE',
  'IOS_REAL_DEVICE',
  'LIVE_OTP_PUSH_PAYMENT_AND_DATABASE_PROVIDERS',
  'TWO_DEVICE_DPOP_AND_SESSION_LIFECYCLE',
  'INDEPENDENT_HUMAN_RELEASE_APPROVAL',
];
const validFile=name=>typeof name==='string'&&
  /^[a-zA-Z0-9_.\/-]+$/.test(name)&&
  !name.startsWith('/')&&!name.split('/').some(x=>x==='..'||x==='.'||!x);

/** Consolidate every pnpm test:* script that is a direct Node test command. */
export function discoverExistingNodeTests(scripts,hasFile=()=>true){
  const paths=new Set(),unsupported=[];
  for(const [name,script] of Object.entries(scripts??{})){
    if(!name.startsWith('test:')||typeof script!=='string')continue;
    if(!script.startsWith('node --test '))continue;
    const parts=script.substring('node --test '.length).trim().split(/\s+/);
    if(parts.some(x=>!validFile(x))){unsupported.push(name);continue;}
    for(const path of parts){
      if(!hasFile(path))unsupported.push(name+':'+path);
      else paths.add(path);
    }
  }
  return {paths:[...paths].sort(),unsupported:[...new Set(unsupported)].sort()};
}

/**
 * Read the version-controlled Node test inventory instead of trusting only
 * package.json. RC217 skipped many older source tests without scripts.
 * Git's NUL-delimited tracked paths avoid shell parsing and untracked code.
 */
export function discoverTrackedNodeTests(root,{
  runGit=execFileSync,
  safeRead=readSafeFeatureEvidence,
}={}){
  let names;
  try {
    names=runGit('git',['ls-files','--cached','-z','--','test','tools'],{
      cwd:root,encoding:'utf8',timeout:8000,maxBuffer:8*1024*1024,
      stdio:['ignore','pipe','ignore'],
    }).split('\\0').filter(Boolean);
  }catch{
    return {files:[],rejected:[],gitInventoryVerified:false};
  }
  const files=[],rejected=[];
  for(const name of [...new Set(names)].sort()){
    if(!name.endsWith('.test.mjs'))continue;
    if(!/^(?:test|tools)\\/[a-zA-Z0-9_.\\/-]+\\.test\\.mjs$/.test(name)||
       !validFile(name)){
      rejected.push(name);continue;
    }
    try {safeRead(root,name);files.push(name);}
    catch {rejected.push(name);}
  }
  return {files,rejected,gitInventoryVerified:true};
}

export function detectBackendRoot(flutterRoot,exist=existsSync){
  const root=resolve(flutterRoot),parent=dirname(root);
  const candidates=[
    join(parent,'Fable','Fable-Backend-RC66'),
    join(parent,'Fable-Backend-RC66'),
    join(parent,'Fable','Fable-Backend-RC66','Fable-Backend-RC66'),
  ];
  return candidates.find(p=>exist(join(p,'tools/fable-w1-w2-one-shot.mjs')))??null;
}
function readOptionalInputs(root){
  const location='.fable/closeout-inputs.json';
  if(!existsSync(join(root,location)))return {};
  const doc=JSON.parse(readSafeFeatureEvidence(root,location));
  if(!doc||typeof doc!=='object'||Array.isArray(doc))
    throw Error('INVALID_RC217_LOCAL_INPUTS');
  return doc;
}
function safeExistingPath(value){
  if(typeof value!=='string'||!value.trim())return null;
  const full=resolve(value);
  return existsSync(full)?full:null;
}
function gitInfo(root){
  if(!root)return {head:null,main:false,clean:false,originVerified:false};
  try{
    const git=(...args)=>execFileSync('git',args,{
      cwd:root,encoding:'utf8',timeout:6000,maxBuffer:512000,
      stdio:['ignore','pipe','ignore']}).trim();
    const head=git('rev-parse','HEAD'),branch=git('symbolic-ref','--short','HEAD');
    const dirty=git('status','--porcelain','--untracked-files=no');
    const origin=git('remote','get-url','origin').toLowerCase();
    return {head:SHA.test(head)?head:null,main:branch==='main',
      clean:dirty.length===0,origin};
  }catch{return {head:null,main:false,clean:false,origin:null};}
}
/**
 * Find the actual Git checkout root, whether the generator resides inside
 * Fable/Fable-Backend-RC66 or a differently named checked-out project.
 * dirname(generator) is not necessarily the Git repository root.
 */
export function resolveBackendCheckoutRoot(generatorRoot,{git=execFileSync}={}){
  if(!generatorRoot)return null;
  try{
    const top=git('git',['rev-parse','--show-toplevel'],{
      cwd:generatorRoot,encoding:'utf8',timeout:7000,
      maxBuffer:102400,stdio:['ignore','pipe','ignore'],
    }).trim();
    return top?resolve(top):null;
  }catch{return null;}
}

function sourceFingerprint(root,expectedRepo,independentSha=null) {
  const git=gitInfo(root);
  const allowed=git.origin&&new RegExp(
    '^(?:https://github\\.com/|git@github\\.com:|ssh://git@github\\.com/)'+
      'adnan118/'+expectedRepo+'(?:\\.git)?$','i').test(git.origin);
  const trustedLocal=Boolean(git.head&&git.clean&&git.main&&allowed);
  return {
    head:git.head,localMainVerified:trustedLocal,
    independentPinVerified:Boolean(trustedLocal&&SHA.test(independentSha??'')&&
      independentSha===git.head),
  };
}
function backgroundInputs(input,flutterRoot,backendRoot){
  // Values are optional locally authored project paths/pins, not opaque
  // shell command fragments. Missing data remains a documented blocker.
  const generated=safeExistingPath(input.generatedFlutterRoot);
  const backendExport=safeExistingPath(input.backendExportRoot);
  const generatedBackend=safeExistingPath(input.generatedBackendRoot);
  const projectId=typeof input.projectId==='string'?input.projectId:null;
  const hash=HASH.test(input.contractHash??'')?input.contractHash:null;
  const backendPin=SHA.test(input.expectedBackendSha??'')?input.expectedBackendSha:null;
  const flutterPin=SHA.test(input.expectedFlutterSha??'')?input.expectedFlutterSha:null;
  const profiles={};
  for(const profile of PROFILES){
    const candidate=input.fableProfiles?.[profile];
    if(candidate && typeof candidate==='object'){
      const source=safeExistingPath(candidate.source);
      if(source&&typeof candidate.expectedProjectId==='string'&&
        candidate.expectedProjectId.length>2&&HASH.test(candidate.expectedContractHash??'')){
        profiles[profile]={source,
          expectedProjectId:candidate.expectedProjectId,
          expectedContractHash:candidate.expectedContractHash};
      }
    }
  }
  return {generated,backendExport,generatedBackend,projectId,hash,
    backendPin,flutterPin,profiles};
}
export function buildOneCommandPlan({
  root,backendRoot=null,packageScripts={},inputs={},
  flutterAvailable=true,exists=existsSync,
  safeTestRead=readSafeFeatureEvidence,
  gitTestDiscovery=discoverTrackedNodeTests,
}={}){
  const flutterRoot=resolve(root??'.');
  const backend=backendRoot?resolve(backendRoot):null;
  const args=backgroundInputs(inputs,flutterRoot,backend);
  const backendCheckout=resolveBackendCheckoutRoot(backend);
  const nodeTests=discoverExistingNodeTests(packageScripts,
    file=>exists(join(flutterRoot,file)));
  const tracked=gitTestDiscovery(flutterRoot);
  const safePaths=[];
  const invalidPaths=[...nodeTests.unsupported,...tracked.rejected];
  for(const path of new Set([...nodeTests.paths,...tracked.files])){
    try {safeTestRead(flutterRoot,path);safePaths.push(path);}
    catch {invalidPaths.push('UNSAFE_NODE_TEST_FILE:'+path);}
  }
  safePaths.sort();
  const plan=[];
  const add=(id,stage,program,argv,cwd,reason=null,timeout=TIMEOUT.node)=>
    plan.push({id,stage,program,args:argv,root:cwd,
      blockReason:reason,timeoutMs:timeout});
  add('NODE_ALL_EXISTING_TEST_SCRIPTS','W0-W7','node',
    ['--test','--test-concurrency=4',...safePaths],flutterRoot,
    safePaths.length?null:'NO_SAFE_NODE_TEST_FILES_FOUND');
  add('BACKEND_W1_W2_FAST','W1-W2','node',
    ['tools/fable-w1-w2-one-shot.mjs','--fast','--json'],backend,
    backend?null:'PRIVATE_BACKEND_CHECKOUT_NOT_FOUND',TIMEOUT.backendFast);
  add('BACKEND_W1_W2_FULL','W1-W2','node',
    ['tools/fable-w1-w2-one-shot.mjs','--full','--json'],backend,
    backend?null:'PRIVATE_BACKEND_CHECKOUT_NOT_FOUND',TIMEOUT.backendFull);
  add('W2_GENERATED_BACKEND_ARTIFACT_AUDIT','W2','node',
    ['tools/fable-w2-generated-artifact-audit.mjs','--project',
      args.generatedBackend??'','--json'],backend,
    backend&&args.generatedBackend?null:'ACTUAL_GENERATED_BACKEND_PROJECT_REQUIRED');
  add('W3_REAL_BACKEND_FLUTTER_HANDOFF','W3','node',
    ['tools/verify-current-w3-handoff.mjs',
      '--backend-export',args.backendExport??'',
      '--flutter-root',args.generated??flutterRoot,
      '--backend-repo',backendCheckout??'',
      '--expected-backend-sha',args.backendPin??''],flutterRoot,
    backendCheckout&&args.backendExport&&args.generated&&args.backendPin&&args.flutterPin?
      null:'INDEPENDENT_W3_EXPORT_FLUTTER_PROJECT_AND_BOTH_GIT_PINS_REQUIRED');
  const fableComplete=PROFILES.every(p=>args.profiles[p]);
  const profileArgs=PROFILES.flatMap(p=>{
    const x=args.profiles[p];
    return x?['--fable-'+p+'-export',x.source,
      '--fable-'+p+'-project-id',x.expectedProjectId,
      '--fable-'+p+'-contract-hash',x.expectedContractHash]:[];
  });
  add('W4_TWELVE_GUIDED_AGENT_WIZARD_SCENARIOS','W4','node',
    ['tools/run-w4-wizard-matrix.mjs','--json',
      ...(fableComplete?['--materialize']:[]),...profileArgs],
    flutterRoot,null,TIMEOUT.node);
  add('W5_COMPLETE_SELECTED_FEATURE_SOURCE_AUDIT','W5','node',
    ['tools/run-w5-feature-flow-audit.mjs','--root',args.generated??flutterRoot,
      ...(args.projectId&&args.hash?
        ['--expected-project-id',args.projectId,'--expected-contract-hash',args.hash]:[]),
      '--json'],flutterRoot,null,TIMEOUT.node);
  plan.at(-1).realProjectInputsProvided=Boolean(args.generated&&args.projectId&&args.hash);
  add('W0_HISTORICAL_82_ITEM_AUDIT','W0-W8','node',
    ['tools/closure-gap-audit-cli.mjs','--strict','--json'],flutterRoot);
  add('W6_W7_NATIVE_AUTH_NOTIFICATIONS_WIDGET','W6-W7','flutter',
    ['test','packages/fable_core/test/auth_gateway_identity_regression_test.dart',
      'packages/features/fable_auth/test/mandatory_password_change_page_test.dart',
      'packages/features/fable_notifications/test/notification_identity_navigation_rc108_test.dart',
      'packages/features/fable_notifications/test/inbox_refresh_signal_test.dart'],
    flutterRoot,flutterAvailable?null:'FLUTTER_SDK_NOT_INSTALLED',TIMEOUT.flutter);
  add('W7_FLUTTER_ANALYZE','W7','flutter',['analyze'],flutterRoot,
    flutterAvailable?null:'FLUTTER_SDK_NOT_INSTALLED',TIMEOUT.flutter);
  add('W7_FULL_FLUTTER_TEST','W7','flutter',['test'],flutterRoot,
    flutterAvailable?null:'FLUTTER_SDK_NOT_INSTALLED',TIMEOUT.flutter);
  return {schemaVersion:1,batch:'RC217-ONE-COMMAND',
    plan,backendCheckoutRoot:backendCheckout,
    filesDiscovered:safePaths.length,
    unregisteredNodeTests:tracked.files.filter(path=>!nodeTests.paths.includes(path)).length,
    gitTestInventoryVerified:tracked.gitInventoryVerified,
    unsupportedTestCommands:[...new Set(invalidPaths)].sort(),
    profileExportsProvided:PROFILES.filter(p=>args.profiles[p]).length,
    independentInputsProvided:Boolean(args.backendPin&&args.flutterPin)};
}
/**
 * Flutter on Windows is distributed as flutter.bat, not an executable.
 * Node's no-shell child spawning cannot directly launch .bat files.
 * Only the fixed, allowlisted Flutter argv defined by this module may pass
 * through cmd.exe; NO user-provided commands, shell metacharacters or paths.
 */
export function flutterChildSpec(step,{platform=process.platform}={}){
  if(step.program!=='flutter')
    return {command:process.execPath,args:step.args};
  if(platform!=='win32')return {command:'flutter',args:step.args};
  if(!Array.isArray(step.args)||step.args.length===0||
     step.args.some(x=>typeof x!=='string'||
       !/^[a-zA-Z0-9_.\\/-]+$/.test(x)))
    throw Error('RC218_UNSAFE_WINDOWS_FLUTTER_COMMAND');
  return {command:'cmd.exe',args:['/d','/s','/c',
    'flutter '+step.args.join(' ')]};
}
export function localRunner(step,{
  spawn=spawnSync,platform=process.platform,now=Date.now,
}={}){
  const start=now();
  const spec=flutterChildSpec(step,{platform});
  const run=spawn(spec.command,spec.args,{
    cwd:step.root,encoding:'utf8',windowsHide:true,
    stdio:['ignore','pipe','pipe'],timeout:step.timeoutMs,
    maxBuffer:16*1024*1024});
  // No raw command output is surfaced in reports (may contain secrets).
  return {exitCode:run.status,signal:run.signal??null,
    error:run.error?.code??null,durationMs:now()-start};
}
function classify(step,r,{profileExportsProvided=0,closure=null}={}){
  if(step.blockReason)return {state:'BLOCKED',reason:step.blockReason};
  if(!r)return {state:'NOT_RUN',reason:'COMMAND_NOT_EXECUTED'};
  if(r.error==='ENOENT')return {state:'BLOCKED',reason:'TOOL_NOT_INSTALLED'};
  // W4 still executes the Other-Backend paths if no Fable exports exist.
  // Its missing six real Fable profiles are a prerequisite, not a failed
  // implementation test, and never count as 12/12 PASS.
  if(step.id==='W4_TWELVE_GUIDED_AGENT_WIZARD_SCENARIOS'&&
     profileExportsProvided!==3)
    return {state:'BLOCKED',reason:'SIX_FABLE_PATHS_NEED_REAL_PROFILE_EXPORTS'};
  if(step.id==='W5_COMPLETE_SELECTED_FEATURE_SOURCE_AUDIT'&&
     !step.realProjectInputsProvided)
    return {state:'BLOCKED',reason:'REAL_SELECTED_PROJECT_AND_OPERATION_EVIDENCE_REQUIRED'};
  if(step.id==='W0_HISTORICAL_82_ITEM_AUDIT'&&
     closure?.counts?.outstanding>0&&r.exitCode===2&&!r.signal&&!r.error)
    return {state:'BLOCKED',reason:'AUTHORITATIVE_HISTORICAL_ACCEPTANCE_GAPS_OPEN'};
  return r.exitCode===0&&!r.signal&&!r.error?
    {state:'LOCAL_CHECK_PASS',reason:null}:
    {state:'FAILED',reason:'PROCESS_NONZERO_OR_INTERRUPTED'};
}
export function evaluateOneCommandPlan(plan,runs=[],{
  closure=null,backendCheckout=null,flutterCheckout=null,
}={}){
  const byId=new Map(runs.map(x=>[x.id,x]));
  const results=plan.plan.map(step=>{
    const run=byId.get(step.id);
    const classified=classify(step,run,{
      profileExportsProvided:plan.profileExportsProvided,closure});
    const conditionalIncomplete=step.id==='W4_TWELVE_GUIDED_AGENT_WIZARD_SCENARIOS'&&
      plan.profileExportsProvided!==3;
    return {id:step.id,stage:step.stage,state:classified.state,
      reason:classified.reason,exitCode:run?.exitCode??null,
      durationMs:run?.durationMs??null,
      ...(conditionalIncomplete?{fullWizardMatrixAccepted:false}:{}),
    };
  });
  const counts={passed:results.filter(x=>x.state==='LOCAL_CHECK_PASS').length,
    failed:results.filter(x=>x.state==='FAILED').length,
    blocked:results.filter(x=>x.state==='BLOCKED').length,
    notRun:results.filter(x=>x.state==='NOT_RUN').length};
  return {schemaVersion:1,batch:plan.batch,
    selectedManager:'pnpm',oneCommand:'pnpm fable:all',
    latestSource:{backend:backendCheckout,flutter:flutterCheckout},
    testsDiscovered:plan.filesDiscovered,
    previouslyUnregisteredNodeTests:plan.unregisteredNodeTests??0,
    completeGitTestInventoryVerified:Boolean(plan.gitTestInventoryVerified),
    sourceTestScriptIssues:plan.unsupportedTestCommands,
    counts,checks:results,
    historical:{families:closure?.counts?.families??null,
      sourceGapItems:closure?.counts?.sourceGapItems??null,
      crossCuttingItems:closure?.counts?.crossCuttingItems??null,
      wizardScenarios:closure?.counts?.wizardScenarios??null,
      outstanding:closure?.counts?.outstanding??null,
      status:closure?.releaseDecision??'NOT_VERIFIED'},
    realDeviceProviderAndHumanGates:OWNER_GATES.map(id=>
      ({id,state:'OWNER_E2E_REQUIRED'})),
    sourceChecksDoNotImplyHardwareE2E:true,
    realAndroidVerified:false,realIosVerified:false,
    realProviderE2EVerified:false,independentReleaseApproved:false,
    productionReady:false,releaseDecision:'NO_GO'};
}
function auditHistorical(root){
  try {
    const read=name=>JSON.parse(readSafeFeatureEvidence(root,
      'docs/integrations/'+name));
    return auditClosureRegister(read('FABLE-FLUTTER-PARITY-MASTER.json'),
      read('FABLE-FINAL-CLOSURE-W0-GAP-REGISTER.json'));
  }catch{return null;}
}
/**
 * Preserve independent reports without following .fable/reports symlinks.
 * Nothing in this routine deletes a previous report or source file.
 */
export function saveOneCommandReport(root,report,{
  exists=existsSync,lstat=lstatSync,mkdir=mkdirSync,write=writeFileSync,
  stamp=()=>new Date().toISOString().replace(/[:.]/g,'-'),
  unique=()=>process.pid+'-'+Math.random().toString(16).slice(2),
}={}){
  const base=resolve(root);
  for(const folder of [base,join(base,'.fable'),join(base,'.fable','reports')]){
    if(exists(folder)){
      const info=lstat(folder);
      if(info.isSymbolicLink()||!info.isDirectory())
        throw Error('RC218_UNSAFE_REPORT_DIRECTORY: '+folder);
    }else mkdir(folder,{recursive:false,mode:0o700});
  }
  const path=join(base,'.fable','reports',
    'fable-'+stamp()+'-'+unique()+'.json');
  write(path,JSON.stringify(report,null,2)+'\n',
    {flag:'wx',mode:0o600});
  return path;
}

export function runFableOneCommand(root,{
  runner=localRunner,logger=console.log,backendRoot=undefined,
  inputOverride=undefined,flutterAvailable=true,
}={}){
  root=resolve(root);
  const backend=backendRoot===undefined?detectBackendRoot(root):backendRoot;
  const inputs=inputOverride??readOptionalInputs(root);
  const pkg=JSON.parse(readSafeFeatureEvidence(root,'package.json'));
  if(pkg.packageManager!=='pnpm@12.10.1')
    throw Error('EXPECTED_PINNED_PNPM_12_10_1');
  const plan=buildOneCommandPlan({root,backendRoot:backend,
    packageScripts:pkg.scripts,inputs,flutterAvailable});
  const repos={
    flutter:sourceFingerprint(root,'fable_flutter',inputs.expectedFlutterSha),
    backend:sourceFingerprint(plan.backendCheckoutRoot,
      'fable',inputs.expectedBackendSha),
  };
  const runs=[];
  for(const step of plan.plan){
    // A user-authored SHA string is not a verified source checkpoint.
    // The W3 project source check requires both independent Git main pins
    // to match local clean, correct-origin main checkouts.
    if(step.id==='W3_REAL_BACKEND_FLUTTER_HANDOFF' &&
       !step.blockReason &&
       (!repos.flutter.independentPinVerified||
        !repos.backend.independentPinVerified))
      step.blockReason='INDEPENDENT_MAIN_SOURCE_CHECKPOINT_MISMATCH';
    if(step.blockReason)continue;
    logger('Fable '+step.stage+' '+step.id+' ...');
    try{runs.push({id:step.id,...runner(step)});}
    catch(error){runs.push({id:step.id,exitCode:null,signal:null,
      error:error?.code??'RUNNER_ERROR',durationMs:null});}
  }
  const report=evaluateOneCommandPlan(plan,runs,{
    closure:auditHistorical(root),backendCheckout:repos.backend,
    flutterCheckout:repos.flutter,
  });
  const reportPath=saveOneCommandReport(root,report);
  logger('Fable checks: '+JSON.stringify(report.counts));
  logger('Historical outstanding: '+String(report.historical.outstanding));
  logger('Release: NO_GO until independent real E2E and owner approval');
  logger('Report: '+reportPath);
  return {report,reportPath};
}

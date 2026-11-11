#!/usr/bin/env node
/**
 * RC174 Stage 6 SOURCE preflight. A successful result cannot approve a
 * project, mobile device, real provider, or production release.
 * Uses RC153's existing independent project/contract gate; no invented API.
 */
import {readFileSync} from 'node:fs';
import {resolve,join} from 'node:path';
import {spawnSync} from 'node:child_process';
import {pathToFileURL} from 'node:url';

export const FAMILIES=Object.freeze([
  'auth','profile','notifications','media','localization','support','social',
  'biometrics','realtime','deeplinks','messaging','location','payments','offline',
  'analytics','content','access_control',
]);
const hex=v=>typeof v==='string'&&/^[0-9a-f]{64}$/.test(v);
const unique=a=>Array.isArray(a)&&new Set(a).size===a.length;

/** Pure simulation gate; statuses supplied by REAL source verification in CLI. */
export function evaluateStage6Source({mode='source',binding,manifest,master,
  dpopTransportPassed=false,dpopNativePassed=false}={}){
  const blockers=[];
  const fail=code=>{if(!blockers.includes(code))blockers.push(code);};
  if(mode!=='source'&&mode!=='project')fail('INVALID_MODE');
  if(!binding||binding.ok!==true)fail('PROJECT_CONTRACT_SOURCE_CHECK_FAILED');
  if(!master||master.kind!=='fable.flutter-feature-parity-master'||
     !Array.isArray(master.features)||master.features.length!==FAMILIES.length||
     !unique(master.features.map(x=>x?.id))||
     FAMILIES.some(id=>!master.features.some(x=>x?.id===id)))
    fail('FEATURE_PARITY_REGISTRY_INVALID');
  else for(const f of master.features){
    if(f.complete!==false||f.liveE2EVerified!==false)
      fail('UNVERIFIED_FEATURE_MARKED_COMPLETE');
    if(!Array.isArray(f.gaps)||!f.gaps.length||
       !Array.isArray(f.otherBackendContract)||!f.otherBackendContract.length)
      fail('FEATURE_ACCEPTANCE_GAPS_MISSING');
  }
  if(!manifest||!Array.isArray(manifest.features)||
     !unique(manifest.features)||manifest.features.some(id=>!FAMILIES.includes(id))||
     (manifest.capabilities!==undefined &&
       (!Array.isArray(manifest.capabilities)||
        JSON.stringify(manifest.features)!==JSON.stringify(manifest.capabilities))))
    fail('FEATURE_SELECTION_INVALID');
  if(binding&&manifest&&manifest.features?.length!==binding.selectedFeatureCount)
    fail('FEATURE_SELECTION_BINDING_MISMATCH');
  if(!dpopTransportPassed)fail('DPOP_DART_SOURCE_AUDIT_NOT_PASSED');
  if(!dpopNativePassed)fail('DPOP_NATIVE_SOURCE_AUDIT_NOT_PASSED');
  const backendKind=binding?.backendKind??null;
  if(!['fable','other'].includes(backendKind))fail('BACKEND_KIND_NOT_VERIFIED');
  const pin=manifest?.backendContractHash??null;
  if(backendKind==='fable'&&mode==='project'){
    if(binding?.fixture===true||binding?.projectBound!==true||
      !hex(pin)||binding?.contractHash!==pin)
      fail('REAL_FABLE_PROJECT_CONTRACT_PIN_REQUIRED');
  }
  if(backendKind==='other'&&mode==='project')
    fail('OTHER_BACKEND_REQUIRES_INDEPENDENT_PROJECT_ACCEPTANCE');
  if(backendKind==='other'&&pin!==null)
    fail('OTHER_BACKEND_CANNOT_BORROW_FABLE_HASH');
  // Source verification is deliberately distinct from authenticated mobile E2E.
  const sourcePreflightPassed=blockers.length===0;
  return {
    schemaVersion:1,stage:6,mode,backendKind,
    selectedFeatureCount:manifest?.features?.length??null,
    auditedFamilies:FAMILIES.length,
    sourcePreflightPassed,
    realProjectBound:backendKind==='fable'&&mode==='project'&&
      binding?.projectBound===true&&binding?.fixture===false&&hex(pin)&&
      binding?.contractHash===pin&&sourcePreflightPassed,
    // Never infer these from file existence, mocked checks or a self-asserted ledger.
    dartExecuted:false,androidExecuted:false,iosExecuted:false,
    authenticatedBackendE2E:false,stage6Complete:false,productionReady:false,
    blockers,
    unverified:['Flutter analyze/test on current HEAD','native Android and iOS execution',
      'authenticated HTTPS with pinned non-fixture project','selected provider/feature E2E',
      'real device hardware-backed DPoP and credential lifecycle'],
  };
}

function command(root,args){
  const run=spawnSync(process.execPath,args,{cwd:root,encoding:'utf8',
    timeout:120000,maxBuffer:2*1024*1024,windowsHide:true});
  return {passed:run.status===0&&!run.error,stdout:run.stdout??''};
}
export function runStage6Source({root=resolve(import.meta.dirname,'..'),
  mode='source',expectedProjectId=null,expectedContractHash=null}={}){
  root=resolve(root);
  const args=['tools/verify-stage4-feature-binding.mjs','--root',root,'--mode',mode];
  if(expectedProjectId)args.push('--expected-project-id',expectedProjectId);
  if(expectedContractHash)args.push('--expected-contract-hash',expectedContractHash);
  const checked=command(root,args);
  let binding=null;
  try{binding=JSON.parse(checked.stdout);}catch{}
  if(!checked.passed&&binding)binding.ok=false;
  const read=path=>{try{return JSON.parse(readFileSync(join(root,path),'utf8'));}catch{return null;}};
  const dpopTransport=command(root,['--test','tools/rc166-dpop-source-audit.mjs']);
  const dpopNative=command(root,['--test','tools/rc166-native-dpop-source-audit.mjs']);
  return evaluateStage6Source({mode,binding,
    manifest:read('.fable/mobile-features.json'),
    master:read('docs/integrations/FABLE-FLUTTER-PARITY-MASTER.json'),
    dpopTransportPassed:dpopTransport.passed,
    dpopNativePassed:dpopNative.passed});
}
if(process.argv[1]&&import.meta.url===pathToFileURL(resolve(process.argv[1])).href){
  try{
    let root=resolve(import.meta.dirname,'..'),mode='source',expectedProjectId=null,
      expectedContractHash=null;
    for(let i=2;i<process.argv.length;i++){
      const a=process.argv[i],v=process.argv[++i];
      if(!v)throw Error('Missing value for '+a);
      if(a==='--root')root=v;
      else if(a==='--mode')mode=v;
      else if(a==='--expected-project-id')expectedProjectId=v;
      else if(a==='--expected-contract-hash')expectedContractHash=v;
      else throw Error('Unsupported argument '+a);
    }
    const report=runStage6Source({root,mode,expectedProjectId,expectedContractHash});
    process.stdout.write(JSON.stringify(report,null,2)+'\n');
    if(!report.sourcePreflightPassed)process.exitCode=2;
  }catch(e){process.stderr.write('RC174 source preflight blocked: '+e.message+'\n');process.exitCode=2;}
}

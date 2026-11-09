#!/usr/bin/env node
/**
 * RC153 / original Stage 4 — read-only cross-manifest contract provenance.
 * Source mode permits the reusable test-project fixture but never approves it.
 * Project mode needs independently supplied identity and Backend export hash.
 * Other Backend never borrows Fable's fixtures or approval.
 */
import {existsSync,readFileSync} from 'node:fs';
import {join,resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import {verifyFableContract} from './verify-fable-contract.mjs';

const isHash=value=>typeof value==='string'&&/^[0-9a-f]{64}$/.test(value);
const isFeature=value=>typeof value==='string'&&/^[a-z][a-z0-9_-]{1,80}$/.test(value);
const unique=values=>new Set(values).size===values.length;

export function verifyStage4FeatureBinding(root,{mode='source',expectedProjectId=null,expectedContractHash=null}={}){
  root=resolve(root);
  const failures=[],messages=[];
  const fail=code=>{if(!failures.includes(code))failures.push(code);};
  const read=(path,required=true)=>{
    const file=join(root,path);
    if(!existsSync(file)){if(required)fail('missing:'+path);return null;}
    try{return JSON.parse(readFileSync(file,'utf8'));}
    catch{fail('invalid_json:'+path);return null;}
  };
  if(!['source','project'].includes(mode))fail('invalid_mode');
  const cfg=read('assets/config/backend.json');
  const manifest=read('.fable/mobile-features.json');
  const kind=cfg?.backend?.kind??null;
  if(!cfg||cfg.schemaVersion!==1||cfg.kind!=='fable.mobile-backend-configuration'||
     !['fable','other'].includes(kind)||typeof cfg.contractImported!=='boolean')
    fail('invalid_backend_selection');
  if(!manifest||manifest.schemaVersion!==2||
     manifest.kind!=='fable.mobile-feature-selection'||
     !Array.isArray(manifest.features)||!manifest.features.every(isFeature)||
     !unique(manifest.features))
    fail('invalid_mobile_features');
  if(manifest?.capabilities!==undefined &&
      (!Array.isArray(manifest.capabilities)||!manifest.capabilities.every(isFeature)||
       !unique(manifest.capabilities)||
       JSON.stringify(manifest.capabilities)!==JSON.stringify(manifest.features)))
    fail('capabilities_features_mismatch');
  // A locally selected feature is never proof that its server route is enabled.
  // Preserve client-only/hybrid packages even if the Backend has no corresponding API.
  const selected=Array.isArray(manifest?.features)?manifest.features:[];
  let contractHash=null,projectId=null,fixture=false,projectBound=false;
  const declaredHash=manifest?.backendContractHash??null;
  if(declaredHash!==null&&!isHash(declaredHash))fail('invalid_mobile_feature_contract_hash');
  if(kind==='fable'){
    if(cfg?.backend?.adapter!=='fable-contract'||cfg?.backend?.status!=='ready'||
       cfg?.contractImported!==true)fail('fable_backend_not_imported');
    // Independently verify the imported Fable export and its handoff; do not
    // derive trust solely from feature selections or a self-asserted hash.
    const verified=verifyFableContract(root,{
      mode:mode==='project'?'project':'source',
      expectedProjectId,expectedContractHash,
    });
    if(!verified.ok){
      fail('fable_contract_verification_failed');
      for(const code of verified.failures)fail('fable:'+code);
    }
    contractHash=verified.contractHash??null;
    projectId=verified.projectId??null;
    fixture=Boolean(verified.fixture);
    if(isHash(declaredHash)&&declaredHash!==contractHash)
      fail('mobile_feature_contract_hash_mismatch');
    if(!isHash(declaredHash)&&!fixture)
      fail('mobile_feature_contract_unpinned');
    if(fixture){
      messages.push('Reusable test-project contract: source-only; not a real Backend integration.');
      if(mode==='project')fail('fixture_project_not_accepted');
    }
    if(mode==='project'){
      if(!isHash(declaredHash))fail('mobile_feature_contract_unpinned');
      const source='verified-backend-project:'+String(projectId??'');
      if(manifest?.selectionSource!==source)
        fail('feature_selection_not_from_verified_project');
      const setup=read('.fable/frontend-setup.json');
      if(!setup||setup.kind!=='fable.flutter-frontend-setup'||
         setup.source!=='backend-contract-export'||setup.backendAuthority!==true||
         setup.projectBound!==true||setup.projectId!==projectId||
         setup.contractHash!==contractHash)
        fail('verified_frontend_setup_missing_or_stale');
      const sync=read('.fable/last-feature-sync.json');
      if(!sync||sync.kind!=='fable.flutter-feature-sync'||
         sync.projectId!==projectId||sync.contractHash!==contractHash)
        fail('feature_sync_provenance_missing_or_stale');
      projectBound=verified.projectBound===true&&isHash(declaredHash)&&
        declaredHash===contractHash&&!failures.length;
    }
  } else if(kind==='other'){
    if(declaredHash!==null)
      fail('other_backend_must_not_use_fable_contract_hash');
    // Other needs its own catalog/sourceHash, auth/permission mapping and real
    // API acceptance. This gate must not claim an external server is verified.
    messages.push('Other Backend must be verified against its independent imported API catalog.');
    if(mode==='project')fail('other_backend_independent_project_gate_required');
  }
  return {ok:failures.length===0,mode,backendKind:kind,projectId,
    contractHash,selectedFeatureCount:selected.length,fixture,projectBound,
    productionReady:false,liveE2EVerified:false,failures,messages};
}

function cli(args){
  let root=process.cwd(),mode='source',expectedProjectId=null,expectedContractHash=null;
  for(let i=0;i<args.length;i++){
    if(args[i]==='--root'&&args[i+1])root=args[++i];
    else if(args[i]==='--mode'&&args[i+1])mode=args[++i];
    else if(args[i]==='--expected-project-id'&&args[i+1])expectedProjectId=args[++i];
    else if(args[i]==='--expected-contract-hash'&&args[i+1])expectedContractHash=args[++i];
    else throw Error('Unsupported/missing argument: '+args[i]);
  }
  const result=verifyStage4FeatureBinding(root,{mode,expectedProjectId,expectedContractHash});
  process.stdout.write(JSON.stringify(result,null,2)+'\n');
  if(!result.ok)process.exitCode=2;
}
if(process.argv[1]&&import.meta.url===pathToFileURL(resolve(process.argv[1])).href){
  try{cli(process.argv.slice(2));}
  catch(error){process.stderr.write(String(error instanceof Error?error.message:error)+'\n');process.exitCode=2;}
}

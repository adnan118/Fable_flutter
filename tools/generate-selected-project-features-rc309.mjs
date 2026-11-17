#!/usr/bin/env node
/**
 * RC309 — source-only bulk creation of selected, independently signed Fable
 * feature packages. All selected features are planned before ANY write.
 * Durable backups + compare-before-rollback; no tests or Flutter SDK invoked.
 */
import {
  existsSync,lstatSync,readFileSync,mkdirSync,mkdtempSync,
  writeFileSync,renameSync,rmSync,openSync,closeSync,
} from 'node:fs';
import {resolve,join,dirname,relative,sep} from 'node:path';
import {pathToFileURL} from 'node:url';
import {createHash} from 'node:crypto';
import {planPinnedTypedFeature} from './generate-typed-feature-rc116.mjs';
import {planW5AppFeatureBinding} from './w5-app-feature-binding.mjs';
import {verifyGeneratedSelectedFeatures} from './verify-selected-project-features-rc311.mjs';
import {pathEntryExists,assertRegularProjectPath,generatedTreeExactlyMatches} from './rc366-safe-source-tree.mjs';

const HASH=/^[0-9a-f]{64}$/;
const ID=/^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$/;
const SOURCES=[
  'assets/config/backend.json',
  'assets/contracts/contract.json',
  'assets/contracts/openapi.json',
  '.fable/frontend-setup.json',
  '.fable/project-features.json',
  '.fable/feature-integration-requirements.json',
];
const sha=s=>createHash('sha256').update(s).digest('hex');
function requireDirectory(path){
  if(!existsSync(path)||lstatSync(path).isSymbolicLink()||
     !lstatSync(path).isDirectory())
    throw Error('RC309 requires a real, non-symlink project folder: '+path);
}
function requireFile(path,root=null){
  if(root!==null)assertRegularProjectPath(root,path,'file');
  else if(!pathEntryExists(path)||lstatSync(path).isSymbolicLink()||
     !lstatSync(path).isFile())throw Error('RC309 requires a real source file: '+path);
}
function selection(root){
  const p=join(root,'.fable/project-features.json');
  requireFile(p,root);
  const parsed=JSON.parse(readFileSync(p,'utf8'));
  if(parsed.schemaVersion!==1||!Array.isArray(parsed.features)||
     parsed.features.length<1||parsed.features.length>24)
    throw Error('RC309 requires 1–24 explicitly selected project features');
  const ids=parsed.features.map(x=>typeof x==='string'?x:x?.id);
  if(ids.some(x=>typeof x!=='string'||!ID.test(x)||x.length>64)||
     new Set(ids).size!==ids.length)
    throw Error('Duplicate or unsafe selected feature names');
  return ids;
}
function snapshots(root){
  return new Map(SOURCES.map(name=>{
    const path=join(root,...name.split('/'));
    requireFile(path,root);
    return [name,readFileSync(path,'utf8')];
  }));
}
function unchanged(root,saved){
  for(const [name,original] of saved){
    const path=join(root,...name.split('/'));
    requireFile(path,root);
    if(readFileSync(path,'utf8')!==original)
      throw Error('A signed project input changed during source generation: '+name);
  }
}
function pathWithin(root,target){
  return target.startsWith(root+sep)&&target!==root;
}
function assembleBinding(root,ids){
  const pubspecPath=join(root,'pubspec.yaml');
  const registryPath=join(root,'lib/src/generated/feature_registry.dart');
  for(const dir of [root,join(root,'lib'),join(root,'lib/src'),
      join(root,'lib/src/generated')])assertRegularProjectPath(root,dir,'dir');
  for(const file of [pubspecPath,registryPath])requireFile(file,root);
  const initialPubspec=readFileSync(pubspecPath,'utf8');
  const initialRegistry=readFileSync(registryPath,'utf8');
  let pubspec=initialPubspec,registry=initialRegistry;
  // Compute ALL registry/pubspec edits in memory before touching the project.
  for(const featureId of ids){
    const next=planW5AppFeatureBinding({pubspec,registry,featureId});
    pubspec=next.pubspec;
    registry=next.registry;
  }
  return {pubspecPath,registryPath,initialPubspec,initialRegistry,pubspec,registry};
}
function args(argv){
  const result={root:process.cwd(),apply:false,wireApp:false,json:false};
  const seen=new Set();
  for(let i=0;i<argv.length;i++){
    const key=argv[i];
    if(key==='--')continue;
    if(key==='--help'||key==='-h')return {help:true};
    if(seen.has(key))throw Error('Duplicate RC309 argument: '+key);
    seen.add(key);
    if(key==='--apply'||key==='--wire-app'||key==='--json'){
      result[key.slice(2).replace(/-([a-z])/g,(_,c)=>c.toUpperCase())]=true;
      continue;
    }
    if(!['--root','--expected-project-id','--expected-contract-hash'].includes(key)||
       !argv[i+1]||argv[i+1].startsWith('--'))
      throw Error('Unknown/incomplete RC309 option: '+key);
    const name=key.slice(2).replace(/-([a-z])/g,(_,c)=>c.toUpperCase());
    result[name]=argv[++i];
  }
  if(!result.expectedProjectId||
     typeof result.expectedProjectId!=='string'||
     result.expectedProjectId.length>160||
     !HASH.test(result.expectedContractHash??''))
    throw Error('Independent --expected-project-id and 64-hex --expected-contract-hash are required');
  return result;
}
export function generateSelectedProjectFeatures(options){
  const root=resolve(options.root??process.cwd());
  for(const dir of [root,join(root,'.fable'),join(root,'packages'),
      join(root,'packages/features')])assertRegularProjectPath(root,dir,'dir');
  const ids=selection(root);
  const saved=snapshots(root);
  const all=ids.map(featureId=>{
    const planned=planPinnedTypedFeature(root,{
      featureId,expectedProjectId:options.expectedProjectId,
      expectedContractHash:options.expectedContractHash,
    });
    const destination=join(root,'packages/features/fable_'+featureId);
    if(!pathWithin(root,destination)||pathEntryExists(destination))
      throw Error('Package destination already exists or is unsafe: '+featureId);
    return {...planned,featureId,destination};
  });
  const binding=options.wireApp===true?assembleBinding(root,ids):null;
  const totalFiles=all.reduce((sum,item)=>sum+item.files.size,0);
  if(totalFiles>2400)throw Error('RC309 feature batch exceeds safe file cap');
  const report={
    schemaVersion:1,kind:'fable.selected-feature-source-batch',
    projectId:options.expectedProjectId,
    projectContractHash:options.expectedContractHash,
    selected:ids.length,operations:all.reduce((n,x)=>n+x.plan.operations.length,0),
    files:totalFiles,appWiringRequested:Boolean(binding),
    features:all.map(x=>({
      featureId:x.featureId,files:x.files.size,
      methods:[...new Set(x.plan.operations.map(op=>op.method))].sort(),
      operationIds:x.plan.operations.map(op=>op.operationId),
      requiresManagedBinding:x.plan.operations.some(op=>op.managedScoped===true),
    })),
    applied:false,appWired:false,sourceOnly:true,
    testsExecuted:false,liveE2EVerified:false,productionReady:false,
    preflight:'ALL_SELECTED_FEATURES_AND_SIGNED_CONTRACTS_PLANNED',
  };
  if(options.apply!==true)return report;
  // A single inter-process writer for this batch only. Legacy generators
  // still use their own controls; all signed inputs are rechecked at commit.
  const lock=join(root,'.fable/rc309-source-batch.lock');
  let fd;
  try{fd=openSync(lock,'wx');}
  catch{throw Error('Another RC309 batch lock exists; review before retry');}
  let stage=null,backup=null;
  const created=[];
  try{
    unchanged(root,saved);
    for(const x of all)
      if(pathEntryExists(x.destination))
        throw Error('Feature appeared after preflight: '+x.featureId);
    stage=mkdtempSync(join(root,'packages/features/.rc309-stage-'));
    for(const feature of all){
      const base='packages/features/fable_'+feature.featureId+'/';
      const directory=join(stage,feature.featureId);
      mkdirSync(directory,{recursive:false});
      for(const [name,source] of feature.files){
        if(!name.startsWith(base)||typeof source!=='string'||source.length>4_000_000)
          throw Error('Unexpected feature output: '+name);
        const path=name.slice(base.length);
        const parts=path.split('/');
        if(!path||parts.some(x=>!x||x==='.'||x==='..'||x.includes('\\')))
          throw Error('RC309 path traversal in generated package: '+name);
        const dest=join(directory,...parts);
        if(!pathWithin(directory,dest))
          throw Error('Generated source escaped feature stage: '+name);
        mkdirSync(dirname(dest),{recursive:true});
        writeFileSync(dest,source,{encoding:'utf8',flag:'wx'});
      }
    }
    if(binding){
      const backupParent=join(root,'.fable/feature-backups');
      if(!existsSync(backupParent))mkdirSync(backupParent,{recursive:true});
      requireDirectory(backupParent);
      assertRegularProjectPath(root,backupParent,'dir');
      backup=mkdtempSync(join(backupParent,'rc309-'));
      writeFileSync(join(backup,'pubspec.yaml'),binding.initialPubspec,{
        encoding:'utf8',flag:'wx',
      });
      writeFileSync(join(backup,'feature_registry.dart'),binding.initialRegistry,{
        encoding:'utf8',flag:'wx',
      });
      writeFileSync(join(backup,'source-receipt.json'),JSON.stringify({
        ...report,backupSha256:{
          pubspec:sha(binding.initialPubspec),registry:sha(binding.initialRegistry),
        },filesWillBeWritten:true,
      },null,2)+'\n',{flag:'wx'});
    }
    unchanged(root,saved);
    if(binding){requireFile(binding.pubspecPath,root);requireFile(binding.registryPath,root);}
    if(binding&&(
      readFileSync(binding.pubspecPath,'utf8')!==binding.initialPubspec||
      readFileSync(binding.registryPath,'utf8')!==binding.initialRegistry))
      throw Error('App pubspec/feature registry changed during preflight');
    for(const feature of all){
      if(pathEntryExists(feature.destination))
        throw Error('Package appeared while staging: '+feature.featureId);
      renameSync(join(stage,feature.featureId),feature.destination);
      created.push(feature);
    }
    if(binding){
      requireFile(binding.pubspecPath,root);
      requireFile(binding.registryPath,root);
      if(readFileSync(binding.pubspecPath,'utf8')!==binding.initialPubspec||
         readFileSync(binding.registryPath,'utf8')!==binding.initialRegistry)
        throw Error('App source changed while committing feature packages');
      writeFileSync(binding.pubspecPath,binding.pubspec,'utf8');
      writeFileSync(binding.registryPath,binding.registry,'utf8');

    }
    // Source receipt: compare every committed file to the fully verified
    // preflight source before announcing source-level success (not a test).
    let verifiedFiles=0;
    for(const feature of all){
      const prefix='packages/features/fable_'+feature.featureId+'/';
      for(const [name,source] of feature.files){
        const dest=join(feature.destination,...name.slice(prefix.length).split('/'));
        requireFile(dest,root);
        if(readFileSync(dest,'utf8')!==source)
          throw Error('Committed source differs from signed preflight: '+name);
        verifiedFiles++;
      }
    }
    if(binding&&(
      readFileSync(binding.pubspecPath,'utf8')!==binding.pubspec||
      readFileSync(binding.registryPath,'utf8')!==binding.registry))
      throw Error('Committed app integration differs from preflight');
    // RC311: independent re-render of all signed sources, exact package-tree
    // checks (including injected extras), and canonical app registry integrity.
    // A refusal here enters the RC309 guarded rollback path.
    const attestation=verifyGeneratedSelectedFeatures({
      root,expectedProjectId:options.expectedProjectId,
      expectedContractHash:options.expectedContractHash,
      requireAppWiring:Boolean(binding),
    });
    if(attestation.sourceFilesVerified!==verifiedFiles)
      throw Error('RC311 independent signed file count disagrees with commit');
    report.sourceFilesVerified=verifiedFiles;
    report.sourceTreeAttestation=attestation.packages;
    report.appWiringVerified=attestation.appWiringVerified;
    report.applied=true;report.appWired=Boolean(binding);
    report.preflight='COMMITTED_SOURCE_ONLY';
    report.backup=backup?relative(root,backup):null;
    return report;
  }catch(error){
    const warnings=[];
    if(binding){
      // Roll back the bytes we wrote, but never overwrite another editor's
      // concurrent changes; recovery copies remain on disk.
      for(const [path,expected,original] of [
        [binding.pubspecPath,binding.pubspec,binding.initialPubspec],
        [binding.registryPath,binding.registry,binding.initialRegistry],
      ]){
        try{
          requireFile(path,root);
          if(readFileSync(path,'utf8')===expected)
            writeFileSync(path,original,'utf8');
          else if(readFileSync(path,'utf8')!==original)
            warnings.push('Concurrent change preserved: '+path);
        }catch{warnings.push('Manual source rollback needed: '+path);}
      }
    }
    for(const item of [...created].reverse()){
      try{
        const prefix='packages/features/fable_'+item.featureId+'/';
        // An extra file or symlink may belong to a concurrent developer.
        if(generatedTreeExactlyMatches(item.destination,item.files,prefix))
          rmSync(item.destination,{recursive:true,force:false});
        else warnings.push('Concurrent package addition/edit preserved: '+item.featureId);
      }catch{warnings.push('Manual package rollback needed: '+item.featureId);}
    }
    throw Error(error.message+(warnings.length?
      '; STOP, inspect durable backups and: '+warnings.join('; '):''));
  }finally{
    if(stage&&pathEntryExists(stage))rmSync(stage,{recursive:true,force:true});
    closeSync(fd);
    rmSync(lock,{force:true});
  }
}
function main(){
  const options=args(process.argv.slice(2));
  if(options.help){
    console.log('pnpm run wizard:feature:batch -- --expected-project-id <ID> --expected-contract-hash <SHA256> [--apply --wire-app] [--root PATH]');
    console.log('Preview first with --wire-app (no writes); --apply stages all selected feature packages and --wire-app binds app. No tests or downloads.');
    return;
  }
  console.log(JSON.stringify(generateSelectedProjectFeatures(options),null,2));
}
if(process.argv[1]&&import.meta.url===pathToFileURL(resolve(process.argv[1])).href)
  try{main();}catch(error){
    console.error('RC309 BATCH REFUSED: '+error.message);
    process.exitCode=2;
  }

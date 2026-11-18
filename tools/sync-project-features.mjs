#!/usr/bin/env node
/**
 * Project-scoped feature pruning from a verified Fable Backend handoff.
 * The reusable Flutter template is NOT pruned until a real project import
 * is pinned to an independently-known project ID and backend export hash.
 */
import {existsSync,readFileSync,writeFileSync,mkdirSync,readdirSync,statSync,lstatSync,cpSync,rmSync,renameSync} from 'node:fs';
import {resolve,join,dirname,relative,sep} from 'node:path';
import {createHash} from 'node:crypto';
import {pathToFileURL} from 'node:url';
import {importBackendDecisions} from './flutter-setup-wizard.mjs';
import {auditFeatureArchitectures} from './enforce-feature-architecture-rc115.mjs';
import {FEATURE_IDS,FEATURE_OWNERSHIP,REQUIRED_CORE,classifyFeatureDecisions} from './frontend-feature-ownership.mjs';
import {w5FeatureNames} from './w5-app-feature-binding.mjs';
import {assertRegularProjectPath,pathEntryExists} from './rc366-safe-source-tree.mjs';

const KNOWN=FEATURE_IDS;
const REQUIRED=new Set(REQUIRED_CORE);
const KEEP_CLIENT_ONLY=new Set(FEATURE_IDS.filter(id=>FEATURE_OWNERSHIP[id]==='client'));
const pathOf=id=>'packages/features/fable_'+id;
const safeFile=(root,file)=>resolve(root,file);
const sha256=value=>createHash('sha256').update(value).digest('hex');
function json(path){return JSON.parse(readFileSync(path,'utf8'));}
function writeJSON(p,v){mkdirSync(dirname(p),{recursive:true});writeFileSync(p,JSON.stringify(v,null,2)+'\n');}
function allSource(root,skip=new Set()){
  const out=[];
  function walk(dir){
    if(!pathEntryExists(dir))return;
    // A dangling symlink to a source directory is still a project source.
    // It must not disappear silently from the import-reference graph.
    assertRegularProjectPath(root,dir,'dir');
    for(const ent of readdirSync(dir,{withFileTypes:true})){
      if(ent.name==='.git'||ent.name==='build'||ent.name==='.dart_tool'||ent.name==='node_modules'||ent.name==='backups')continue;
      const p=join(dir,ent.name),rel=relative(root,p).split(sep).join('/');
      if([...skip].some(part=>rel===part || rel.startsWith(part+'/')))continue;
      if(ent.isSymbolicLink())
        throw Error('RC383 source reference scan refuses symlink: '+rel);
      if(ent.isDirectory())walk(p);
      else if(ent.isFile()&&p.endsWith('.dart'))out.push(p);
    }
  }
  walk(join(root,'lib'));
  walk(join(root,'test'));
  walk(join(root,'packages'));
  return out;
}
export function wiredTypedProjectFeatures(root,selected){
  // A declared custom feature is NEVER optional during feature sync.
  // Omitting a missing package from the registry would silently remove it
  // from app navigation even though the project still requests it.
  root=resolve(root);
  if(!Array.isArray(selected)||selected.length>24)
    throw Error('RC382 malformed project feature selection');
  const yamlPath=join(root,'pubspec.yaml');
  const registryPath=join(root,'lib/src/generated/feature_registry.dart');
  assertRegularProjectPath(root,yamlPath,'file');
  assertRegularProjectPath(root,registryPath,'file');
  const yaml=readFileSync(yamlPath,'utf8');
  const current=readFileSync(registryPath,'utf8');
  const found=[],ids=new Set();
  for(const feature of selected){
    const id=typeof feature==='string'?feature:feature?.id;
    if(typeof id!=='string'||id.length>64||
       !/^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$/.test(id)||
       FEATURE_IDS.includes(id)||ids.has(id))
      throw Error('RC382 invalid, built-in or duplicate declared custom feature');
    ids.add(id);
    const {packageName,variable}=w5FeatureNames(id);
    const packageRoot=join(root,'packages/features',packageName);
    const source=join(packageRoot,'lib/src/project_feature.dart');
    const pub='  '+packageName+':\n    path: packages/features/'+packageName;
    const imp="import 'package:"+packageName+"/"+packageName+".dart';";
    if(!pathEntryExists(packageRoot)||!pathEntryExists(source))
      throw Error('RC382 declared custom feature source missing: '+id);
    assertRegularProjectPath(root,packageRoot,'dir');
    assertRegularProjectPath(root,source,'file');
    if(!readFileSync(source,'utf8').includes('const '+variable+'=')||
       !yaml.includes(pub)||!current.includes(imp)||
       !new RegExp('^\\s*'+variable+',\\s*$','m').test(current))
      throw Error('RC382 registered custom feature is incomplete: '+id);
    found.push(id);
  }
  // The manifest must describe EVERY custom feature that remains installed
  // in the app. Missing or truncated manifests previously erased these
  // imports on the next regenerated feature registry.
  const installed=new Set();
  const importPattern=/^import 'package:fable_([a-z][a-z0-9]*(?:_[a-z0-9]+)*)\/fable_\1\.dart';\r?$/gm;
  for(const match of current.matchAll(importPattern))
    if(!FEATURE_IDS.includes(match[1]))installed.add(match[1]);
  const dependencyPattern=/^  fable_([a-z][a-z0-9]*(?:_[a-z0-9]+)*):\r?\n    path: packages\/features\/fable_\1(?:\r?\n|$)/gm;
  for(const match of yaml.matchAll(dependencyPattern))
    if(!FEATURE_IDS.includes(match[1]))installed.add(match[1]);
  for(const id of installed)
    if(!ids.has(id))
      throw Error('RC385 previously installed custom feature absent from manifest: '+id);
  const declaredVariables=new Set(found.map(id=>w5FeatureNames(id).variable));
  for(const match of current.matchAll(/^  ([A-Za-z][A-Za-z0-9]*ProjectFeature),\r?$/gm))
    if(!declaredVariables.has(match[1]))
      throw Error('RC385 unmanifested custom feature registry entry: '+match[1]);
  return found;
}

/**
 * RC397: Dart imports are not the complete package dependency graph.
 * Every installed package pubspec can require another feature at compile
 * time, even when that dependency is not currently imported by any .dart.
 */
export function declaredFeaturePackageDependents(root,featureId){
  const project=resolve(root);
  if(!KNOWN.includes(featureId))
    throw Error('Unknown feature package dependency lookup: '+featureId);
  const packagesRoot=join(project,'packages'),found=[];
  const dependency=new RegExp('^  fable_'+featureId+':(?:[ \\t]|$)','m');
  if(!pathEntryExists(packagesRoot))return found;
  function walk(dir,depth=0){
    if(depth>7)throw Error('RC397 unexpected package source nesting');
    assertRegularProjectPath(project,dir,'dir');
    for(const entry of readdirSync(dir,{withFileTypes:true})){
      if(['.git','.dart_tool','build','node_modules','Pods'].includes(entry.name))
        continue;
      const path=join(dir,entry.name);
      const rel=relative(project,path).split(sep).join('/');
      if(entry.isSymbolicLink())
        throw Error('RC397 package dependency graph contains symbolic link: '+rel);
      if(entry.isDirectory())walk(path,depth+1);
      else if(entry.isFile()&&entry.name==='pubspec.yaml'){
        // A package's self declaration is not a dependent; all other
        // package manifests must be considered, including generated ones.
        if(rel==='packages/features/fable_'+featureId+'/pubspec.yaml')continue;
        assertRegularProjectPath(project,path,'file');
        if(dependency.test(readFileSync(path,'utf8')))found.push(rel);
      }else if(!entry.isFile()){
        throw Error('RC397 unknown package entry during dependency scan: '+rel);
      }
    }
  }
  walk(packagesRoot);
  return found.sort();
}

function registry(features,projectFeatures=[]) {
  const all=[...features,...projectFeatures];
  const imports=all.map(id=>"import 'package:fable_"+id+"/fable_"+id+".dart';").join('\n');
  const descriptors=all.map(id=>{
    const varName=projectFeatures.includes(id)
      ?w5FeatureNames(id).variable
      :id==='access_control'?'accessControlFeature':id+'Feature';
    return '  '+varName+',';
  }).join('\n');
  return "// GENERATED BY FABLE MOBILE from a verified Backend contract. Do not edit by hand.\n"+
    "import 'package:fable_feature_contract/fable_feature_contract.dart';\n"+
    (imports?imports+'\n':'')+
    "\nconst List<FableFeature> installedFeatures = <FableFeature>[\n"+
    descriptors+"\n];\n";
}
export function planFeatureSync(root,verified,{prune=false}={}){
  if(verified?.kind!=='fable.flutter-frontend-setup'||verified.backendAuthority!==true||
     verified.source!=='backend-contract-export'||typeof verified.contractHash!=='string')
     throw Error('Verified Fable Backend project setup required for feature sync');
  const decisions=verified.decisionSnapshot?.decisions??{};
  const declared=decisions.frontendFeatures;
  const ownership=classifyFeatureDecisions(declared,verified.frontendSelection);
  // UI routes reflect Backend capability plus the explicit project selection.
  // Package retention is a separate, Flutter-owned decision.
  const visible=ownership.visibleBackendFeatures;
  const retained=ownership.retainedPackages;
  const disabled=ownership.backendPruneEligible;
  const protectedFrontend=ownership.frontendDecisionsRequired;
  const rootDir=resolve(root);
  if(prune){
    const pubspec=join(rootDir,'pubspec.yaml');
    const featuresPath=join(rootDir,'.fable/project-features.json');
    if(existsSync(pubspec)&&existsSync(featuresPath)&&
      /^name:\s*ci_fable\s*$/m.test(readFileSync(pubspec,'utf8'))&&
      json(featuresPath).app==='apps/ci_fable')
      throw Error('Refusing to prune the reusable ci_fable starter. Generate and identify a real Flutter project first.');
  }
  const local=existsSync(join(rootDir,'.fable','mobile-features.json'))?
    json(join(rootDir,'.fable','mobile-features.json')):null;
  const manifestFile=join(rootDir,'.fable','project-features.json');
  if(pathEntryExists(manifestFile))
    assertRegularProjectPath(rootDir,manifestFile,'file');
  const manifestSource=pathEntryExists(manifestFile)
    ?readFileSync(manifestFile,'utf8'):null;
  const externalProjectFeatures=manifestSource===null
    ?{features:[]}:JSON.parse(manifestSource);
  // Project-specific features are never inferred to be unused; they need
  // their own exact operation/permission mapping audit before any retirement.
  const protectedProjectFeatures=externalProjectFeatures?.features??[];
  if(!Array.isArray(protectedProjectFeatures))throw Error('Malformed project feature manifest');
  const wiredProjectFeatures=wiredTypedProjectFeatures(rootDir,protectedProjectFeatures);
  return {
    kind:'fable.flutter-feature-prune-plan',schemaVersion:1,
    projectId:verified.projectId,contractHash:verified.contractHash,
    projectBound:verified.projectBound===true,
    enabled:visible,disabled,
    retainedPackages:retained,
    frontendDecisionsRequired:protectedFrontend,
    hybridRetained:ownership.hybridRetained,
    frontendOnly:ownership.frontendOnly,
    ownership:ownership.decisions,
    clientOnlyReview:declared.clientOnlyReview,
    protectedProjectFeatureCount:protectedProjectFeatures.length,
    projectFeatureManifestSha256:manifestSource===null?null:sha256(manifestSource),
    wiredProjectFeatures,
    requestedSource:local?.selectionSource??null,
    pruneAvailable:verified.projectBound===true,
    note:'Backend routes use enabled; hybrid and local Flutter packages are retained even if unsupported on the server; physical pruning is restricted to disabled server-only features.',
  };
}
function removePushSections(src){
  const blocks=['FABLE_PUSH_IMPORT','FABLE_PUSH_ROUTES','FABLE_PUSH_NAV'];
  for(const key of blocks){
    const re=new RegExp('(^[ \\t]*// '+key+'_BEGIN\\r?\\n)[\\s\\S]*?(^[ \\t]*// '+key+'_END)', 'gm');
    if(!re.test(src))throw Error('Cannot safely prune notifications; missing '+key+' markers');
    re.lastIndex=0;
    src=src.replace(re,'$1$2');
  }
  return src;
}
function applyPrune(root,plan,{prune=false}={}){
  const project=resolve(root),current=json(join(project,'assets/contracts/contract.json'));
  // A second source-side authorization at the point of mutation protects
  // custom features added, removed or replaced after the preview/planning.
  const manifestPath=join(project,'.fable/project-features.json');
  if(pathEntryExists(manifestPath))
    assertRegularProjectPath(project,manifestPath,'file');
  const manifestSource=pathEntryExists(manifestPath)
    ?readFileSync(manifestPath,'utf8'):null;
  if((manifestSource===null?null:sha256(manifestSource))!==
     plan.projectFeatureManifestSha256)
    throw Error('RC385 custom feature manifest changed since sync planning');
  const selected=manifestSource===null?[]:JSON.parse(manifestSource).features;
  const actualWired=wiredTypedProjectFeatures(project,selected);
  if(actualWired.length!==plan.wiredProjectFeatures.length||
     actualWired.some((id,i)=>id!==plan.wiredProjectFeatures[i])||
     selected.length!==plan.protectedProjectFeatureCount)
    throw Error('RC382 custom feature selection changed since sync planning');
  if(current.contractHash!==plan.contractHash ||
    current.project?.id!==plan.projectId)throw Error('Imported project changed since feature planning');
  const registryPath=join(project,'lib/src/generated/feature_registry.dart');
  const inventoryPath=join(project,'.fable/mobile-features.json');
  const appPath=join(project,'lib/src/app.dart');
  const packageYaml=join(project,'pubspec.yaml');
  if(!pathEntryExists(registryPath)||!pathEntryExists(appPath)||
     !pathEntryExists(packageYaml))
    throw Error('Flutter project source missing');
  for(const path of [registryPath,appPath,packageYaml])
    assertRegularProjectPath(project,path,'file');
  const fableDir=join(project,'.fable');
  assertRegularProjectPath(project,fableDir,'dir');
  // Refuse to follow an external inventory symlink when writing selection.
  if(pathEntryExists(inventoryPath))
    assertRegularProjectPath(project,inventoryPath,'file');
  // The checked-in ci_fable repository is a reusable validation fixture,
  // not a customer project. Never physically delete template packages.
  if(prune &&
     /^name:\s*ci_fable\s*$/m.test(readFileSync(packageYaml,'utf8')) &&
     existsSync(join(project,'.fable/project-features.json')) &&
     json(join(project,'.fable/project-features.json')).app==='apps/ci_fable'){
    throw Error('Refusing to prune the reusable ci_fable starter. Generate and identify a real Flutter project first.');
  }
  // Apply only after a real pinned Backend; source-only staging can preview.
  if(!plan.projectBound)throw Error('Feature removal requires an independently pinned Backend project ID and contract hash');
  const pkgDirs=plan.disabled.map(id=>({id,rel:pathOf(id)}))
    .filter(x=>pathEntryExists(join(project,x.rel)));
  let app=readFileSync(appPath,'utf8');
  let yaml=readFileSync(packageYaml,'utf8');
  const blocked=[];
  const toDelete=[];
  const archivePaths=new Set(['lib/src/generated/feature_registry.dart',
    '.fable/mobile-features.json','.fable/last-feature-sync.json','pubspec.yaml']);
  if(prune && plan.disabled.includes('notifications')){
    app=removePushSections(app);
    archivePaths.add('lib/src/app.dart');
  }
  // Physical package prune can only remove dependencies after an import scan.
  // No unknown/custom source file is deleted.
  for(const {id,rel} of pkgDirs){
    if(!prune)continue;
    const candidate=join(project,rel);
    assertRegularProjectPath(project,candidate,'dir');
    // A symlink anywhere inside a removed package is user-controlled source.
    // Never delete that package until its ownership is reviewed explicitly.
    function rejectLinks(dir){
      for(const entry of readdirSync(dir,{withFileTypes:true})){
        const child=join(dir,entry.name);
        if(entry.isSymbolicLink())
          throw Error('RC383 pruning a symlinked feature source is forbidden: '+relative(project,child));
        if(entry.isDirectory())rejectLinks(child);
        else if(!entry.isFile())
          throw Error('RC383 unknown feature source type: '+relative(project,child));
      }
    }
    rejectLinks(candidate);
    const importNeedle="package:fable_"+id+"/";
    // Only the registry itself is replaced by this sync. Other generated
    // Dart source may contain real feature imports that must prevent pruning.
    const others=allSource(project,new Set([rel,'lib/src/generated/feature_registry.dart']))
      .filter(file=>file!==appPath && readFileSync(file,'utf8').includes(importNeedle));
    if(app.includes(importNeedle))others.push(appPath);
    if(others.length){blocked.push({feature:id,reason:'referenced-by-source',sources:others.map(x=>relative(project,x))});continue;}
    const pubspecDependents=declaredFeaturePackageDependents(project,id);
    if(pubspecDependents.length){
      blocked.push({feature:id,reason:'required-by-other-package-pubspec',
        sources:pubspecDependents});
      continue;
    }
    const dependency=new RegExp('^  fable_'+id+':\\r?\\n    path: packages/features/fable_'+id+'\\r?\\n','m');
    if(!dependency.test(yaml)){blocked.push({feature:id,reason:'nonstandard-dependency-ownership'});continue;}
    yaml=yaml.replace(dependency,'');
    toDelete.push(rel);
    // The live source tree will be moved atomically to the backup, not erased.
  }
  // Preserve the full pre-mutation source for rollback; never overwrite a
  // previous backup or delete any source tree before making the snapshot.
  const stamp=new Date().toISOString().replace(/[:.]/g,'-');
  const backup=resolve(project,'.fable','feature-backups',stamp);
  const backupParent=join(fableDir,'feature-backups');
  if(pathEntryExists(backupParent))
    assertRegularProjectPath(project,backupParent,'dir');
  else mkdirSync(backupParent,{recursive:true});
  assertRegularProjectPath(project,backupParent,'dir');
  if(pathEntryExists(backup))throw Error('Backup collision');
  const paths=[...archivePaths].filter(rel=>pathEntryExists(join(project,rel)));
  for(const rel of paths){
    const dst=join(backup,rel),src=join(project,rel);
    // Backups are durable project sources; do not write through symlinks.
    const isDirectory=lstatSync(src).isDirectory();
    assertRegularProjectPath(project,src,isDirectory?'dir':'file');
    mkdirSync(dirname(dst),{recursive:true});
    assertRegularProjectPath(project,dirname(dst),'dir');
    cpSync(src,dst,{recursive:true,force:false,errorOnExist:true});
  }
  const inventory={
    schemaVersion:2,kind:'fable.mobile-feature-selection',
    capabilities:plan.retainedPackages,features:plan.retainedPackages,
    backendVisible:plan.enabled,
    featureOwnership:plan.ownership.map(({id,ownership,backendEnabled,retainPackage,defaultBackendUiVisible})=>
      ({id,ownership,backendEnabled,retainPackage,defaultBackendUiVisible})),
    backendContractHash:plan.contractHash,
    selectionSource:'verified-backend-project:'+plan.projectId,
    disabled:plan.disabled,
    clientOnlyReview:plan.clientOnlyReview,
  };
  const lastSyncPath=join(fableDir,'last-feature-sync.json');
  if(pathEntryExists(lastSyncPath))
    assertRegularProjectPath(project,lastSyncPath,'file');
  // The backup is durable before the first mutation. Each write is
  // compare-before-revert; another editor's changes are NEVER overwritten.
  const originalText=new Map([
    registryPath,inventoryPath,appPath,packageYaml,lastSyncPath,
  ].map(path=>[path,pathEntryExists(path)?readFileSync(path,'utf8'):null]));
  const writes=new Map(),moved=[];
  const archived=[];
  function saveSource(path,content){
    if(pathEntryExists(path))
      assertRegularProjectPath(project,path,'file');
    writes.set(path,content);
    writeFileSync(path,content,'utf8');
  }
  try{
    saveSource(registryPath,registry(plan.retainedPackages,plan.wiredProjectFeatures));
    saveSource(inventoryPath,JSON.stringify(inventory,null,2)+'\n');
    if(prune){
      saveSource(appPath,app);
      saveSource(packageYaml,yaml);
      // Source packages are relocated to an immutable recovery location.
      // Moving directories is atomic on the same filesystem, unlike rmSync.
      for(const rel of toDelete){
        const source=join(project,rel);
        const archivedAt=join(backup,'pruned-packages',rel);
        if(pathEntryExists(archivedAt))
          throw Error('RC384 package archive collision: '+rel);
        assertRegularProjectPath(project,source,'dir');
        mkdirSync(dirname(archivedAt),{recursive:true});
        assertRegularProjectPath(project,dirname(archivedAt),'dir');
        renameSync(source,archivedAt);
        moved.push({source,archivedAt,rel});
        archived.push(relative(project,archivedAt).split(sep).join('/'));
      }
    }
    const report={
      schemaVersion:1,kind:'fable.flutter-feature-sync',
      projectId:plan.projectId,contractHash:plan.contractHash,
      enabled:plan.enabled,disabled:plan.disabled,
      retainedPackages:plan.retainedPackages,
      frontendDecisionsRequired:plan.frontendDecisionsRequired,
      hybridRetained:plan.hybridRetained,
      prunedPackages:toDelete,
      archivedPackages:archived,
      blocked,backup:relative(project,backup),
      projectFeatureCountPreserved:plan.protectedProjectFeatureCount,
    };
    saveSource(lastSyncPath,JSON.stringify(report,null,2)+'\n');
    return {applied:true,backup:relative(project,backup),
      hidden:plan.disabled,retainedPackages:plan.retainedPackages,
      prunedPackages:toDelete,archivedPackages:archived,blocked};
  }catch(error){
    const recovery=[];
    // Restore each moved package only when its original destination is
    // still vacant; a concurrent writer always wins over auto-recovery.
    for(const {source,archivedAt,rel} of [...moved].reverse()){
      try{
        if(!pathEntryExists(source)&&pathEntryExists(archivedAt))
          renameSync(archivedAt,source);
        else recovery.push('Review archived package: '+rel);
      }catch{recovery.push('Restore package from archive manually: '+rel);}
    }
    for(const [path,written] of [...writes].reverse()){
      try{
        if(!pathEntryExists(path)){
          recovery.push('Review missing app source: '+relative(project,path));
          continue;
        }
        assertRegularProjectPath(project,path,'file');
        if(readFileSync(path,'utf8')!==written){
          recovery.push('Concurrent app source preserved: '+relative(project,path));
          continue;
        }
        const original=originalText.get(path);
        if(original===null)rmSync(path,{force:false});
        else writeFileSync(path,original,'utf8');
      }catch{recovery.push('Restore original app source from backup: '+relative(project,path));}
    }
    throw Error(error.message+(recovery.length?
      '; STOP and review source backups: '+recovery.join('; '):''));
  }
}
export function syncProjectFeatures(root,verified,{apply=false,prune=false}={}){
  if(prune&&!apply)throw Error('--prune requires --apply');
  const plan=planFeatureSync(root,verified,{prune});
  // Every project apply checks the physical source before mutations/backups.
  // Legacy is explicitly reported as NOT certified, and any new feature
  // package without typed layers fails closed. The preview never mutates.
  const architecture=auditFeatureArchitectures(root);
  if(!apply){
    return {applied:false,...plan,architecture:{
      enforced:architecture.adopted,legacyNotCertified:architecture.legacy,
      findings:architecture.findings,
    }};
  }
  if(architecture.findings.length){
    throw Error('RC115 feature architecture gate rejected project apply: '+
      architecture.findings.join('; '));
  }
  return {...plan,...applyPrune(root,plan,{prune}),
    architecture:{enforced:architecture.adopted,
      legacyNotCertified:architecture.legacy,findings:[]}};
}
function parse(argv){
  const options={};
  for(let i=0;i<argv.length;i++){
    const k=argv[i];
    if(['--apply','--prune'].includes(k)){options[k.slice(2)]=true;continue;}
    if(!k.startsWith('--')||!argv[i+1])throw Error('Unknown/missing option: '+k);
    options[k.slice(2)]=argv[++i];
  }
  return options;
}
if(process.argv[1]&&import.meta.url===pathToFileURL(resolve(process.argv[1])).href){
  try{
    const o=parse(process.argv.slice(2)),root=resolve(o.out??process.cwd());
    const imported=importBackendDecisions(o.source??root,{
      expectedProjectId:o['expected-project-id']??null,
      expectedContractHash:o['expected-contract-hash']??null,
    });
    // RC396: there must be ONE protected apply path. Copying W3 assets and
    // applying W6 separately used to bypass the durable RC394 rollback
    // when the CLI (rather than the interactive Wizard) was invoked.
    if(o.apply){
      const {applyReviewedSnapshot}=await import('./flutter-setup-wizard.mjs');
      const result=await applyReviewedSnapshot(root,imported,{
        source:o.source??root,prune:Boolean(o.prune),
      });
      console.log(JSON.stringify(result,null,2));
    }else{
      console.log(JSON.stringify(
        syncProjectFeatures(root,imported,{apply:false,prune:Boolean(o.prune)}),
        null,2));
    }
  }catch(e){console.error(String(e?.message??e));process.exitCode=1;}
}

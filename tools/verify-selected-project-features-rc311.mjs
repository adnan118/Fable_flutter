#!/usr/bin/env node
/**
 * RC311 W3/W5/W8 — independently re-render each pinned selected feature and
 * compare exact generated source bytes + app bindings. Read-only: no SDK,
 * network, Flutter build, database, or project writes.
 */
import {existsSync,lstatSync,readdirSync,readFileSync} from 'node:fs';
import {resolve,join,relative,sep} from 'node:path';
import {createHash} from 'node:crypto';
import {pathToFileURL} from 'node:url';
import {planPinnedTypedFeature} from './generate-typed-feature-rc116.mjs';
import {w5FeatureNames} from './w5-app-feature-binding.mjs';

const SHA256=/^[a-f0-9]{64}$/;
const SOURCES=[
  'assets/config/backend.json',
  'assets/contracts/contract.json',
  'assets/contracts/openapi.json',
  '.fable/frontend-setup.json',
  '.fable/project-features.json',
  '.fable/feature-integration-requirements.json',
];
const digest=s=>createHash('sha256').update(s).digest('hex');
function fail(message){throw Error('RC311 source attestation refused: '+message);}
function safeEntry(root,path,type){
  const rel=relative(root,path);
  if(rel==='..'||rel.startsWith('..'+sep)||rel.startsWith(sep))
    fail('path outside generated project');
  const parts=rel?rel.split(sep):[];
  let here=root;
  for(let i=0;i<=parts.length;i++){
    if(i>0)here=join(here,parts[i-1]);
    if(!existsSync(here))fail('missing source path: '+relative(root,here));
    const stat=lstatSync(here);
    if(stat.isSymbolicLink())fail('symlink not allowed: '+relative(root,here));
    if(i<parts.length&&!stat.isDirectory())
      fail('non-directory ancestor: '+relative(root,here));
  }
  const last=lstatSync(path);
  if(type==='file'&&!last.isFile())fail('expected a regular file: '+rel);
  if(type==='dir'&&!last.isDirectory())fail('expected a directory: '+rel);
}
function snapshot(root){
  return new Map(SOURCES.map(name=>{
    const p=join(root,...name.split('/'));
    safeEntry(root,p,'file');
    return [name,readFileSync(p,'utf8')];
  }));
}
function unchanged(root,before){
  for(const [name,source] of before){
    const path=join(root,...name.split('/'));
    safeEntry(root,path,'file');
    if(readFileSync(path,'utf8')!==source)
      fail('signed project source changed during verification: '+name);
  }
}
function selected(root){
  const parsed=JSON.parse(readFileSync(join(root,'.fable/project-features.json'),'utf8'));
  const ids=parsed.features?.map(x=>typeof x==='string'?x:x?.id);
  if(parsed.schemaVersion!==1||!Array.isArray(ids)||ids.length<1||ids.length>24||
     ids.some(x=>typeof x!=='string'||!/^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$/.test(x)||x.length>64)||
     new Set(ids).size!==ids.length)fail('invalid or duplicate selected feature identifiers');
  return ids;
}
/** Inspect the *entire* generated tree: an injected extra Dart file is a failure. */
export function verifyRenderedFeatureTree(root,featureId,files){
  const folder=join(root,'packages/features/fable_'+featureId);
  safeEntry(root,folder,'dir');
  const prefix='packages/features/fable_'+featureId+'/';
  const expected=new Map();
  for(const [name,content] of files){
    if(!name.startsWith(prefix)||typeof content!=='string')
      fail('rendered path does not belong to selected package');
    const remainder=name.slice(prefix.length);
    if(!remainder||remainder.split('/').some(x=>!x||x==='.'||x==='..'||x.includes('\\')))
      fail('invalid rendered path');
    if(expected.has(remainder))fail('duplicate rendered file');
    expected.set(remainder,content);
  }
  const actual=[];
  function walk(dir,relativeDir=''){
    safeEntry(root,dir,'dir');
    for(const entry of readdirSync(dir,{withFileTypes:true})){
      const sub=relativeDir?relativeDir+'/'+entry.name:entry.name;
      const full=join(dir,entry.name);
      if(entry.isSymbolicLink())fail('symlink inside package: '+sub);
      if(entry.isDirectory())walk(full,sub);
      else if(entry.isFile())actual.push(sub);
      else fail('unrecognized package source type: '+sub);
    }
  }
  walk(folder);
  if(actual.length!==expected.size||actual.some(name=>!expected.has(name)))
    fail('missing or extra package file: '+featureId);
  const h=createHash('sha256');
  for(const name of [...expected.keys()].sort()){
    const file=join(folder,...name.split('/'));
    safeEntry(root,file,'file');
    const actualBytes=readFileSync(file,'utf8');
    if(actualBytes!==expected.get(name))
      fail('generated source differs from signed render: '+featureId+'/'+name);
    h.update(name+'\0'+digest(actualBytes)+'\n');
  }
  return {featureId,fileCount:expected.size,sourceTreeSha256:h.digest('hex')};
}
function exactLineCount(source,line){
  return source.split(/\r?\n/).filter(x=>x===line).length;
}
/** Verify canonical wiring, not just the appearance of a feature name. */
export function verifySelectedAppBindings(pubspec,registry,ids){
  if(typeof pubspec!=='string'||typeof registry!=='string')
    fail('missing host app source');
  if(exactLineCount(pubspec,'dependencies:')!==1)
    fail('host app dependency anchor is ambiguous');
  const marker='const List<FableFeature> installedFeatures = <FableFeature>[\n';
  if(registry.split(marker).length!==2)
    fail('host app registry anchor is ambiguous');
  const afterMarker=registry.split(marker)[1];
  const closing=afterMarker.match(/^\];\s*$/m);
  if(!closing)fail('host app feature list has no canonical closing bracket');
  const registryEntries=afterMarker.slice(0,closing.index);
  for(const id of ids){
    const {packageName,variable}=w5FeatureNames(id);
    const dep='  '+packageName+':\n    path: packages/features/'+packageName+'\n';
    if(!pubspec.includes(dep)||exactLineCount(pubspec,'  '+packageName+':')!==1)
      fail('missing/duplicate canonical dependency: '+id);
    const sourceImport="import 'package:"+packageName+'/'+packageName+".dart';";
    if(exactLineCount(registry,sourceImport)!==1||
       exactLineCount(registryEntries,'  '+variable+',')!==1)
      fail('missing/duplicate canonical feature registry entry: '+id);
  }
}
export function verifyGeneratedSelectedFeatures(options={}){
  const root=resolve(options.root??process.cwd());
  safeEntry(root,root,'dir');
  const projectId=options.expectedProjectId;
  const contractHash=options.expectedContractHash;
  if(typeof projectId!=='string'||!projectId.trim()||projectId.length>160||
     !SHA256.test(contractHash??''))
    fail('independent expected project ID and contract SHA256 required');
  for(const dir of ['.fable','packages','packages/features'])
    safeEntry(root,join(root,...dir.split('/')),'dir');
  const before=snapshot(root);
  const ids=selected(root);
  let count=0,operations=0;
  const packages=[];
  for(const featureId of ids){
    // Verification is the only caller allowed to re-render an existing package.
    const planned=planPinnedTypedFeature(root,{
      featureId,expectedProjectId:projectId,expectedContractHash:contractHash,
      allowExistingPackageForVerification:true,
    });
    count+=planned.files.size;
    operations+=planned.plan.operations.length;
    if(count>2400)fail('source verification exceeds 2400-file cap');
    packages.push(verifyRenderedFeatureTree(root,featureId,planned.files));
  }
  if(options.requireAppWiring!==false){
    const pub=join(root,'pubspec.yaml');
    const registry=join(root,'lib/src/generated/feature_registry.dart');
    safeEntry(root,pub,'file');safeEntry(root,registry,'file');
    verifySelectedAppBindings(readFileSync(pub,'utf8'),readFileSync(registry,'utf8'),ids);
  }
  unchanged(root,before);
  return {
    schemaVersion:1,kind:'fable.selected-feature-source-attestation',
    projectId,contractHash,selected:ids.length,operations,sourceFilesVerified:count,
    packages,appWiringVerified:options.requireAppWiring!==false,
    sourceOnly:true,testsExecuted:false,liveE2EVerified:false,productionReady:false,
    status:'EXACT_SIGNED_RENDERED_SOURCE_VERIFIED',
  };
}
function parseArgs(argv){
  const options={root:process.cwd(),requireAppWiring:true};
  const keys={'--root':'root','--expected-project-id':'expectedProjectId',
    '--expected-contract-hash':'expectedContractHash'};
  const seen=new Set();
  for(let i=0;i<argv.length;i++){
    const flag=argv[i];
    if(flag==='--')continue;
    if(flag==='--help'||flag==='-h')return {help:true};
    if(seen.has(flag))fail('duplicate CLI argument: '+flag);
    seen.add(flag);
    if(flag==='--no-app-wiring'){options.requireAppWiring=false;continue;}
    if(!Object.hasOwn(keys,flag)||!argv[i+1]||argv[i+1].startsWith('--'))
      fail('unsupported or incomplete option: '+flag);
    options[keys[flag]]=argv[++i];
  }
  return options;
}
if(process.argv[1]&&import.meta.url===pathToFileURL(resolve(process.argv[1])).href){
  try{
    const options=parseArgs(process.argv.slice(2));
    if(options.help)console.log('pnpm run wizard:feature:verify -- --root PATH --expected-project-id ID --expected-contract-hash SHA256 [--no-app-wiring]');
    else console.log(JSON.stringify(verifyGeneratedSelectedFeatures(options),null,2));
  }catch(error){console.error(error.message);process.exitCode=2;}
}

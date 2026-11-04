#!/usr/bin/env node
/**
 * RC115: architecture acceptance for ALL newly layered Flutter feature packages.
 *
 * Adoption is detected from source structure (src/{domain,application,data,
 * presentation}), NOT from an opt-in flag alone; deleting a manifest cannot
 * silently disable enforcement. Legacy packages without those folders remain
 * reported as not-yet-migrated, not certified.
 *
 * Source import graph validation complements Dart analyzer and tests; it is NOT
 * an AST/symbol-level proof that business logic is absent from Presentation.
 */
import {existsSync,readFileSync,readdirSync,lstatSync,realpathSync} from 'node:fs';
import {resolve,join,relative,dirname,normalize,sep,extname} from 'node:path';
import {pathToFileURL} from 'node:url';

export const architectureLayers=Object.freeze([
  'domain','application','data','presentation',
]);
const layerSet=new Set(architectureLayers);
const allowedInternal={
  domain:new Set(['domain']),
  application:new Set(['domain','application']),
  data:new Set(['domain','application','data','legacy']),
  presentation:new Set(['domain','application','presentation']),
};
const allowedExternal={
  domain:new Set(['meta','collection']),
  application:new Set(['meta','collection']),
  data:new Set(['meta','collection','dio','fable_core','crypto',
    'shared_preferences','shared_preferences_platform_interface','http']),
  presentation:new Set(['meta','collection','flutter','flutter_riverpod',
    'riverpod','bloc','flutter_bloc','material_ui','cupertino_ui',
    'fable_design_system','intl']),
};
const disallowedPlatform=new Set([
  'dart:io','dart:html','dart:ffi','dart:mirrors','dart:isolate',
]);

function isSafeFeatureId(name){
  return /^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$/.test(name) &&
    name.length<=72 && name!=='core';
}

function directDartFiles(folder,problems,prefix){
  if(!existsSync(folder))return [];
  const files=[];
  const walk=dir=>{
    for(const entry of readdirSync(dir,{withFileTypes:true})){
      const abs=join(dir,entry.name);
      const stat=lstatSync(abs);
      if(stat.isSymbolicLink()){
        problems.push(prefix+': symlink in enforced source tree '+abs);
        continue;
      }
      if(stat.isDirectory())walk(abs);
      else if(stat.isFile()&&extname(abs)==='.dart')files.push(abs);
    }
  };
  walk(folder);
  return files;
}
function readImports(src){
  // Import/export/part are the only Dart directives declaring file links.
  // Regex covers static literal directives and is backed by Dart analyzer;
  // synthetic AST errors still require analyzer, never solely this script.
  return [...src.matchAll(/^\s*(?:import|export|part)\s+['"]([^'"\r\n]+)['"]/gm)]
    .map(m=>m[1]);
}
function localLayer(uri,file,packageId){
  if(uri.startsWith('dart:'))return {kind:'sdk',value:uri};
  if(uri.startsWith('package:')){
    const m=uri.match(/^package:([^/]+)\/(.+)$/);
    if(!m)return {kind:'invalid',value:uri};
    if(m[1]!==packageId)return {kind:'package',value:m[1]};
    // Only explicit lib/src layers and feature-local barrel APIs are allowed.
    if(!m[2].startsWith('src/'))return {kind:'internal',value:'legacy'};
    const parent=m[2].slice(4).split('/')[0];
    return {kind:'internal',value:layerSet.has(parent)?parent:'legacy'};
  }
  if(uri.startsWith('/')||uri.includes('\\')||uri.includes('\0')||
     uri.includes('?')||uri.includes('#')||uri.includes('%')){
    return {kind:'invalid',value:uri};
  }
  // Dart files can import a same-folder filename with no "./" prefix.
  const absolute=resolve(dirname(file),uri);
  const parts=normalize(absolute).split(sep);
  const lib=parts.lastIndexOf('lib');
  if(lib<0||parts[lib+1]!=='src')return {kind:'invalid',value:uri};
  const ownerIndex=parts.lastIndexOf('features');
  if(ownerIndex<0||parts[ownerIndex+1]!=='fable_'+packageId.replace(/^fable_/,'')){
    return {kind:'invalid',value:uri};
  }
  const targetLayer=parts[lib+2];
  return {kind:'internal',value:layerSet.has(targetLayer)?targetLayer:'legacy'};
}

function stripComments(source){
  return source.replace(/\/\*[\s\S]*?\*\//g,'')
    .replace(/^\s*\/\/.*$/gm,'');
}
export function checkLayerSource({featureId,layer,source,file}){
  if(!isSafeFeatureId(featureId)||!layerSet.has(layer))
    throw Error('Invalid feature/layer inputs');
  const packageId='fable_'+featureId;
  const findings=[];
  for(const uri of readImports(source)){
    const target=localLayer(uri,file,packageId);
    if(target.kind==='sdk'){
      if(disallowedPlatform.has(uri)&&layer!=='data'){
        findings.push('forbidden platform library '+uri);
      }
    }else if(target.kind==='package'){
      if(!allowedExternal[layer].has(target.value)){
        findings.push('forbidden external package '+uri);
      }
    }else if(target.kind==='internal'){
      if(!allowedInternal[layer].has(target.value)){
        findings.push('forbidden layer dependency '+layer+' -> '+target.value+' ('+uri+')');
      }
    }else{
      findings.push('unresolved/unsafe import '+uri);
    }
  }
  const sanitized=stripComments(source);
  if(layer!=='data'&&/\bdynamic\b/.test(sanitized)){
    findings.push(layer+' public boundary contains dynamic');
  }
  if(layer==='domain'||layer==='application'){
    if(/\b(Dio|ResponseBody|Response|Widget|BuildContext|FableAuthGateway|BackendApiGateway|FirebaseAuth)\b/.test(sanitized)){
      findings.push(layer+' contains UI/transport type');
    }
  }
  return findings;
}

export function checkFeatureArchitecture(root,featureId){
  root=resolve(root);
  if(!isSafeFeatureId(featureId))throw Error('Invalid feature ID');
  const packageDir=join(root,'packages/features/fable_'+featureId);
  const sourceDir=join(packageDir,'lib/src');
  const marker=join(packageDir,'.fable-architecture.json');
  const findings=[];
  if(!existsSync(packageDir))return ['Missing selected feature package '+featureId];
  // A source folder that adopts one of four layer names is automatically
  // enrolled in strict enforcement, even if its manifest is deleted.
  const adopted=architectureLayers.some(layer=>existsSync(join(sourceDir,layer))) ||
    existsSync(marker);
  if(!adopted)return []; // legacy (not architecturally certified)
  if(!existsSync(marker)){
    findings.push(featureId+': architecture manifest missing');
  }else if(lstatSync(marker).isSymbolicLink()){
    findings.push(featureId+': architecture manifest cannot be a symlink');
  }else{
    try{
      const cfg=JSON.parse(readFileSync(marker,'utf8'));
      if(cfg.kind!=='fable.flutter-feature-architecture'||cfg.schemaVersion!==1||
         cfg.featureId!==featureId||cfg.mode!=='four-layer-typed'||
         cfg.enforced!==true){
        findings.push(featureId+': invalid architecture manifest');
      }
    }catch(_){findings.push(featureId+': unreadable architecture manifest');}
  }
  for(const layer of architectureLayers){
    const folder=join(sourceDir,layer);
    if(!existsSync(folder)){
      findings.push(featureId+': missing '+layer+' layer');
      continue;
    }
    if(lstatSync(folder).isSymbolicLink()){
      findings.push(featureId+': '+layer+' layer cannot be a symlink');
      continue;
    }
    const files=directDartFiles(folder,findings,featureId);
    if(files.length===0){
      findings.push(featureId+': '+layer+' contains no Dart source');
    }
    for(const file of files){
      const source=readFileSync(file,'utf8');
      for(const problem of checkLayerSource({featureId,layer,source,file})){
        findings.push(relative(root,file).split(sep).join('/')+': '+problem);
      }
    }
  }
  return findings;
}

export function auditFeatureArchitectures(root=process.cwd()){
  root=resolve(root);
  const dir=join(root,'packages/features');
  const candidates=[];
  if(!existsSync(dir))return {adopted:[],legacy:[],findings:[]};
  const findings=[],adopted=[],legacy=[];
  for(const entry of readdirSync(dir,{withFileTypes:true})){
    if(!entry.name.startsWith('fable_'))continue;
    const id=entry.name.slice(6);
    if(!isSafeFeatureId(id)){
      findings.push('Invalid feature package name '+entry.name);
      continue;
    }
    if(entry.isSymbolicLink()){
      findings.push('Feature directory symlink forbidden: '+entry.name);
      continue;
    }
    if(!entry.isDirectory())continue;
    const packageDir=join(dir,entry.name);
    const marker=join(packageDir,'.fable-architecture.json');
    const layered=architectureLayers.some(x=>
      existsSync(join(packageDir,'lib/src',x)))||existsSync(marker);
    if(!layered){
      legacy.push(id);
      continue;
    }
    adopted.push(id);
    findings.push(...checkFeatureArchitecture(root,id));
  }
  return {adopted,legacy,findings};
}
if(process.argv[1]&&import.meta.url===pathToFileURL(resolve(process.argv[1])).href){
  const args=process.argv.slice(2);
  const idx=args.indexOf('--root');
  if(args.length!==0 && (idx<0||args.length!==2||!args[idx+1])){
    console.error('Usage: node tools/enforce-feature-architecture-rc115.mjs [--root /path]');
    process.exitCode=2;
  }else{
    const result=auditFeatureArchitectures(idx>=0?args[idx+1]:process.cwd());
    if(result.findings.length){
      for(const problem of result.findings)console.error(problem);
      process.exitCode=1;
    }else{
      console.log('RC115 architecture gate PASS: '+result.adopted.length+
        ' enforced layered feature(s); '+result.legacy.length+
        ' legacy feature(s) not yet certified');
    }
  }
}

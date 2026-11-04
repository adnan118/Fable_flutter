#!/usr/bin/env node
// RC114 incremental architecture gate for new Media Clean Architecture layers.
// This is import-graph enforcement plus dart analyze; NOT a full Dart AST lint.
import {existsSync,readFileSync,readdirSync} from 'node:fs';
import {resolve,join,relative,dirname,extname,normalize} from 'node:path';
import {pathToFileURL} from 'node:url';

const layers=['domain','application','data','presentation'];
const mandatory={
  domain:['media_byte_range.dart','media_byte_source.dart','media_read_result.dart'],
  application:['read_media_range_use_case.dart'],
  data:['fable_media_byte_source.dart'],
  presentation:['media_range_controller.dart'],
};
const allowed={
  domain:new Set(['domain']),
  application:new Set(['application','domain']),
  data:new Set(['data','domain','application','legacy']),
  presentation:new Set(['presentation','application','domain']),
};

function stripComments(source){
  // Only used for detection of type tokens. Actual imports are parsed before.
  return source.replace(/\/\*[\s\S]*?\*\//g,'')
    .replace(/^\s*\/\/.*$/gm,'');
}
function readDirectives(source){
  // Recognizes all normal Dart import/export directives, including show/hide.
  return [...source.matchAll(/^\s*(?:import|export)\s+['"]([^'"]+)['"]/gm)]
    .map(match=>match[1]);
}
function layerOf(uri,layer,filename){
  if(uri.startsWith('dart:'))return 'standard';
  if(uri.startsWith('package:fable_media/src/')){
    const suffix=uri.slice('package:fable_media/src/'.length);
    const first=suffix.split('/')[0];
    return layers.includes(first)?first:'legacy';
  }
  if(uri.startsWith('.')){
    const normalized=normalize(join(dirname(filename),uri));
    const pieces=normalized.split(/[\\/]/);
    const libIndex=pieces.lastIndexOf('src');
    if(libIndex<0)return 'outside';
    const first=pieces[libIndex+1];
    return layers.includes(first)?first:'legacy';
  }
  return 'outside';
}

export function auditMediaLayerFile(layer,source,filename='packages/features/fable_media/lib/src/domain/example.dart'){
  if(!layers.includes(layer))throw new Error('Invalid architecture layer');
  const errors=[];
  for(const uri of readDirectives(source)){
    const kind=layerOf(uri,layer,filename);
    if(kind==='standard'){
      if(layer!=='data' && /^(dart:io|dart:html|dart:ffi|dart:mirrors)$/.test(uri)){
        errors.push(layer+': platform-specific library in '+uri);
      }
    }else if(!allowed[layer].has(kind)){
      errors.push(layer+': forbidden import/export '+uri+' -> '+kind);
    }
    if(layer==='presentation' &&
      /^(package:dio|package:fable_core|package:shared_preferences|package:fable_media\/src\/data)\b/.test(uri)){
      errors.push('presentation: direct transport/persistence dependency '+uri);
    }
  }
  const noComments=stripComments(source);
  if((layer==='domain'||layer==='application') && /\bdynamic\b/.test(noComments)){
    errors.push(layer+': dynamic types are not permitted in typed contracts');
  }
  // Domain/application must not know Flutter/Dio or local backend symbols,
  // including fully qualified names embedded in type signatures.
  if((layer==='domain'||layer==='application') &&
     /\b(Dio|ResponseBody|Widget|BuildContext|FableAuthGateway|BackendApiGateway)\b/.test(noComments)){
    errors.push(layer+': transport or Flutter type exposed');
  }
  return errors;
}

function allDartFiles(folder){
  if(!existsSync(folder))return [];
  const found=[];
  for(const entry of readdirSync(folder,{withFileTypes:true})){
    const file=join(folder,entry.name);
    if(entry.isDirectory())found.push(...allDartFiles(file));
    else if(entry.isFile()&&extname(file)==='.dart')found.push(file);
  }
  return found;
}

export function auditMediaArchitecture(root=process.cwd()){
  const base=join(root,'packages/features/fable_media/lib/src');
  const findings=[];
  for(const layer of layers){
    const folder=join(base,layer);
    for(const required of mandatory[layer]){
      if(!existsSync(join(folder,required))){
        findings.push('Missing required '+layer+' source '+required);
      }
    }
    for(const file of allDartFiles(folder)){
      const display=relative(root,file);
      for(const problem of auditMediaLayerFile(layer,readFileSync(file,'utf8'),file)){
        findings.push(display+': '+problem);
      }
    }
  }
  return findings;
}
if(process.argv[1] && import.meta.url===pathToFileURL(resolve(process.argv[1])).href){
  const problems=auditMediaArchitecture();
  if(problems.length){
    for(const problem of problems)console.error(problem);
    process.exitCode=1;
  }else{
    console.log('RC114: typed Media layer import graph and boundary gate PASS');
  }
}

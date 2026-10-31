#!/usr/bin/env node
/**
 * Frontend-owned (native/hybrid) project decisions.
 * Never imports/rewrites Backend session policies, roles, or operation rights.
 * Changes are explicit; no feature package is deleted by this command.
 */
import {existsSync,readFileSync} from 'node:fs';
import {resolve,join} from 'node:path';
import {createInterface} from 'node:readline/promises';
import {pathToFileURL} from 'node:url';
import {FEATURE_OWNERSHIP} from './frontend-feature-ownership.mjs';
import {readFrontendOwnedDecisions,updateFrontendOwnedChoice} from './frontend-owned-decisions.mjs';

function resolveProjectId(root) {
  const file=resolve(root,'.fable/frontend-setup.json');
  if(!existsSync(file))throw Error('Import the Fable Backend first; project identity is missing');
  const data=JSON.parse(readFileSync(file,'utf8'));
  if(typeof data?.projectId!=='string'||!data.projectId.trim())
    throw Error('Invalid frontend project ID');
  return data.projectId;
}
export function reviewFrontendChoices(root,projectId) {
  const cfg=readFrontendOwnedDecisions(root,projectId);
  const rows=Object.entries(cfg.choices).map(([id,value])=>({
    id,ownership:value.ownership,
    decision:value.enabled===null?'REVIEW':value.enabled?'ENABLED':'DISABLED',
    backendPermissions:'not-overridden',
  }));
  return {projectId,kind:cfg.kind,rows};
}
export async function chooseFrontendFeature(root,projectId,{
  feature,state,ask,show=console.log,
}={}){
  if(!(feature in FEATURE_OWNERSHIP)||FEATURE_OWNERSHIP[feature]==='server')
    throw Error('Only frontend-only or hybrid features may be configured here: '+feature);
  const choices={on:true,off:false,review:null};
  if(!Object.hasOwn(choices,state))throw Error('State must be on, off, or review');
  if(typeof ask!=='function')throw Error('Explicit approval callback required');
  const preview=reviewFrontendChoices(root,projectId);
  show(JSON.stringify({preview,change:{feature,ownership:FEATURE_OWNERSHIP[feature],
    state,backendPermissions:'unchanged',deletesPackages:false}},null,2));
  const answer=await ask('اكتب «اعتمد» أو APPROVE لتغيير قرار Flutter المحلي: ');
  if(!['اعتمد','APPROVE'].includes(String(answer??'').trim())){
    show('تم الإلغاء؛ لم يُحذف أو يتغير أي ملف.');
    return {applied:false,cancelled:true};
  }
  updateFrontendOwnedChoice(root,projectId,feature,choices[state],{apply:true});
  return {applied:true,feature,state,backendPermissions:'unchanged',deletesPackages:false};
}
if(process.argv[1]&&import.meta.url===pathToFileURL(resolve(process.argv[1])).href){
  const args=process.argv.slice(2),root=process.cwd();
  const feature=args[0],state=args[1];
  const cli=createInterface({input:process.stdin,output:process.stdout});
  try{
    const projectId=resolveProjectId(root);
    if(!feature&&!state){
      console.log(JSON.stringify(reviewFrontendChoices(root,projectId),null,2));
    }else{
      console.log(JSON.stringify(await chooseFrontendFeature(root,projectId,{
        feature,state,ask:prompt=>cli.question(prompt),
      }),null,2));
    }
  }catch(e){console.error(e.message??String(e));process.exitCode=1;}
  finally{cli.close();}
}

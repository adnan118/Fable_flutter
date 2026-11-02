#!/usr/bin/env node
// Per-project, explicit Offline choice. No Backend operation is guessed.
import {existsSync,readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {createInterface} from 'node:readline/promises';
import {pathToFileURL} from 'node:url';
import {readFrontendOwnedDecisions,saveFrontendOwnedDecisions,
  APPROVED_SYNC_MODES} from './frontend-owned-decisions.mjs';

function projectId(root) {
  const file=resolve(root,'.fable/frontend-setup.json');
  if(!existsSync(file))throw Error('Run the main Backend Wizard first');
  const data=JSON.parse(readFileSync(file,'utf8'));
  if(typeof data?.projectId!=='string'||!data.projectId.trim())
    throw Error('Invalid project identity');
  return data.projectId;
}

export function reviewOfflineSync(root,id) {
  const config=readFrontendOwnedDecisions(root,id);
  return {
    projectId:id,
    feature:'offline',
    enabled:config.choices.offline.enabled,
    storage:config.offlineSync.storage,
    policy:config.offlineSync.policy,
    backgroundGuaranteed:false,
    backendPermissions:'unchanged',
    canReplayFinancialOperations:false,
    backendMutationApproval:'per-operation-contract-required',
  };
}

export async function approveOfflineSync(root,id,{
  enabled,policy='foreground_plus_background_best_effort',
  ask,show=console.log,
}={}) {
  if(typeof enabled!=='boolean'||!APPROVED_SYNC_MODES.includes(policy))
    throw Error('Offline must be explicitly on/off and policy must be supported');
  if(typeof ask!=='function')throw Error('Interactive approval required');
  const cfg=readFrontendOwnedDecisions(root,id);
  const next={
    ...cfg,
    choices:{...cfg.choices,
      offline:{...cfg.choices.offline,enabled}},
    offlineSync:{...cfg.offlineSync,policy},
  };
  show(JSON.stringify({current:reviewOfflineSync(root,id),
    proposed:{enabled,policy,storage:'sqlite_drift',
      backgroundGuaranteed:false,
      writes:'blocked until Backend contract verification'},
    noBackendChanges:true,deletesNoPackages:true},null,2));
  const answer=String(await ask('اكتب «اعتمد» أو APPROVE لتفعيل قرار Offline للمشروع: ')).trim();
  if(!['اعتمد','APPROVE'].includes(answer))
    return {applied:false,cancelled:true};
  saveFrontendOwnedDecisions(root,next,{apply:true});
  return {applied:true,projectId:id,offlineEnabled:enabled,policy,
    backendSecurityOverride:false,mutationContractVerified:false};
}

async function main() {
  const args=process.argv.slice(2);
  const root=process.cwd(),id=projectId(root);
  if(args.length===0||args[0]==='review'){
    console.log(JSON.stringify(reviewOfflineSync(root,id),null,2));
    return;
  }
  const on=args[0]==='on'?true:args[0]==='off'?false:null;
  const policy=args[1]??'foreground_plus_background_best_effort';
  if(on===null||!APPROVED_SYNC_MODES.includes(policy))
    throw Error('Use: pnpm wizard:offline [review|on|off] [foreground_only|foreground_plus_background_best_effort]');
  const cli=createInterface({input:process.stdin,output:process.stdout});
  try{
    const out=await approveOfflineSync(root,id,{
      enabled:on,policy,ask:message=>cli.question(message),
    });
    console.log(JSON.stringify(out,null,2));
  }finally{cli.close();}
}

if(process.argv[1]&&import.meta.url===pathToFileURL(resolve(process.argv[1])).href)
  main().catch(e=>{console.error('Offline Wizard: '+e.message);process.exitCode=1;});

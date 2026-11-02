// Flutter-only source of truth for native and hybrid UI choices.
// Never imported from Backend and never used to grant Backend permissions.
import {existsSync,readFileSync,writeFileSync,mkdirSync} from 'node:fs';
import {dirname,resolve} from 'node:path';
import {FEATURE_IDS,FEATURE_OWNERSHIP} from './frontend-feature-ownership.mjs';
export const OWNED_CONFIG_PATH='.fable/frontend-owned-decisions.json';
export const OWNED_ASSET_PATH='assets/config/frontend-owned-decisions.json';
function read(path){return JSON.parse(readFileSync(path,'utf8'));}
function write(path,object){mkdirSync(dirname(path),{recursive:true});writeFileSync(path,JSON.stringify(object,null,2)+'\n');}
function assertChoice(choice,id){
  if(choice===null || typeof choice==='boolean')return;
  throw Error('Frontend choice must be true, false, or null (review): '+id);
}
export const APPROVED_SYNC_MODES=Object.freeze([
 'foreground_only','foreground_plus_background_best_effort'
]);
export const DEFAULT_OFFLINE_SYNC_POLICY=Object.freeze({
 schemaVersion:1,
 storage:'sqlite_drift',
 policy:'foreground_plus_background_best_effort',
 writeReplay:'verified_backend_operation_only',
 conflict:'server_version_preconditions_required',
 financial:'online_revalidation_required',
 scheduler:'android_workmanager_ios_bgtaskscheduler',
 guaranteedBackgroundExecution:false,
});
export function validateOfflineSyncPolicy(policy) {
 if(!policy||typeof policy!=='object'||Array.isArray(policy)||
   policy.schemaVersion!==1||policy.storage!=='sqlite_drift'||
   !APPROVED_SYNC_MODES.includes(policy.policy)||
   policy.writeReplay!=='verified_backend_operation_only'||
   policy.conflict!=='server_version_preconditions_required'||
   policy.financial!=='online_revalidation_required'||
   policy.scheduler!=='android_workmanager_ios_bgtaskscheduler'||
   policy.guaranteedBackgroundExecution!==false||
   Object.keys(policy).length!==Object.keys(DEFAULT_OFFLINE_SYNC_POLICY).length) {
   throw Error('Invalid Offline/Sync policy: backend authority and background schedule must remain fail-closed');
 }
 return policy;
}
export function frontendOwnedDefaults(projectId){
  if(typeof projectId!=='string'||!projectId.trim())throw Error('Missing frontend project ID');
  return {
    schemaVersion:1,kind:'fable.flutter-owned-decisions',projectId,
    authority:'frontend-only',backendSecurityOverride:false,
    choices:Object.fromEntries(FEATURE_IDS.filter(id=>FEATURE_OWNERSHIP[id]!=='server')
      .map(id=>[id,{ownership:FEATURE_OWNERSHIP[id],enabled:null}])),
    offlineSync:{...DEFAULT_OFFLINE_SYNC_POLICY},
  };
}
export function readFrontendOwnedDecisions(root,projectId){
  const file=resolve(root,OWNED_CONFIG_PATH);
  if(!existsSync(file))return frontendOwnedDefaults(projectId);
  const current=read(file);
  if(current.kind!=='fable.flutter-owned-decisions'||current.schemaVersion!==1 ||
    current.projectId!==projectId||current.backendSecurityOverride!==false ||
    !current.choices||typeof current.choices!=='object'||Array.isArray(current.choices))
    throw Error('Frontend choices exist for another project or have an invalid schema. Review before replacing.');
  const baseline=frontendOwnedDefaults(projectId);
  const names=Object.keys(current.choices);
  if(names.length!==Object.keys(baseline.choices).length)
    throw Error('Frontend choices have incomplete/unknown entries. Review required.');
  for(const [id,value] of Object.entries(baseline.choices)){
    const saved=current.choices[id];
    if(!saved||saved.ownership!==value.ownership)throw Error('Frontend feature ownership conflicts: '+id);
    assertChoice(saved.enabled,id);
  }
  // RC89: existing project decisions from before Offline policy keep their
  // choices; migrating the config cannot turn Offline on silently.
  if(current.offlineSync==null)current.offlineSync={...DEFAULT_OFFLINE_SYNC_POLICY};
  validateOfflineSyncPolicy(current.offlineSync);
  return current;
}
export function saveFrontendOwnedDecisions(root,config,{apply=false}={}){
  if(config?.kind!=='fable.flutter-owned-decisions' || config.schemaVersion!==1 ||
    config.authority!=='frontend-only' || config.backendSecurityOverride!==false)
    throw Error('Invalid Flutter decisions');
  const baseline=frontendOwnedDefaults(config.projectId);
  if(!config.choices||typeof config.choices!=='object' ||
    Object.keys(config.choices).length!==Object.keys(baseline.choices).length)
    throw Error('Incomplete Flutter-owned choices');
  for(const [id,choice] of Object.entries(baseline.choices)){
    if(config.choices[id]?.ownership!==choice.ownership)
      throw Error('Invalid Flutter ownership: '+id);
    assertChoice(config.choices[id].enabled,id);
  }
  validateOfflineSyncPolicy(config.offlineSync);
  const path=resolve(root,OWNED_CONFIG_PATH);
  // Ensure a previously recorded local choice is not replaced by an unrelated project.
  if(existsSync(path))readFrontendOwnedDecisions(root,config.projectId);
  if(!apply)return {applied:false,path:OWNED_CONFIG_PATH};
  write(path,config);
  write(resolve(root,OWNED_ASSET_PATH),config);
  return {applied:true,path:OWNED_CONFIG_PATH};
}
export function updateFrontendOwnedChoice(root,projectId,feature,enabled,{apply=false}={}){
  const config=readFrontendOwnedDecisions(root,projectId);
  if(!(feature in config.choices))throw Error('Not a Flutter-owned feature: '+feature);
  assertChoice(enabled,feature);
  const next={...config,choices:{...config.choices,[feature]:{...config.choices[feature],enabled}}};
  if(apply)saveFrontendOwnedDecisions(root,next,{apply:true});
  return next;
}

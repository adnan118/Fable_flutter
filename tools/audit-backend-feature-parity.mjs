#!/usr/bin/env node
// Feature-by-feature integration audit. A code string is NOT equivalent to
// a verified working frontend: evidence classes distinguish source wiring,
// missing UI, and live end-to-end verification.
import {existsSync,readFileSync,writeFileSync,mkdirSync} from 'node:fs';
import {resolve,join,dirname} from 'node:path';
import {pathToFileURL} from 'node:url';
import {verifyFableContract} from './verify-fable-contract.mjs';

const WIRED=Object.freeze({
  'auth.login':'packages/fable_core/lib/src/fable_auth_gateway.dart',
  'auth.refresh':'packages/fable_core/lib/src/fable_auth_gateway.dart',
  'auth.logout':'packages/fable_core/lib/src/fable_auth_gateway.dart',
  'auth.sessions':'packages/fable_core/lib/src/fable_auth_gateway.dart',
  'auth.session-policy':'packages/fable_core/lib/src/fable_auth_gateway.dart',
  'auth.2fa.login.request':'packages/fable_core/lib/src/fable_auth_gateway.dart',
  'auth.2fa.login.complete':'packages/fable_core/lib/src/fable_auth_gateway.dart',
  'account.me':'packages/fable_core/lib/src/fable_auth_gateway.dart',
  'account.displayName.update':'packages/fable_core/lib/src/fable_auth_gateway.dart',
  'auth.social.challenge':'packages/features/fable_social/lib/src/social_auth_repository.dart',
  'auth.social.google':'packages/features/fable_social/lib/src/social_auth_repository.dart',
  'auth.social.apple':'packages/features/fable_social/lib/src/social_auth_repository.dart',
  'auth.social.google.link':'packages/features/fable_social/lib/src/social_auth_repository.dart',
  'auth.social.apple.link':'packages/features/fable_social/lib/src/social_auth_repository.dart',
  'auth.social.unlink':'packages/features/fable_social/lib/src/social_auth_repository.dart',
  'passkeys.authentication.options':'packages/features/fable_biometrics/lib/src/biometrics_repository.dart',
  'passkeys.authentication.verify':'packages/features/fable_biometrics/lib/src/biometrics_repository.dart',
});
// Screen evidence is separate from Gateway evidence; neither proves a live
// Backend session. Keep Auth sessions as the first mapped workflow.
const VIEW_SOURCES=Object.freeze({
  'auth.login':'packages/features/fable_auth/lib/src/login_page.dart',
  'auth.sessions':'packages/features/fable_auth/lib/src/sessions_page.dart',
});
const MOBILE_CORE='assets/contracts/mobile-core-operations.json';
const isWebOnly=op=>op.id.startsWith('auth.web.')||op.path.startsWith('/auth/web/');
const unique=(items)=>{
  const map=new Map();
  for(const op of items){
    const id=op?.operationId;
    if(typeof id!=='string'||!id.trim())continue;
    if(map.has(id)){
      const previous=map.get(id);
      if(previous.method!==op.method || previous.path!==op.path ||
        previous.public!==op.public)throw Error('Conflicting Backend operation: '+id);
    }else map.set(id,{id,method:op.method,path:op.path,
      public:op.public,feature:op.feature??null});
  }
  return [...map.values()].sort((a,b)=>a.id.localeCompare(b.id));
};
function load(root){
  const p=resolve(root,'assets/contracts/contract.json');
  const core=resolve(root,MOBILE_CORE);
  if(!existsSync(p)||!existsSync(core))throw Error('Missing imported backend contracts');
  const c=JSON.parse(readFileSync(p,'utf8'));
  const m=JSON.parse(readFileSync(core,'utf8'));
  return {contract:c,operations:unique([...(c.operations??[]),...(m.operations??[])])};
}
export function auditBackendFeatureParity(root,{requireProjectBinding=false,expectedProjectId=null,expectedContractHash=null}={}){
  const path=resolve(root),gate=verifyFableContract(path,{
    mode:requireProjectBinding?'project':'source',
    expectedProjectId,expectedContractHash});
  if(!gate.ok)throw Error('Invalid imported Backend contract: '+gate.failures.join(','));
  const {contract,operations}=load(path);
  const projectFeatures=contract.core?.frontendSetup?.decisions?.frontendFeatures??null;
  if(projectFeatures && !Array.isArray(projectFeatures.enabled))
    throw Error('Invalid backend frontend feature declarations');
  const mapped=operations.map(op=>{
    if(isWebOnly(op))return {...op,status:'NOT_FOR_FLUTTER',source:null,
      nextAction:'No native mobile implementation; Backend Web transport only'};
    const source=WIRED[op.id]??null;
    if(!source)return {...op,status:'NOT_MAPPED',source:null,
      nextAction:'Implement and test this endpoint in an appropriate frontend feature'};
    if(!existsSync(join(path,source)) ||
       !readFileSync(join(path,source),'utf8').includes("'"+op.id+"'"))
      return {...op,status:'MAPPING_STALE',source,
        nextAction:'Update frontend source and contract binding before claiming coverage'};
    const viewSource=VIEW_SOURCES[op.id]??null;
    const screenWired=viewSource!=null&&existsSync(join(path,viewSource))&&
      (op.id==='auth.sessions'
        ?readFileSync(join(path,viewSource),'utf8').includes('listActiveSessions')
        :readFileSync(join(path,viewSource),'utf8').includes('auth.login'));
    return {...op,status:'SOURCE_WIRED_NOT_LIVE_TESTED',source,
      viewSource:screenWired?viewSource:null,
      presentationEvidence:screenWired?'SCREEN_WIRED_NOT_LIVE_TESTED':'SCREEN_NOT_VERIFIED',
      nextAction:'Validate request/response/errors/permissions and a real Android/iOS Backend flow'};
  });
  const counts=Object.fromEntries(['SOURCE_WIRED_NOT_LIVE_TESTED','NOT_MAPPED','MAPPING_STALE','NOT_FOR_FLUTTER']
    .map(status=>[status,mapped.filter(x=>x.status===status).length]));
  return {
    schemaVersion:1,kind:'fable.flutter-feature-parity-audit',
    projectId:contract.project?.id??null,contractHash:contract.contractHash,
    projectBound:gate.projectBound,productionReady:false,
    enabledBackendFeatures:projectFeatures?.enabled??null,
    operationCount:mapped.length,counts,operations:mapped,
    assurance:'Source wiring only; e2e tests required before marking operations complete',
  };
}
if(process.argv[1]&&import.meta.url===pathToFileURL(resolve(process.argv[1])).href){
  try{
    const args=process.argv.slice(2),root=resolve(args[0]??process.cwd());
    const id=args[1]??null,hash=args[2]??null;
    const report=auditBackendFeatureParity(root,{
      requireProjectBinding:Boolean(id||hash),
      expectedProjectId:id,expectedContractHash:hash});
    const target=resolve(root,'.fable','feature-parity-report.json');
    mkdirSync(dirname(target),{recursive:true});
    writeFileSync(target,JSON.stringify(report,null,2)+'\n');
    console.log(JSON.stringify({output:target,counts:report.counts,
      productionReady:report.productionReady},null,2));
  }catch(e){console.error(e.message??String(e));process.exitCode=1;}
}

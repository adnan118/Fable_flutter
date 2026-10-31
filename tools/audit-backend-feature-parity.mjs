#!/usr/bin/env node
// Feature-by-feature integration audit. A code string is NOT equivalent to
// a verified working frontend: evidence classes distinguish source wiring,
// missing UI, and live end-to-end verification.
import {existsSync,readFileSync,writeFileSync,mkdirSync} from 'node:fs';
import {resolve,join,dirname} from 'node:path';
import {pathToFileURL} from 'node:url';
import {verifyFableContract} from './verify-fable-contract.mjs';
import {FEATURE_IDS,FEATURE_OWNERSHIP} from './frontend-feature-ownership.mjs';

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
  'content.page.read':'packages/features/fable_content/lib/src/published_content_repository.dart',
  'content.page.accept':'packages/features/fable_content/lib/src/published_content_repository.dart',
  'content.publicChanges':'packages/features/fable_content/lib/fable_content.dart',
  'notifications.inbox':'packages/features/fable_notifications/lib/src/inbox_repository.dart',
  'notifications.read':'packages/features/fable_notifications/lib/src/inbox_repository.dart',
  'languages.list':'packages/features/fable_localization/lib/src/languages_repository.dart',
  'languages.clientCopy':'packages/features/fable_localization/lib/src/client_copy_sync.dart',
  'media.clientContract':'packages/features/fable_media/lib/src/media_read_repository.dart',
  'media.metadata':'packages/features/fable_media/lib/src/media_read_repository.dart',
  'media.upload.prepare':'packages/features/fable_media/lib/src/media_upload_repository.dart',
  'media.upload.status':'packages/features/fable_media/lib/src/media_upload_repository.dart',
  'media.upload.chunk':'packages/features/fable_media/lib/src/media_upload_repository.dart',
  'media.upload.partUrl':'packages/features/fable_media/lib/src/media_upload_repository.dart',
  'media.upload.partAck':'packages/features/fable_media/lib/src/media_upload_repository.dart',
  'media.upload.complete':'packages/features/fable_media/lib/src/media_upload_repository.dart',
  'media.upload.abort':'packages/features/fable_media/lib/src/media_upload_repository.dart',
});
// Screen evidence is separate from Gateway evidence; neither proves a live
// Backend session. Keep Auth sessions as the first mapped workflow.
const VIEW_SOURCES=Object.freeze({
  'auth.login':'packages/features/fable_auth/lib/src/login_page.dart',
  'auth.sessions':'packages/features/fable_auth/lib/src/sessions_page.dart',
  'content.page.read':'packages/features/fable_content/lib/src/published_content_index.dart',
  'notifications.inbox':'packages/features/fable_notifications/lib/src/inbox_page.dart',
  'languages.list':'packages/features/fable_localization/lib/src/languages_page.dart',
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
// The checked-in ci_fable starter contains a narrow demo contract. It is
// not an exhaustive API surface for every project/capability in Backend.
export function featureOfOperation(op){
  const id=op.id;
  if(id.startsWith('auth.social.'))return 'social';
  if(id.startsWith('passkeys.'))return 'biometrics';
  if(id.startsWith('account.'))return 'profile';
  if(id.startsWith('managed-entities.')||id.startsWith('managed-accounts.'))return 'profile';
  if(id.startsWith('auth.'))return 'auth';
  if(id.startsWith('push.'))return 'notifications';
  if(id.startsWith('languages.'))return 'localization';
  if(id.startsWith('permissions.')||id.startsWith('roles.')||
     id.startsWith('access.'))return 'access_control';
  if(id.startsWith('payment.'))return 'payments';
  const prefix=id.split('.')[0];
  return FEATURE_IDS.includes(prefix)?prefix:null;
}
function getNativeScreenEvidence(root,id){
  const source=`packages/features/fable_${id}/lib/fable_${id}.dart`;
  const file=join(root,source);
  if(!existsSync(file))return {source:null,customFableScreen:false,customExternalScreen:false};
  const code=readFileSync(file,'utf8');
  // This detects an owned screen factory, not its business/UX completeness.
  return {
    source,customFableScreen:/@override\\s+Widget\\s+screen\\s*\\(/.test(code),
    customExternalScreen:/@override\\s+Widget\\?\\s+externalScreen\\s*\\(/.test(code),
  };
}
function auditFeatureMatrix(root,operations,features,projectBound){
  const registryPath=join(root,'lib/src/generated/feature_registry.dart');
  const registry=existsSync(registryPath)?readFileSync(registryPath,'utf8'):'';
  return FEATURE_IDS.map(id=>{
    const featureOperations=operations.filter(o=>featureOfOperation(o)===id);
    const wired=featureOperations.filter(o=>o.status==='SOURCE_WIRED_NOT_LIVE_TESTED');
    const screens=wired.filter(o=>o.presentationEvidence==='SCREEN_WIRED_NOT_LIVE_TESTED');
    const configured=features
      ?features.enabled.includes(id)?'ENABLED'
      :features.disabled?.includes(id)?'DISABLED'
      :features.clientOnlyReview?.includes(id)?'CLIENT_DECISION'
      :'NOT_DECLARED'
      :'NO_BACKEND_FEATURE_INVENTORY';
    const packagePresent=existsSync(join(root,'packages/features/fable_'+id,'pubspec.yaml'));
    const registered=registry.includes("package:fable_"+id+"/");
    const nativeScreen=getNativeScreenEvidence(root,id);
    const missingOperationIds=featureOperations
      .filter(o=>o.status==='NOT_MAPPED'||o.status==='MAPPING_STALE')
      .map(o=>o.id);
    return {
      id,ownership:FEATURE_OWNERSHIP[id],packagePresent,registered,
      nativeScreen,
      missingOperationIds,
      contractOperationCoverage:featureOperations.length===0?null:
        {referenced:wired.length,total:featureOperations.length},
      completeFeature:false, // requires per-operation UI, errors, permissions & live verification
      backendDecision:configured,operationCount:featureOperations.length,
      sourceWiredOperationCount:wired.length,screenWiredCount:screens.length,
      operationIds:featureOperations.map(o=>o.id),
      liveVerified:false,
      status:featureOperations.length===0?'NOT_AUDITED_NO_IMPORTED_OPERATIONS'
        :wired.length===0?'NOT_MAPPED'
        :wired.length<featureOperations.length?'PARTIAL_SOURCE_WIRING'
        :screens.length===0?'GATEWAY_ONLY_NO_VERIFIED_UI'
        :'SOURCE_WIRED_NOT_LIVE_VERIFIED',
      nextAction:projectBound
        ?'Verify all Backend operations, permissions, errors and Android/iOS runtime behavior'
        :'Import and independently pin the real project Backend contract; fixture/source only',
    };
  });
}
export function auditBackendFeatureParity(root,{requireProjectBinding=false,expectedProjectId=null,expectedContractHash=null}={}){
  const path=resolve(root);
  const backendConfigPath=join(path,'assets/config/backend.json');
  if(!existsSync(backendConfigPath))throw Error('Backend selection is required before a parity audit');
  const backendConfig=JSON.parse(readFileSync(backendConfigPath,'utf8'));
  if(backendConfig?.backend?.kind!=='fable' ||
     backendConfig.backend?.adapter!=='fable-contract' ||
     backendConfig.backend?.status!=='ready' ||
     backendConfig.contractImported!==true)
    throw Error('Fable parity audit refused for an unverified or non-Fable Backend; use the external adapter audit');
  const gate=verifyFableContract(path,{
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
        :op.id==='content.page.read'
          ?readFileSync(join(path,viewSource),'utf8').includes('FablePublishedContentPage')
        :op.id==='notifications.inbox'
          ?readFileSync(join(path,viewSource),'utf8').includes('FableInboxPage')
        :op.id==='languages.list'
          ?readFileSync(join(path,viewSource),'utf8').includes('FableLanguagesPage')
        :readFileSync(join(path,viewSource),'utf8').includes('auth.login'));
    return {...op,status:'SOURCE_WIRED_NOT_LIVE_TESTED',source,
      viewSource:screenWired?viewSource:null,
      presentationEvidence:screenWired?'SCREEN_WIRED_NOT_LIVE_TESTED':'SCREEN_NOT_VERIFIED',
      nextAction:'Validate request/response/errors/permissions and a real Android/iOS Backend flow'};
  });
  const featureMatrix=auditFeatureMatrix(path,mapped,projectFeatures,gate.projectBound);
  const fixturePath=join(path,'.fable/project-features.json');
  const fixture=existsSync(fixturePath) &&
    JSON.parse(readFileSync(fixturePath,'utf8')).app==='apps/ci_fable';
  const auditScope={
    importedContractKind:fixture?'CI_STARTER_DEMO_CONTRACT':'PROJECT_CONTRACT',
    independentlyProjectBound:gate.projectBound,
    backendFeatureInventoryPresent:Boolean(projectFeatures),
    featureCount:FEATURE_IDS.length,
    featuresWithoutImportedOperations:featureMatrix
      .filter(f=>f.operationCount===0).map(f=>f.id),
    exhaustiveBackendFeatureAudit:false,
    note:fixture
      ?'ci_fable includes only a demo subset of operations. Do not count packages as integrated Backend features.'
      :'A source contract is not runtime E2E proof; feature inventory and backend project binding are separately required.',
  };
  const counts=Object.fromEntries(['SOURCE_WIRED_NOT_LIVE_TESTED','NOT_MAPPED','MAPPING_STALE','NOT_FOR_FLUTTER']
    .map(status=>[status,mapped.filter(x=>x.status===status).length]));
  return {
    schemaVersion:1,kind:'fable.flutter-feature-parity-audit',
    projectId:contract.project?.id??null,contractHash:contract.contractHash,
    projectBound:gate.projectBound,productionReady:false,
    enabledBackendFeatures:projectFeatures?.enabled??null,
    auditScope,featureMatrix,
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
      auditScope:report.auditScope,
      unverifiedFeatureIds:report.featureMatrix.filter(f=>!f.liveVerified).map(f=>f.id),
      productionReady:report.productionReady},null,2));
  }catch(e){console.error(e.message??String(e));process.exitCode=1;}
}

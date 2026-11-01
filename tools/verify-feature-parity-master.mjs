#!/usr/bin/env node
/**
 * سجل الميزات الرئيسي:
 * - لا يعني وجود Repository أو Widget أن الميزة مكتملة.
 * - يفحص 17 Feature وعقود Fable وOther Backend دون اختراع Endpoint.
 * - للتفاصيل التعليمية: docs/integrations/FLUTTER-BLOC-LEARNING.ar.md
 * - لتفسير الحالات: docs/integrations/FABLE-FLUTTER-PARITY-MASTER.ar.md
 */
import {readFileSync,readdirSync,existsSync,writeFileSync} from 'node:fs';
import {resolve,join} from 'node:path';
import {createHash} from 'node:crypto';
import {pathToFileURL} from 'node:url';
import {FEATURE_IDS,FEATURE_OWNERSHIP} from './frontend-feature-ownership.mjs';

const MASTER='docs/integrations/FABLE-FLUTTER-PARITY-MASTER.json';
const AUTH_INVENTORY='docs/integrations/FABLE-AUTH-OPERATIONS-RC80.json';
const EXPECTED_CAPABILITIES=Object.freeze([
'access-control','account-integrity','account-lifecycle','ai-assistant',
'asvs-security','audit','auth-assurance','auth','availability-governance',
'client-version-governance','commercial-access','company-settings',
'content-pages','distributed-cache','domain-events','edge-web-performance',
'fapi2-security','feature-flags','financial-platform','geo-jurisdiction',
'http-message-signatures','idempotency','job-queue','languages',
'location-platform','logging','mail','managed-accounts','media',
'notification-templates','notifications','oauth-security',
'observability-platform','openfeature-adapter','passkeys','phone-messages',
'problem-details','push-notifications','realtime-communications',
'request-context','scheduled-tasks','search','seo','shared-signals',
'supply-chain-provenance','supported-currencies','system-monitoring',
'system-settings','turnstile','users'
]);
const validSources=new Set(['source_and_selected_ui','repository_and_selected_ui','repository_only','client_source']);
const validExternal=new Set(['mapped_partial','not_proven','client_only']);
const noDuplicates=(arr)=>Array.isArray(arr)&&new Set(arr).size===arr.length;
const isNonempty=(v)=>typeof v==='string'&&v.trim().length>0;

export function validateMaster(root,master){
 const errors=[];
 if(master?.kind!=='fable.flutter-feature-parity-master'||master.schemaVersion!==1)
   errors.push('Unknown feature master schema');
 if(!Array.isArray(master.features)||master.features.length!==FEATURE_IDS.length)
   errors.push('Exactly 17 Flutter features must be declared');
 const features=Array.isArray(master.features)?master.features:[];
 const ids=features.map(f=>f.id);
 if(!noDuplicates(ids)||FEATURE_IDS.some(id=>!ids.includes(id))||
   ids.some(id=>!FEATURE_IDS.includes(id)))errors.push('Feature IDs differ from Flutter ownership registry');
 for(const f of features){
   if(!FEATURE_IDS.includes(f.id))continue;
   if(f.ownership!==FEATURE_OWNERSHIP[f.id])errors.push(f.id+': source ownership drift');
   if(!validSources.has(f.sourceStatus)||!validExternal.has(f.externalStatus))
     errors.push(f.id+': unsupported source/external status');
   if(f.complete!==false||f.liveE2EVerified!==false||
      f.operationCoverage!=='NOT_EXHAUSTIVELY_VERIFIED_FOR_REAL_PROJECT')
     errors.push(f.id+': forbidden completeness claim without verified live per-operation E2E');
   if(f.wizardStatus!=='DECISIONS_PRESENT_PER_OPERATION_PARITY_NOT_PROVEN')
     errors.push(f.id+': wizard proof was upgraded without acceptance');
   for(const field of ['backendCapabilities','frontendEvidence','gaps','otherBackendContract']){
     if(!Array.isArray(f[field]) || (field!=='backendCapabilities' && f[field].length===0) ||
        !noDuplicates(f[field]) || !f[field].every(isNonempty))
       errors.push(f.id+': incomplete '+field);
   }
   for(const file of f.frontendEvidence??[])
     if(!existsSync(resolve(root,file)))errors.push(f.id+': evidence path missing: '+file);
 }
 const seen=new Set();
 for(const f of features)for(const cap of f.backendCapabilities??[]){
   seen.add(cap);
   if(!EXPECTED_CAPABILITIES.includes(cap))
     errors.push(f.id+': invented/renamed Fable capability: '+cap);
 }
 if(!seen.has('auth')||!seen.has('managed-accounts')||!seen.has('financial-platform'))
   errors.push('Critical Auth/Managed/Finance capability coverage missing');
 const decisionPath=resolve(root,'docs/integrations/FABLE-BACKEND-WIDE-DECISIONS-RC81.json');
 if(!existsSync(decisionPath))errors.push('Missing cross-cutting Backend decision register');
 else {
   const inventory=JSON.parse(readFileSync(decisionPath,'utf8'));
   const rows=inventory.decisions;
   const required=['clientTransport','sessionPolicy','identityModel','managedEntitiesPolicy',
     'authProviderAndOtp','structuredErrors','idempotencyAndReplay','conditionalWrite',
     'cacheConsistency','dataOwnershipAndDeletion','featureAccessAndCommercial',
     'capabilityInstalledVsBlueprint','languageAndTime','roleBasedUiAndFeatures'];
   if(inventory.schemaVersion!==1||inventory.kind!=='fable.backend-wide-decision-register'||
      !Array.isArray(rows)||rows.length!==23||!noDuplicates(rows.map(x=>x.id))||
      required.some(x=>!rows.some(r=>r.id===x))||
      rows.some(r=>!isNonempty(r.backendSource)||!isNonempty(r.behavior)||
        !/^[a-f0-9]{40}$/.test(r.sourceGitBlobSha??'')||
        !isNonempty(r.otherBackendRequirement)||!isNonempty(r.flutterAction)||
        r.fullParityVerified!==false||r.projectContractVerified!==false||
        r.liveE2EVerified!==false))
     errors.push('Missing/mutated shared Backend/Wizard/Other decision policy');
 }
 const authPath=resolve(root,AUTH_INVENTORY);
 if(!existsSync(authPath))errors.push('Missing Auth 40-operation checklist');
 else {
   const inventory=JSON.parse(readFileSync(authPath,'utf8'));
   const operations=inventory.operations;
   // يسمح بنقل عملية مصدرية واحدة دون أن تصبح معتمدة إنتاجياً:
   // كل عملية SOURCE_IMPLEMENTED يلزمها أدلة ملفات واختبارات،
   // بينما كل عملية NOT_DECIDED لا يجوز نسب تنفيذ/اختبار إليها.
   if(inventory.schemaVersion!==1||inventory.operationCount!==40||
      !Array.isArray(operations)||operations.length!==40||
      !noDuplicates(operations.map(o=>o.id))||
      operations.some(o=>{
        if(!o.id.startsWith('auth.')||!isNonempty(o.method)||
           !isNonempty(o.path)||o.realE2EVerified!==false)return true;
        if(o.disposition==='NOT_DECIDED')
          return o.modelAndDtoReviewed!==false||o.uiFlowReviewed!==false;
        if(o.disposition!=='SOURCE_IMPLEMENTED_E2E_PENDING'||
           o.modelAndDtoReviewed!==true||o.uiFlowReviewed!==true||
           o.permissionAndErrorReviewed!==true)return true;
        if(!Array.isArray(o.flutterEvidence)||o.flutterEvidence.length<2||
           !Array.isArray(o.regressionTests)||o.regressionTests.length<2||
           !Array.isArray(o.missingGates)||o.missingGates.length<3||
           !Array.isArray(o.otherBackendRequired)||o.otherBackendRequired.length<3)
           return true;
        return [...o.flutterEvidence,...o.regressionTests].some(path=>
          !isNonempty(path)||!existsSync(resolve(root,path)));
      }))
     errors.push('Auth operation checklist has unsupported or unverified completeness claims');
 }
 const paths=[
 'tools/flutter-setup-wizard.mjs',
 'packages/fable_core/lib/src/external_operation_catalog.dart',
 'packages/fable_core/lib/src/external_feature_bindings.dart',
 'packages/fable_core/lib/src/external_auth_gateway.dart',
 'packages/fable_core/lib/src/fable_contract.dart'
 ];
 for(const path of paths)if(!existsSync(resolve(root,path)))
   errors.push('Backend selection/Wizard source missing: '+path);
 const wizard=existsSync(resolve(root,paths[0]))?
   readFileSync(resolve(root,paths[0]),'utf8'):'';
 if(!wizard.includes('classifyFeatureDecisions')||
   !wizard.includes('importBackendDecisions')||
   !wizard.includes('manualFrontendDecisions'))
   errors.push('Wizard no longer separates Fable from manually configured Other Backend');
 const catalog=existsSync(resolve(root,paths[1]))?
   readFileSync(resolve(root,paths[1]),'utf8'):'';
 if(!catalog.includes('operationsHash')||!catalog.includes('sourceHash')||
    !catalog.includes('requiresAuth'))
   errors.push('Other Backend contract no longer proves operation source and auth');
 return {errors,features,declaredCapabilities:[...seen].sort()};
}

function manifestDirectory(root){
 const candidates=[root,join(root,'Fable-Backend-RC66'),join(root,'blueprints','capabilities')];
 for(const candidate of candidates){
   const p=join(candidate,'blueprints','capabilities');
   if(existsSync(p))return p;
   if(candidate.endsWith('/capabilities') && existsSync(candidate))return candidate;
 }
 return null;
}

export function auditBackendManifests(backendRoot,declaredCapabilities){
 const path=manifestDirectory(resolve(backendRoot));
 if(!path)throw Error('Cannot locate Fable-Backend-RC66/blueprints/capabilities in --backend-root');
 const names=readdirSync(path,{withFileTypes:true}).filter(d=>d.isDirectory()&&
   existsSync(join(path,d.name,'manifest.json'))).map(d=>d.name).sort();
 const newCapabilities=names.filter(name=>!EXPECTED_CAPABILITIES.includes(name));
 const missingCapabilities=EXPECTED_CAPABILITIES.filter(name=>!names.includes(name));
 const routes=[],invalid=[];
 const routeKeys=new Set();
 for(const cap of names){
   let manifest;
   try{manifest=JSON.parse(readFileSync(join(path,cap,'manifest.json'),'utf8'));}
   catch(e){invalid.push(cap+': invalid JSON');continue;}
   if(!Array.isArray(manifest.routes))continue;
   for(const r of manifest.routes){
     if(!isNonempty(r.id)||!isNonempty(r.method)||!isNonempty(r.path)||
        routeKeys.has(r.id))invalid.push(cap+': duplicate/invalid route '+r.id);
     else routeKeys.add(r.id);
     const isCandidate=declaredCapabilities.includes(cap);
     // «مرجع مرشح» لا يثبت Model/واجهة/صلاحيات أو أن العملية تخص الموبايل.
     routes.push({capability:cap,id:r.id,method:r.method,path:r.path,
       permission:r.permission??null,
       classification:isCandidate?'FEATURE_CANDIDATE_NEEDS_PER_OPERATION_REVIEW':
        'BACKEND_CAPABILITY_UNCLASSIFIED_FOR_MOBILE',
       disposition:'NOT_DECIDED',
       sourceEvidence:'NOT_VERIFIED',uiEvidence:'NOT_VERIFIED',
       wizardEvidence:'NOT_VERIFIED',externalBackendEvidence:'NOT_APPLICABLE'});
   }
 }
 return {path,capabilities:names.length,routeCount:routes.length,
   mappedCandidateRoutes:routes.filter(r=>r.classification.startsWith('FEATURE_')).length,
   unclassifiedForMobile:routes.filter(r=>r.classification.startsWith('BACKEND_')).length,
   newCapabilities,missingCapabilities,invalid,
   // No operation gets DONE from a textual source scan.
   operationDecisionsStillRequired:routes.length,routes};
}


/**
 * تحقق قرارات Fable التي تتجاوز الـFeature: Git blob hash يلتقط تعديل
 * السياسة أو العينة المرجعية حتى لو لم تتغير API Route في Manifest.
 * لا يعني تطابق المصدر أن Runtime مشروع العميل مُثبت أو اختُبر.
 */
export function auditBackendWideDecisionSources(backendRoot,rows){
 const root=resolve(backendRoot);
 const sub=existsSync(join(root,'Fable-Backend-RC66'))
   ?join(root,'Fable-Backend-RC66'):root;
 const changed=[],missing=[],invalid=[];
 const checked=new Set();
 for(const row of rows){
   const path=row.backendSource,expected=row.sourceGitBlobSha;
   if(typeof path!=='string'||! /^(?:lib|src|docs|blueprints)\/[A-Za-z0-9._/-]+$/.test(path)||
      path.includes('..')||typeof expected!=='string'||
      !/^[a-f0-9]{40}$/.test(expected)){invalid.push(row.id);continue;}
   if(checked.has(path))continue;
   checked.add(path);
   const full=join(sub,path);
   if(!existsSync(full)){missing.push(path);continue;}
   const bytes=readFileSync(full);
   const actual=createHash('sha1')
     .update('blob '+bytes.length+'\x00').update(bytes).digest('hex');
   if(actual!==expected)changed.push({path,expected,actual});
 }
 return {trackedSources:checked.size,changed,missing,invalid};
}

export function checkParity(root,{backendRoot=null}={}){
 const project=resolve(root);
 const master=JSON.parse(readFileSync(resolve(project,MASTER),'utf8'));
 const result=validateMaster(project,master);
 const report={schemaVersion:1,source:'fable-parity-master-review',
   evaluatedAt:new Date().toISOString(),flutterFeatureCount:result.features.length,
   sourceStatusCounts:Object.fromEntries([...new Set(result.features.map(f=>f.sourceStatus))].map(status=>
     [status,result.features.filter(f=>f.sourceStatus===status).length])),
   featureIds:result.features.map(f=>f.id),
   realProjectContractVerified:false,liveE2EVerified:false,completeFeatures:0,
   declaredMappedBackendCapabilities:result.declaredCapabilities,
   backendManifestAudit:backendRoot?
     auditBackendManifests(backendRoot,result.declaredCapabilities):null,
   errors:result.errors};
 if(backendRoot){
   const policy=JSON.parse(readFileSync(resolve(project,
     'docs/integrations/FABLE-BACKEND-WIDE-DECISIONS-RC81.json'),'utf8'));
   report.backendWideSourceAudit=auditBackendWideDecisionSources(
     backendRoot,policy.decisions);
   for(const entry of report.backendWideSourceAudit.changed)
     report.errors.push('BACKEND_WIDE_POLICY_SOURCE_CHANGED_REQUIRES_REVIEW: '+entry.path);
   for(const entry of report.backendWideSourceAudit.missing)
     report.errors.push('BACKEND_WIDE_POLICY_SOURCE_MISSING: '+entry);
   for(const entry of report.backendWideSourceAudit.invalid)
     report.errors.push('BACKEND_WIDE_POLICY_SOURCE_INVALID: '+entry);
 }
 if(report.backendManifestAudit){
   const audit=report.backendManifestAudit;
   report.errors.push(...audit.invalid,...audit.newCapabilities.map(x=>'NEW_BACKEND_CAPABILITY: '+x),
     ...audit.missingCapabilities.map(x=>'BACKEND_CAPABILITY_REMOVED: '+x));
   // المقارنة بأسماء عمليات Auth الأربعين، وليس فقط رقم 40.
   // أي عملية مضافة أو محذوفة من Blueprint تفتح Gap ولا تمر بصمت.
   const expected=JSON.parse(readFileSync(resolve(project,AUTH_INVENTORY),'utf8'));
   const recorded=new Set(expected.operations.map(op=>op.id));
   const actual=new Set(audit.routes.filter(op=>op.capability==='auth').map(op=>op.id));
   report.authOperationDrift={
     newAuthOperations:[...actual].filter(id=>!recorded.has(id)),
     removedAuthOperations:[...recorded].filter(id=>!actual.has(id)),
   };
   for(const id of report.authOperationDrift.newAuthOperations)
     report.errors.push('AUTH_ROUTE_ADDED_REQUIRES_REVIEW: '+id);
   for(const id of report.authOperationDrift.removedAuthOperations)
     report.errors.push('AUTH_ROUTE_REMOVED_REQUIRES_REVIEW: '+id);
 }
 return report;
}

function parse(args){
 const opts={root:process.cwd(),backendRoot:null,output:null,requireExhaustive:false};
 for(let i=0;i<args.length;i++){
   if(args[i]==='--root')opts.root=args[++i];
   else if(args[i]==='--backend-root')opts.backendRoot=args[++i];
   else if(args[i]==='--output')opts.output=args[++i];
   else if(args[i]==='--require-exhaustive')opts.requireExhaustive=true;
   else throw Error('Unknown argument: '+args[i]);
 }
 return opts;
}
if(process.argv[1]&&import.meta.url===pathToFileURL(resolve(process.argv[1])).href){
 try{
   const opts=parse(process.argv.slice(2));
   const report=checkParity(opts.root,{backendRoot:opts.backendRoot});
   if(opts.output)writeFileSync(resolve(opts.output),JSON.stringify(report,null,2)+'\n');
   console.log(JSON.stringify({...report,
     backendManifestAudit:report.backendManifestAudit==null?null:{
       ...report.backendManifestAudit,routes:undefined}},null,2));
   if(report.errors.length||
      (opts.requireExhaustive && (!report.backendManifestAudit ||
        report.backendManifestAudit.operationDecisionsStillRequired>0)))
     process.exitCode=1;
 }catch(e){console.error(String(e?.stack??e));process.exitCode=1;}
}

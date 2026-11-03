#!/usr/bin/env node
/**
 * RC90 — Fail-closed, selected-feature Backend integration audit.
 *
 * No UI/Repository name proves a working Backend. A user-facing feature may
 * be MISSING, PARTIAL, SOURCE_MAPPED_E2E_PENDING or CLIENT_ONLY.
 * This tool reports the exact *known* deficit, and explicitly distinguishes
 * unknown contract requirements from verified missing API operations.
 */
import {existsSync,readFileSync,writeFileSync,mkdirSync} from 'node:fs';
import {resolve,join,dirname,relative,isAbsolute} from 'node:path';
import {createHash} from 'node:crypto';
import {pathToFileURL,fileURLToPath} from 'node:url';
import {FEATURE_IDS,FEATURE_OWNERSHIP} from './frontend-feature-ownership.mjs';
import {auditBackendFeatureParity} from './audit-backend-feature-parity.mjs';

const MASTER='docs/integrations/FABLE-FLUTTER-PARITY-MASTER.json';
const CONFIG='assets/config/backend.json';
const CONTRACT='assets/contracts/external-operations.json';
const BINDINGS='assets/config/feature-operations.json';
const REQUIREMENTS='.fable/feature-integration-requirements.json';
const ACTION_METHODS=Object.freeze({
  read:['GET','HEAD'],list:['GET'],create:['POST'],update:['PUT','PATCH'],
  remove:['DELETE'],markRead:['POST','PUT','PATCH'],
});
const BACKEND_REQUIRED=['auth','profile','notifications','media','localization',
  'support','social','biometrics','realtime','messaging','location','payments',
  'analytics','content','access_control'];
const evidenceKeys=['requestDto','responseDto','errors','permissions',
  'frontendFile','testFile'];
const read=(p)=>JSON.parse(readFileSync(p,'utf8'));
const present=(v)=>typeof v==='string'&&v.trim().length>0;
const safePath=(root,name)=>{
  if(!present(name)||name.startsWith('/')||name.includes('\\')||
    name.split('/').some(s=>s==='..'||s==='.')||
    !/^[a-zA-Z0-9/_\-.]+$/.test(name))return null;
  const full=resolve(root,name);
  const relativePath=relative(root,full);
  if(!relativePath||relativePath==='..'||relativePath.startsWith('..\\')||
    relativePath.startsWith('../')||isAbsolute(relativePath))return null;
  return full;
};
function checkedFile(root,name){
  const full=safePath(root,name);
  return full!==null&&existsSync(full);
}
const gap=(code,detail,action,operationId=null)=>({
  code,detail,action,...(operationId?{operationId}:{})
});
function selectedFeatures(root) {
  const selectionPath=join(root,'.fable/mobile-features.json');
  const all=[];
  const seen=new Set();
  let explicit=existsSync(selectionPath);
  if(explicit){
    const j=read(selectionPath);
    if(!Array.isArray(j.features))throw Error('Invalid selected feature manifest');
    for(const id of j.features){
      if(!present(id))throw Error('Malformed selected feature id');
      if(!seen.has(id)){seen.add(id);all.push(id);}
    }
  }
  const projectFeatures=join(root,'.fable/project-features.json');
  if(existsSync(projectFeatures)){
    const custom=read(projectFeatures);
    if(!Array.isArray(custom.features))throw Error('Invalid custom project feature manifest');
    for(const feature of custom.features){
      const id=typeof feature==='string'?feature:feature?.id;
      if(!present(id))throw Error('Custom project feature is missing its identifier');
      if(!seen.has(id)){seen.add(id);all.push(id);explicit=true;}
    }
  }
  const owned=join(root,'.fable/frontend-owned-decisions.json');
  if(existsSync(owned)){
    const j=read(owned);
    if(j?.kind!=='fable.flutter-owned-decisions'||!j.choices||
      typeof j.choices!=='object')throw Error('Malformed Flutter local feature decisions');
    for(const [id,x] of Object.entries(j.choices)){
      if(x?.enabled===false){seen.delete(id);}
      else if(x?.enabled===true&&!seen.has(id)){seen.add(id);all.push(id);explicit=true;}
    }
  }
  return {ids:all.filter(id=>seen.has(id)),explicit};
}
function backendConfig(root){
  const path=join(root,CONFIG);
  if(!existsSync(path))return {kind:'unselected',ready:false,adapter:null};
  const cfg=read(path),backend=cfg?.backend;
  if(cfg.kind!=='fable.mobile-backend-configuration'||
    !['fable','other'].includes(backend?.kind) ||
    !['ready','pending'].includes(backend?.status) ||
    typeof cfg.contractImported!=='boolean')
    throw Error('Invalid Backend configuration; Wizard must select it first');
  return {kind:backend.kind,adapter:backend.adapter,
    ready:backend.status==='ready'&&cfg.contractImported};
}
function requirements(root,ids){
  const path=join(root,REQUIREMENTS);
  if(!existsSync(path))return {features:{},provided:false};
  const j=read(path);
  if(j.schemaVersion!==1||j.kind!=='fable.feature-integration-requirements'||
    !j.features||typeof j.features!=='object'||Array.isArray(j.features))
    throw Error('Malformed feature integration requirements manifest');
  if(Object.keys(j.features).some(id=>!ids.includes(id)))
    throw Error('Requirements mention a feature that was not selected');
  return {features:j.features,provided:true};
}
function externalEvidence(root,backend){
  const missing=[];
  if(!backend.ready)missing.push(gap('BACKEND_NOT_READY',
    'Backend الآخر ما زال Pending أو لم يُثبت استيراد العقد',
    'أكمل استيراد OpenAPI/Custom Catalog بمصدر موثق'));
  if(!existsSync(join(root,CONTRACT))){
    missing.push(gap('EXTERNAL_API_CATALOG_MISSING',CONTRACT,
      'استورد عقد العمليات من Backend الآخر دون استنتاج مسارات Fable'));
    return {operations:new Map(),bindings:{},missing,verified:false};
  }
  const j=read(join(root,CONTRACT));
  if(j.schemaVersion!==1||j.kind!=='fable.external-operation-catalog'||
     j.adapter!==backend.adapter||!Array.isArray(j.operations)||
     !/^[a-f0-9]{64}$/.test(j.sourceHash||'')||
     !/^[a-f0-9]{64}$/.test(j.operationsHash||'')||
     createHash('sha256').update(JSON.stringify(j.operations)).digest('hex')!==j.operationsHash)
    throw Error('External catalog is malformed/stale: reimport the actual Backend contract');
  const operations=new Map();
  for(const op of j.operations){
    if(!present(op.operationId)||!present(op.method)||!present(op.path)||
       !op.path.startsWith('/')||operations.has(op.operationId))
      throw Error('Malformed/duplicated external operation');
    operations.set(op.operationId,op);
  }
  if(!existsSync(join(root,BINDINGS))){
    missing.push(gap('EXTERNAL_FEATURE_BINDINGS_MISSING',BINDINGS,
      'اربط كل دور في الخدمة بـoperationId من العقد عبر feature-operations.json'));
    return {operations,bindings:{},missing,verified:false};
  }
  const b=read(join(root,BINDINGS));
  if(b.schemaVersion!==1||b.kind!=='fable.feature-operation-bindings'||
     b.adapter!==j.adapter||b.sourceHash!==j.sourceHash||
     b.operationsHash!==j.operationsHash||
     !b.bindings||typeof b.bindings!=='object')
    throw Error('External feature bindings do not match the active Backend catalog');
  return {operations,bindings:b.bindings,missing,verified:backend.ready};
}
/// Wizard guard for the cross-feature Managed Accounts → Access Control binding.
/// A matching screen or imported operation is not enough: all runtime layers
/// must share one backend identity namespace and invalidate access snapshots.
export function managedAccessContextBindingGaps(root) {
  root=resolve(root);
  const source=(name)=>checkedFile(root,name)?readFileSync(safePath(root,name),'utf8'):'';
  const app=source('lib/src/app.dart');
  const session=source('packages/features/fable_access_control/lib/src/access_session.dart');
  const bootstrap=source('packages/features/fable_access_control/lib/src/access_bootstrap.dart');
  const store=source('packages/fable_core/lib/src/fable_managed_entity_scope.dart');
  const auth=source('packages/fable_core/lib/src/fable_auth_gateway.dart');
  const accessRepo=source('packages/features/fable_access_control/lib/src/access_repository.dart');
  const managedRepo=source('packages/features/fable_profile/lib/src/managed_accounts_repository.dart');
  const managedPage=source('packages/features/fable_profile/lib/src/managed_accounts_page.dart');
  const managedMembers=source('packages/features/fable_profile/lib/src/managed_members_page.dart');
  const checks=[
    ['APP_STORE_NAMESPACE',app.includes('FableManagedEntityStore(session:FableSecureSession(')],
    ['APP_STORE_BACKEND_PIN',app.includes('FableAuthGateway.managedEntityBackendIdentityFor(baseUri,contract)')],
    ['APP_STORE_SCOPE',app.includes('managedEntityStore:managedStore')&&app.includes('FableManagedEntityScope(store:managedStore')],
    ['BOOTSTRAP_STORE_BINDING',bootstrap.includes('managedEntityStore: widget.managedEntityStore')&&bootstrap.includes('managedStore.isBoundToBackend(auth.managedEntityBackendIdentity)')],
    ['ACCESS_SESSION_BINDING',bootstrap.includes('access.bindToCredentials(credentials,')&&bootstrap.includes('managedEntityStore: widget.managedEntityStore')],
    ['ACCESS_SESSION_INVALIDATION',session.includes('managedEntityStore?.addListener(_onManagedSelectionChanged)')&&session.includes('store.selectionRevision')&&session.includes('value = null;')],
    ['SHARED_IDENTITY_NAMESPACE',store.includes('_session.sharesIdentityNamespaceWith(credentials)')&&auth.includes('sessionNamespaceFor')],
    ['BACKEND_IDENTITY_PIN',store.includes('isBoundToBackend(String identity)')&&auth.includes('managedEntityBackendIdentityFor')],
    ['SCOPED_REPOSITORY_GUARD',managedRepo.includes('store.isBoundToBackend(gateway.managedEntityBackendIdentity)')],
    ['SCOPED_DENIAL_CLEAR',managedRepo.includes('error.status==403')&&managedRepo.includes('store.clear()')],
    ['MANAGED_ROLE_RESUME_REFRESH',managedPage.includes('WidgetsBindingObserver')&&managedPage.includes('AppLifecycleState.resumed')&&managedPage.includes('unawaited(_reload())')],
    ['MANAGED_PARENT_SCOPE_GUARD',managedPage.includes('FableManagedEntityScope.maybeOf(context)')&&managedPage.includes('identical(store.selected,choice)')&&managedPage.includes('_onManagedStoreChanged')],
    ['MANAGED_PARENT_INVITE_GUARD',managedPage.includes('store.selectionRevision==storeRevision')&&managedPage.includes('!sameSelection()')],
    ['OWNER_LIFECYCLE_CONTEXT_GUARD',managedPage.includes('_pendingLifecycleRevision')&&managedPage.includes('_sameLifecycleContext(store,contextRevision)')&&managedPage.includes('contextStillValid:valid')],
    ['OWNER_LIFECYCLE_POST_OTP_GUARD',managedRepo.includes('contextStillValid')&&managedRepo.includes("if(!validContext())throw StateError('Managed lifecycle context changed after OTP verification')")],
    ['MEMBER_ROUTE_STORE',managedPage.includes('managedStore:FableManagedEntityScope.maybeOf(context)')],
    ['MEMBER_PAGE_SELECTION_REVISION',managedMembers.includes('_openedSelectionRevision==store.selectionRevision')&&managedMembers.includes('identical(store.selected,widget.selection)')],
    ['MEMBER_PAGE_CONFIRMATION_GUARD',managedMembers.includes('!_at(generation)||!_owner')&&managedMembers.includes('!_at(generation)||!_invitationAdmin')],
    ['MEMBER_PAGE_RESUME_ROLE_REVALIDATION',managedMembers.includes('AppLifecycleState.resumed')&&managedMembers.includes('widget.repo.listMine()')&&managedMembers.includes('widget.managedStore?.clear()')],
    ['GLOBAL_PERMISSION_BOUNDARY',accessRepo.includes('Deliberately user-global')&&accessRepo.includes('gateway.execute(operationId)')],
  ];
  return checks.filter(([,ok])=>!ok).map(([code])=>code);
}

function classify({selected,problems,sourceMapped,needsBackend}){
  if(!selected)return 'NOT_SELECTED';
  if(!needsBackend)return problems.length?'CLIENT_ONLY_REVIEW':'CLIENT_ONLY_NO_BACKEND_REQUIRED';
  if(problems.length===0)return 'SOURCE_MAPPED_E2E_PENDING';
  if(sourceMapped>0)return 'PARTIAL';
  return 'MISSING';
}
function auditOne(root,feature,backend,master,external,explicit,selectedIds=[]){
  const ownership=FEATURE_OWNERSHIP[feature]??'custom';
  const req=explicit??null;
  // Backend-owned features cannot be silently recast as client-only just
  // by writing needsBackend:false in a local config file.
  const requires=ownership==='server'||req?.needsBackend===true||
    (req?.needsBackend===false?false:BACKEND_REQUIRED.includes(feature)||
      (ownership==='custom'&&req?.needsBackend!==false));
  const problems=[],details=[];
  const add=(code,detail,action,operationId)=>{
    if(!problems.some(p=>p.code===code&&p.detail===detail)){
      problems.push(gap(code,detail,action,operationId));
    }
  };
  const localPkg=FEATURE_IDS.includes(feature)
    ?'packages/features/fable_'+feature+'/pubspec.yaml':null;
  if(localPkg&&!checkedFile(root,localPkg))
    add('FRONTEND_PACKAGE_MISSING',localPkg,
      'أضف حزمة Flutter أو احذف اختيار الخدمة بعد موافقة صريحة');
  const operations=Array.isArray(req?.operations)?req.operations:[];
  if(req&&req.needsBackend!==false&&
     (!Array.isArray(req.operations)||req.operations.length===0)){
    add('REQUIRED_OPERATIONS_UNSPECIFIED',
      'لم تُحدد عمليات الخدمة المطلوبة لهذا المشروع',
      'حدد لكل وظيفة مطلوبة method/path/operationId وDTO والاختبارات في '+REQUIREMENTS);
  }
  if(requires&&!req){
    add('PER_FEATURE_REQUIREMENTS_NOT_DECLARED',
      'لا توجد قائمة عمليات وأدوار معتمدة لهذه الخدمة في هذا المشروع',
      'أضف '+REQUIREMENTS+' وحدّد العمليات المطلوبة؛ لا يمكن إثبات الاكتمال بدون نطاق واضح');
  }
  if(req&&typeof req.needsBackend!=='boolean')
    add('BACKEND_DEPENDENCY_NOT_DECIDED','لم يُصرّح هل تحتاج الخدمة Backend',
      'حدد needsBackend=true أو false مع تفسير العقد');
  if(requires&&backend.kind==='unselected')
    add('BACKEND_SELECTION_MISSING','لم يُختر Backend في Wizard',
      'اختر Fable أو Other Backend أولاً');
  let mapped=0;
  const fableOps=external?.fable?.featureMatrix?.find(x=>x.id===feature);
  if(feature==='access_control' && selectedIds.includes('profile') &&
     backend.kind==='fable' &&
     external?.fable?.operations?.some(op=>
       /^managed-(?:entities|accounts)\./.test(op.id))) {
    const gaps=managedAccessContextBindingGaps(root);
    if(gaps.length) add('MANAGED_ACCESS_CONTEXT_NOT_BOUND',
      'ربط حسابات Fable الفرعية مع Access Control غير مكتمل: '+gaps.join(', '),
      'وحّد namespace الخاص بـFableSecureSession، ومرّر ManagedEntityStore إلى AccessBootstrap، وأعد التحقق من Snapshot عند كل تبديل دون تحويل أدوار الكيان إلى صلاحيات عامة.');
  }
  if(requires&&backend.kind==='fable'){
    if(!backend.ready)
      add('FABLE_BACKEND_NOT_READY','عقد Fable غير مفعّل لهذا المشروع',
        'استورد handoff متحققاً من مشروع Backend الحقيقي');
    if(!external?.fable){
      add('FABLE_CONTRACT_AUDIT_UNAVAILABLE',
        'تعذر تدقيق عمليات Fable من العقد المصدر',
        'أعد استيراد عقد المشروع وافحص مصدره وبصمته');
    }else{
      const rows=external.fable.operations.filter(x=>
        x.status!=='NOT_FOR_FLUTTER'&&
        (external.fable.featureMatrix.find(f=>f.id===feature)?.operationIds||[])
          .includes(x.id));
      mapped=rows.filter(x=>x.status==='SOURCE_WIRED_NOT_LIVE_TESTED').length;
      if(rows.length===0)
        add('FABLE_FEATURE_OPERATIONS_ABSENT',
          'لا توجد عمليات مستوردة مصنفة لهذه الخدمة في عقد المشروع الحالي',
          'تحقق من تثبيت Capability وتصدير operations؛ لا تخترع endpoint');
      for(const op of rows.filter(x=>x.status==='NOT_MAPPED'||x.status==='MAPPING_STALE')){
        add('FABLE_OPERATION_NOT_WIRED',op.id+' '+op.method+' '+op.path,
          op.nextAction,op.id);
      }
      if(!external.fable.projectBound)
        add('PROJECT_CONTRACT_UNPINNED',
          'لم يُثبت استيراد العقد من مشروع Backend حقيقي مستقل الهوية والبصمة',
          'استورد العقد الحقيقي مع expected-project-id وexpected-contract-hash');
      if(fableOps?.status==='GATEWAY_ONLY_NO_VERIFIED_UI')
        add('FRONTEND_FLOW_NOT_VERIFIED',
          'Gateway موجود، لكن تدفق الشاشة لم يُثبت',
          'اربط الشاشة/BLoC بالأخطاء والصلاحيات واختبرها');
    }
  }
  if(requires&&backend.kind==='other'){
    for(const p of external.missing)add(p.code,p.detail,p.action);
    const bindings=external.bindings[feature]??{};
    const ids=new Set(Object.values(bindings));
    mapped=Object.values(bindings).filter(id=>external.operations.has(id)).length;
    if(!Object.keys(bindings).length)
      add('FEATURE_BINDINGS_EMPTY','لا يوجد دور/عملية مربوط بالخدمة: '+feature,
        'أضف bindings.'+feature+' في '+BINDINGS+' وراجع role وoperationId');
    for(const [role,id] of Object.entries(bindings)){
      const op=external.operations.get(id);
      if(!op)add('BOUND_OPERATION_NOT_FOUND',role+' → '+id,
        'العملية غير موجودة في كتالوج Backend المستورد؛ صحح الربط',id);
      else if(ACTION_METHODS[role]&&!ACTION_METHODS[role].includes(op.method))
        add('BOUND_METHOD_MISMATCH',role+' → '+id+' '+op.method,
          'تحقق من method المطلوب لهذا الدور',id);
    }
    // Keep the existing catalog's typed and per-feature semantics authoritative.
    if(!external.verified)
      add('EXTERNAL_CONTRACT_NOT_VERIFIED',
        'لم يثبت توافق الكتالوج مع Backend جاهز',
        'راجع sourceHash وoperationsHash وحالة backend.json');
  }
  for(const op of operations){
    if(!present(op?.operationId)||!present(op?.method)||!present(op?.path)||
       !op.path.startsWith('/')){
      add('REQUIRED_OPERATION_ID_METHOD_PATH',
        'عملية مطلوبة ليس لها operationId/method/path صريح',
        'حدّد جميع الحقول الأساسية للعملية في ملف المتطلبات');
      continue;
    }
    const id=op.operationId,method=op.method.toUpperCase();
    let declared=null;
    if(backend.kind==='other')declared=external.operations.get(id);
    if(backend.kind==='fable')declared=external?.fable?.operations.find(x=>x.id===id);
    if(requires&&!declared)
      add('REQUIRED_OPERATION_MISSING',id+' '+method+' '+op.path,
        'أضف هذه العملية إلى عقد Backend الصحيح ثم استورد العقد',id);
    else if(declared&&(declared.method!==method||declared.path!==op.path))
      add('REQUIRED_OPERATION_MISMATCH',id+': expected '+method+' '+op.path+
        ', actual '+declared.method+' '+declared.path,
        'صحح العقد أو الاختيار بعد مراجعة المبرمج',id);
    if(backend.kind==='other'&&declared &&
       !Object.values(external.bindings[feature]??{}).includes(id))
      add('REQUIRED_OPERATION_UNBOUND',id+' '+method+' '+op.path,
        'اربط العملية بدور Flutter لهذه الخدمة',id);
    if(!evidenceKeys.every(key=>present(op[key]))){
      for(const key of evidenceKeys.filter(key=>!present(op[key]))){
        add('OPERATION_EVIDENCE_MISSING',id+' → '+key,
          'قدّم دليلاً موثقاً للحقل '+key+' (لا يكفي اسم operationId)',id);
      }
    }
    for(const key of ['frontendFile','testFile']){
      if(present(op[key])&&!checkedFile(root,op[key]))
        add('EVIDENCE_FILE_NOT_FOUND',id+' → '+key+'='+op[key],
          'أنشئ الملف واختبره أو صحّح المسار',id);
    }
  }
  if(requires){
    const missingGeneric=(backend.kind==='other'?master?.otherBackendContract:master?.gaps)??[];
    for(const text of missingGeneric.slice(0,8))details.push(text);
    // Never report "complete" from source metadata alone.
    // A manifest boolean cannot prove production correctness or runner results.
    // Require independently checked device/server evidence in a later gate.
    add('LIVE_E2E_NOT_VERIFIED','لا يوجد إثبات E2E حي مستقل لهذه الخدمة',
      'اختبر API/DB وAndroid/iOS والرفض والتعارضات وسجّل الإثبات');
  }else if(ownership==='client'){
    details.push('قرار Flutter محلي؛ Backend ليس إلزامياً ما لم تطلب هذه الميزة API في المشروع');
  }
  return {id:feature,ownership,needsBackend:requires,backendKind:backend.kind,
    state:classify({selected:true,problems,sourceMapped:mapped,needsBackend:requires}),
    sourceMappedOperations:mapped,requiredOperationCount:operations.length,
    missing:problems,backendRequirements:details,
    liveE2EVerified:false};
}
export function auditSelectedFeatureIntegration(root,{overrideSelections=null}={}){
  root=resolve(root);
  const selected=overrideSelections??selectedFeatures(root);
  if(!Array.isArray(selected.ids)||selected.ids.some(id=>!present(id)))
    throw Error('Invalid selected feature list');
  const backend=backendConfig(root);
  // Generated projects may contain the Wizard and feature packages without
  // duplicating its reference checklists. Use the installed Fable tool's master.
  const projectMaster=join(root,MASTER);
  const bundledMaster=resolve(dirname(fileURLToPath(import.meta.url)),'..',MASTER);
  const master=read(existsSync(projectMaster)?projectMaster:bundledMaster);
  if(!Array.isArray(master.features))throw Error('Missing feature parity master');
  const defs=new Map(master.features.map(x=>[x.id,x]));
  const req=requirements(root,selected.ids);
  let fable=null,external=null;
  if(backend.kind==='fable'&&backend.ready){
    try{fable=auditBackendFeatureParity(root);}
    catch(error){
      external={fable:null,reason:error.message};
    }
  }
  if(backend.kind==='other'){
    external=externalEvidence(root,backend);
  }
  const evidence=backend.kind==='fable'?{fable,reason:external?.reason}:
    backend.kind==='other'?external:{};
  const features=selected.ids.map(id=>auditOne(root,id,backend,defs.get(id),
    evidence,req.features[id],selected.ids));
  const counts={
    MISSING:features.filter(x=>x.state==='MISSING').length,
    PARTIAL:features.filter(x=>x.state==='PARTIAL').length,
    SOURCE_MAPPED_E2E_PENDING:features.filter(x=>x.state==='SOURCE_MAPPED_E2E_PENDING').length,
    CLIENT_ONLY_NO_BACKEND_REQUIRED:features.filter(x=>x.state==='CLIENT_ONLY_NO_BACKEND_REQUIRED').length,
    CLIENT_ONLY_REVIEW:features.filter(x=>x.state==='CLIENT_ONLY_REVIEW').length,
  };
  return {schemaVersion:1,kind:'fable.selected-feature-integration-gaps',
    selectionExplicit:selected.explicit===true,selectedFeatureCount:features.length,
    backendKind:backend.kind,backendReady:backend.ready,
    requirementsManifestPresent:req.provided,
    overallReadyForLiveUse:false,counts,features};
}
export function formatIntegrationGapReport(report){
  const lines=[
    '════════ Fable: تدقيق ربط الميزات المختارة بالـBackend ════════',
    'Backend: '+report.backendKind+' | Selected: '+report.selectedFeatureCount+
      ' | MISSING: '+report.counts.MISSING+' | PARTIAL: '+report.counts.PARTIAL,
  ];
  if(!report.selectionExplicit)lines.push('⚠ لم يتم تسجيل اختيار خدمات صريح؛ راجع إعداد المشروع');
  if(!report.requirementsManifestPresent)
    lines.push('⚠ لا يوجد ملف متطلبات per-feature: '+REQUIREMENTS+
      ' (سيفصل المدقق بين النقص المؤكد والعقود غير المحسومة)');
  for(const feature of report.features){
    const ico=feature.state==='MISSING'?'✖':feature.state==='PARTIAL'?'⚠':'ℹ';
    lines.push('\n'+ico+' ['+feature.state+'] '+feature.id+
      ' | backend='+feature.needsBackend+' | mapped='+feature.sourceMappedOperations);
    for(const entry of feature.missing){
      lines.push('    • '+entry.code+': '+entry.detail);
      lines.push('      ↳ المطلوب: '+entry.action);
    }
    if(feature.backendRequirements.length){
      lines.push('    متطلبات لم يُثبت اكتمالها بعد:');
      for(const description of feature.backendRequirements)
        lines.push('    – '+description);
    }
  }
  lines.push('\nنتيجة الفحص: تنبيه فقط؛ --strict يُرجع Exit 2 عند أي نقص/انتظار E2E للخدمات المعتمدة على Backend.');
  return lines.join('\n');
}
function parseArgs(args){
  const out={};
  for(let i=0;i<args.length;i++){
    if(args[i]==='--strict'||args[i]==='--json'){out[args[i].slice(2)]=true;continue;}
    if(!['--root','--out'].includes(args[i])||!args[i+1])
      throw Error('Use --root PATH [--out PATH] [--json] [--strict]');
    out[args[i].slice(2)]=args[++i];
  }
  return out;
}
if(process.argv[1]&&import.meta.url===pathToFileURL(resolve(process.argv[1])).href){
  try{
    const opt=parseArgs(process.argv.slice(2));
    const root=resolve(opt.root??process.cwd());
    const report=auditSelectedFeatureIntegration(root);
    const result=opt.json?JSON.stringify(report,null,2):formatIntegrationGapReport(report);
    process.stdout.write(result+'\n');
    if(opt.out){
      const target=resolve(root,opt.out);
      if(!target.startsWith(root+'/'))throw Error('Report path must stay inside project');
      mkdirSync(dirname(target),{recursive:true});
      writeFileSync(target,JSON.stringify(report,null,2)+'\n');
    }
    if(opt.strict&&(!report.selectionExplicit||report.features.some(x=>x.missing.length>0)))
      process.exitCode=2;
  }catch(error){process.stderr.write('Integration audit error: '+error.message+'\n');process.exitCode=1;}
}

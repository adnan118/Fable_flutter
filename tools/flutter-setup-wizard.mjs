#!/usr/bin/env node
// Flutter setup wizard: import a Backend-generated handoff, or manually draft
// UI decisions for a non-Fable Backend. Never invent auth/security policy.
import {mkdtempSync,mkdirSync,readFileSync,writeFileSync,copyFileSync,rmSync,existsSync} from 'node:fs';
import {resolve,join,dirname} from 'node:path';
import {tmpdir} from 'node:os';
import {createInterface} from 'node:readline/promises';
import {pathToFileURL} from 'node:url';
import {verifyFableContract} from './verify-fable-contract.mjs';
import {validateSessionPolicyForWizard} from './read-session-policy.mjs';

const CONTRACT_FILES=['contract.json','flutter-handoff.json','openapi.json','mobile-core-operations.json'];
const OUTPUT_PATH='assets/config/frontend-setup.json';
const PROJECT_PATH='.fable/frontend-setup.json';
const asJson=file=>JSON.parse(readFileSync(file,'utf8'));
function outputFile(root,path,value){
  const file=resolve(root,path);
  mkdirSync(dirname(file),{recursive:true});
  writeFileSync(file,JSON.stringify(value,null,2)+'\n','utf8');
}
function explicitKeys(options){
  const out={};
  for(let i=0;i<options.length;i++){
    const current=options[i];
    if(!current.startsWith('--'))throw Error('Unexpected argument: '+current);
    const key=current.slice(2);
    if(['apply','interactive','prune','yes'].includes(key)){out[key]=true;continue;}
    if(!options[i+1]||options[i+1].startsWith('--'))throw Error('Missing value for --'+key);
    out[key]=options[++i];
  }
  return out;
}
function sourceFiles(source){
  const candidate=resolve(source);
  const dir=existsSync(join(candidate,'contract.json'))?candidate:resolve(candidate,'assets/contracts');
  for(const file of CONTRACT_FILES)if(!existsSync(join(dir,file)))throw Error('Missing backend export: '+file);
  return dir;
}
function assertMatchingSetup(contract,handoff){
  const decision=contract.core?.frontendSetup;
  const mirror=handoff.frontendSetup;
  if(!decision||!mirror||JSON.stringify(decision)!==JSON.stringify(mirror) ||
    decision.schemaVersion!==1 ||decision.kind!=='fable.frontend-setup-decisions'||
    decision.projectId!==contract.project?.id||
    !Array.isArray(decision.steps)||!decision.decisions||
    decision.decisions.authentication?.sessions?.runtimeEndpoint!=='/auth/session-policy') {
    throw Error('Missing, invalid or conflicting backend frontend wizard decisions. Re-export from Fable Backend.');
  }
  validateSessionPolicyForWizard(decision.decisions.authentication.sessions);
  if(JSON.stringify(decision).length>256000)throw Error('Frontend setup decisions exceed safe limit');
  return decision;
}

export function importBackendDecisions(source,{expectedProjectId=null,expectedContractHash=null}={}){
  const dir=sourceFiles(source);
  const stage=mkdtempSync(join(tmpdir(),'fable-flutter-setup-'));
  try{
    const target=resolve(stage,'assets/contracts');
    mkdirSync(target,{recursive:true});
    for(const file of CONTRACT_FILES)copyFileSync(join(dir,file),join(target,file));
    outputFile(stage,'assets/config/backend.json',{
      schemaVersion:1,kind:'fable.mobile-backend-configuration',
      backend:{kind:'fable',adapter:'fable-contract',status:'ready'},
      contractImported:true,
    });
    const hasPin=Boolean(expectedProjectId&&expectedContractHash);
    if(Boolean(expectedProjectId)!==Boolean(expectedContractHash))throw Error('Provide both independent --expected-project-id and --expected-contract-hash');
    const gate=verifyFableContract(stage,{
      mode:hasPin?'project':'source',
      expectedProjectId,expectedContractHash});
    if(!gate.ok)throw Error('Backend export verification failed: '+gate.failures.join(','));
    if(gate.fixture)throw Error('Fixture backend cannot configure a real Flutter project');
    const contract=asJson(join(dir,'contract.json'));
    const handoff=asJson(join(dir,'flutter-handoff.json'));
    const decisions=assertMatchingSetup(contract,handoff);
    const standalone=join(dir,'frontend-setup.json');
    if(existsSync(standalone)){
      const payload=asJson(standalone);
      if(payload.kind!=='fable.frontend-setup-handoff' || payload.schemaVersion!==1 ||
        payload.backendContractHash!==contract.contractHash ||
        payload.project?.id!==contract.project.id ||
        JSON.stringify(payload.setup)!==JSON.stringify(decisions)){
        throw Error('Standalone frontend-setup.json does not match signed backend export');
      }
    }
    return {
      schemaVersion:1,kind:'fable.flutter-frontend-setup',
      source:'backend-contract-export',projectId:contract.project.id,
      contractHash:contract.contractHash,projectBound:hasPin,
      mode:'import',backendAuthority:true,
      decisionSnapshot:decisions,
      frontendSelection:{
        mode:handoff.selection?.mode??'advisory',
        features:handoff.selection?.features??null,
      },
      uiPreferences:{navigation:'auto-by-roles',theme:'project-default'},
      implementation:{status:'requires-feature-binding-review',
        instructions:'Use installed operations, verified permissions and runtime contracts; do not create unrelated features.'},
    };
  }finally{rmSync(stage,{recursive:true,force:true});}
}
export function manualFrontendDecisions(input) {
  if(!input || typeof input!=='object'||Array.isArray(input) ||
    input.schemaVersion!==1 ||input.kind!=='manual.frontend-setup-decisions' ||
    typeof input.projectId!=='string'||!input.projectId.trim() ||
    !input.decisions||typeof input.decisions!=='object'||Array.isArray(input.decisions)||
    !Array.isArray(input.steps)||input.steps.length>50) {
    throw Error('Invalid manual frontend setup schema. Use manual.frontend-setup-decisions v1.');
  }
  // Manual cannot claim verified server enforcement or bypass backend Auth.
  return {
    schemaVersion:1,kind:'fable.flutter-frontend-setup',
    source:'developer-manual',projectId:input.projectId,
    contractHash:null,projectBound:false,mode:'manual',
    backendAuthority:false,
    decisionSnapshot:{schemaVersion:1,kind:input.kind,
      projectId:input.projectId,decisions:input.decisions,
      steps:input.steps},
    uiPreferences:{navigation:'manual-review',theme:'project-default'},
    implementation:{status:'unverified-backend-bindings',
      instructions:'Explicitly integrate and verify an external Backend. Manual declarations never authorize or enforce operations.'},
  };
}
// Display the complete public decision tree before any file is changed.
// Do not print the private source config, environment variables or secrets.
export function formatFrontendSetupReview(snapshot,{root=null}={}){
  if(snapshot?.kind!=='fable.flutter-frontend-setup')throw Error('Invalid setup for review');
  let old=null;
  if(root){
    const file=resolve(root,PROJECT_PATH);
    if(existsSync(file))old=asJson(file);
  }
  const current=old?.decisionSnapshot?.decisions??null;
  const proposed=snapshot.decisionSnapshot.decisions;
  const changes=[];
  function walk(a,b,key=''){
    if(JSON.stringify(a)===JSON.stringify(b))return;
    if(a && b && typeof a==='object' && typeof b==='object' &&
       !Array.isArray(a) && !Array.isArray(b)){
      for(const k of [...new Set([...Object.keys(a),...Object.keys(b)])].sort())
        walk(a[k],b[k],key?key+'.'+k:k);
    }else changes.push(key||'(root)');
  }
  if(current)walk(current,proposed);
  const features=proposed?.frontendFeatures;
  const lines=[
    '════════════════ FABLE BACKEND → FLUTTER ════════════════',
    'المشروع: '+snapshot.projectId,
    'بصمة العقد: '+(snapshot.contractHash??'manual / unverified'),
    'التحقق من هوية المشروع: '+(snapshot.projectBound?'مُطابق للقيم الموثوقة المُمررة':'المصدر فقط؛ لم تُقدَّم بصمة مستقلة'),
    'الوضع: '+snapshot.mode,
    '',
    '── قرارات الباك الكاملة (للقراءة فقط) ──',
    JSON.stringify(proposed,null,2),
    '',
    '── خطوات إعداد Flutter ──',
    ...snapshot.decisionSnapshot.steps.map(step=>'- '+step.id+': '+(step.frontendAction??step.id)),
    '',
  ];
  if(features){
    lines.push('── الميزات ──',
      'المتاحة: '+(features.enabled??[]).join(', '),
      'غير المفعلة: '+(features.disabled??[]).join(', '),
      'تحتاج مراجعة قرار Frontend محلي: '+(features.clientOnlyReview??[]).join(', '),'');
  }
  if(current)lines.push(
    '── الفروقات عن القرارات المستوردة سابقاً ──',
    ...(changes.length?changes.map(x=>'- '+x):['لا توجد فروقات في القرارات']),
    '');
  else lines.push('لا يوجد ملف قرارات مستورد سابقاً لهذا المشروع.','');
  lines.push(
    'لم يتم تغيير أي ملف بعد. استيراد القرارات لا يثبت نجاح الاتصال بالباك.',
    'لن تُحذف حزم Flutter الفعلية دون اختيار --prune وفحص عقد مشروع مثبت الهوية.',
    '═══════════════════════════════════════════════════════');
  return lines.join('\n');
}
export const isExplicitFrontendApproval=answer=>['اعتمد','APPROVE'].includes(String(answer??'').trim());
function requirePruningPin(snapshot,prune){
  if(prune && (!snapshot.backendAuthority||!snapshot.projectBound))
    throw Error('Pruning requires a pinned Fable Backend contract and explicit project identity');
}
async function applyReviewedSnapshot(root,snapshot,{source,prune=false}={}){
  requirePruningPin(snapshot,prune);
  const hasFeatures=snapshot.backendAuthority && snapshot.decisionSnapshot?.decisions?.frontendFeatures;
  const sync=hasFeatures?await import('./sync-project-features.mjs'):null;
  // Preflight feature inventory before copying any project assets.
  if(sync && snapshot.projectBound)sync.planFeatureSync(root,snapshot);
  const result=saveFrontendSetup(root,snapshot,{apply:true,sourceDir:source??null});
  if(sync){
    result.featureSync=sync.syncProjectFeatures(root,snapshot,{apply:snapshot.projectBound,prune});
  }
  return result;
}
// The confirmation callback is intentionally injectable to test refusals.
export async function reviewedBackendImport({
  root=process.cwd(),source,expectedProjectId=null,expectedContractHash=null,
  prune=false,ask,show=console.log,
}={}){
  if(typeof ask!=='function')throw Error('An interactive confirmation prompt is required');
  const project=resolve(root);
  const snapshot=importBackendDecisions(source??project,{expectedProjectId,expectedContractHash});
  requirePruningPin(snapshot,prune);
  show(formatFrontendSetupReview(snapshot,{root:project}));
  const answer=await ask('بعد مراجعة جميع القرارات، اكتب «اعتمد» أو APPROVE لتطبيقها (أي إجابة أخرى تلغي): ');
  if(!isExplicitFrontendApproval(answer)){
    show('تم إلغاء الاستيراد. لم يتغير أي ملف في مشروع Flutter.');
    return {applied:false,cancelled:true,projectId:snapshot.projectId};
  }
  const result=await applyReviewedSnapshot(project,snapshot,{source:source??project,prune});
  show('✓ تم تطبيق قرارات الباك الموافق عليها.');
  return result;
}

// Manual review with a Fable Backend still uses the signed Backend as authority.
// Only supplied fields are compared, and client-only UI preferences can differ.
export function reconcileManualWithBackend(manual,verified) {
  if(manual?.projectId!==verified?.projectId)throw Error('Manual project ID does not match verified Backend');
  const authoritative=verified.decisionSnapshot?.decisions;
  if(!authoritative)throw Error('Verified backend decisions unavailable');
  function assertSubset(candidate,original,path='decisions'){
    if(candidate===null || typeof candidate!=='object'||Array.isArray(candidate)){
      if(JSON.stringify(candidate)!==JSON.stringify(original))throw Error('Manual choice conflicts with Backend: '+path);
      return;
    }
    if(!original||typeof original!=='object')throw Error('Unknown backend choice: '+path);
    for(const [key,value] of Object.entries(candidate)){
      if(!(key in original))throw Error('Unknown backend choice: '+path+'.'+key);
      assertSubset(value,original[key],path+'.'+key);
    }
  }
  assertSubset(manual.decisions,authoritative);
  return {...verified,mode:'manual-review',
    uiPreferences:{...verified.uiPreferences,navigation:'developer-reviewed'},
    implementation:{...verified.implementation,
      instructions:'Manual choices were checked against the verified Fable Backend; build and runtime authorization remain backend-owned.'}};
}

export function saveFrontendSetup(root,snapshot,{apply=false,sourceDir=null}={}){
  const project=resolve(root);
  if(snapshot?.kind!=='fable.flutter-frontend-setup')throw Error('Refusing unsupported frontend setup');
  const summary={
    applied:Boolean(apply),projectId:snapshot.projectId,
    mode:snapshot.mode,projectBound:snapshot.projectBound,
    steps:snapshot.decisionSnapshot.steps.map(x=>({id:x.id,
      action:x.frontendAction??x.id,status:x.status??'review'})),
    output:[OUTPUT_PATH,PROJECT_PATH],
  };
  if(!apply)return summary;
  if(snapshot.backendAuthority===true){
    if(!sourceDir)throw Error('Cannot apply imported backend setup without source directory');
    const dir=sourceFiles(sourceDir);
    const contract=asJson(join(dir,'contract.json'));
    if(contract.contractHash!==snapshot.contractHash)throw Error('Source changed after validation');
    const to=resolve(project,'assets/contracts');
    mkdirSync(to,{recursive:true});
    for(const file of CONTRACT_FILES){const from=resolve(dir,file),dest=resolve(to,file);if(from!==dest)copyFileSync(from,dest);}
    if(existsSync(join(dir,'frontend-setup.json'))){const from=resolve(dir,'frontend-setup.json'),dest=resolve(to,'frontend-setup.json');if(from!==dest)copyFileSync(from,dest);}
    outputFile(project,'assets/config/backend.json',{
      schemaVersion:1,kind:'fable.mobile-backend-configuration',
      backend:{kind:'fable',adapter:'fable-contract',status:'ready'},
      contractImported:true,
    });
  }
  outputFile(project,OUTPUT_PATH,snapshot);
  outputFile(project,PROJECT_PATH,snapshot);
  return summary;
}
async function interactiveManual(question=null){
  const cli=question?null:createInterface({input:process.stdin,output:process.stdout});
  try{
    const ask=async(label,def)=>{const answer=(await (question?question(label+' ['+def+']: '):cli.question(label+' ['+def+']: '))).trim();return answer||def;};
    const yn=async(label,def=false)=>(await ask(label+' (yes/no)',def?'yes':'no')).toLowerCase()==='yes';
    const projectId=await ask('Project ID','my-app');
    const title=await ask('Project display title',projectId);
    const supportedLocales=(await ask('Supported locales, separated by comma','ar,en')).split(',').map(x=>x.trim()).filter(Boolean);
    const defaultLocale=await ask('Fallback locale',supportedLocales[0]??'ar');
    if(!supportedLocales.includes(defaultLocale))throw Error('Fallback locale must be supported');
    const identityMode=await ask('Login identity (email/phone/username/email-or-phone/email-phone-username)','email');
    if(!['email','phone','username','email-or-phone','email-phone-username'].includes(identityMode))throw Error('Unknown identity mode');
    const google=await yn('Google login available on external Backend?');
    const apple=await yn('Apple login available on external Backend?');
    const passkeys=await yn('Passkeys available on external Backend?');
    const sessions=await ask('Session mode (single/multi)','single');
    if(!['single','multi'].includes(sessions))throw Error('Invalid session mode');
    const maxActive=sessions==='single'?1:Number(await ask('Max active sessions (0=unlimited)','5'));
    if(!Number.isInteger(maxActive)||maxActive<0||maxActive>100)throw Error('Invalid max sessions');
    const identityModel=await ask('Account profiles (single/multi-profile)','single');
    if(!['single','multi-profile'].includes(identityModel))throw Error('Invalid profile model');
    const managedEnabled=await yn('Does an account manage related pages/stores/organizations?');
    const capabilities=(await ask('Installed UI capabilities (comma separated)','')).split(',').map(x=>x.trim()).filter(Boolean);
    const commercialMode=(await ask('Commercial access (FREE/PAID/TRIAL/FREEMIUM)','FREE')).toUpperCase();
    if(!['FREE','PAID','TRIAL','FREEMIUM'].includes(commercialMode))throw Error('Invalid access mode');
    const decisions={
      project:{id:projectId,name:title,clients:['flutter'],capabilities},
      localization:{defaultLocale,supportedLocales},
      authentication:{identityMode,google,apple,passkeys,
        sessions:{mode:sessions,maxActive,overflow:'revoke-oldest'}},
      accounts:{identityModel,managedEntities:{enabled:managedEnabled}},
      commercial:{mode:commercialMode},
    };
    return {schemaVersion:1,kind:'manual.frontend-setup-decisions',projectId,
      decisions,
      steps:['identity','authentication','accounts','permissions','capabilities','commercial']
        .map((id,index)=>({id,order:index+1,status:'manual-review',
          frontendAction:'Connect this choice to a verified external Backend API before production'}))};
  }finally{cli?.close();}
}
export async function runGuidedFlutterSetup({
  root=process.cwd(),source=null,expectedProjectId=null,expectedContractHash=null,
  prune=false,ask,show=console.log,askToImport=true,
}={}){
  if(typeof ask!=='function')throw Error('The guided frontend wizard requires a terminal question callback');
  const project=resolve(root);
  if(askToImport){
    const answer=(await ask('هل تريد استيراد قرارات Fable Backend الآن؟ (نعم/لا) [نعم]: ')).trim().toLowerCase();
    if(['لا','n','no','0'].includes(answer)){
      const draft=manualFrontendDecisions(await interactiveManual(ask));
      show(formatFrontendSetupReview(draft,{root:project}));
      const approve=await ask('اكتب «اعتمد» أو APPROVE لحفظ إعداد Flutter اليدوي: ');
      if(!isExplicitFrontendApproval(approve)){
        show('تم الإلغاء؛ لا توجد تغييرات.');
        return {applied:false,cancelled:true,mode:'manual'};
      }
      const result=saveFrontendSetup(project,draft,{apply:true});
      show('✓ تم حفظ إعداد Flutter اليدوي بعد الموافقة.');
      return result;
    }
  }
  let selectedSource=source;
  if(!selectedSource){
    const first=resolve(project,'../Fable-Backend-RC66/dist/client-contract');
    const second=resolve(project,'../backend/dist/client-contract');
    const suggestion=existsSync(join(first,'contract.json'))?first:second;
    const answer=(await ask('مسار ملف قرارات الباك (مجلد dist/client-contract) ['+suggestion+']: ')).trim();
    selectedSource=answer||suggestion;
  }
  return reviewedBackendImport({
    root:project,source:selectedSource,
    expectedProjectId,expectedContractHash,prune,ask,show,
  });
}
async function main(){
  const opt=explicitKeys(process.argv.slice(2));
  const root=resolve(opt.out??process.cwd());
  const guided=opt.mode==='guided'||(!opt.mode&&(process.stdin.isTTY||opt.interactive));
  const promptMode=guided || (opt.mode==='import' && (opt.interactive||(opt.apply && process.stdin.isTTY&&!opt.yes)));
  if(promptMode){
    const cli=createInterface({input:process.stdin,output:process.stdout});
    try{
      const result=await runGuidedFlutterSetup({
        root,source:opt.source??null,
        expectedProjectId:opt['expected-project-id']??null,
        expectedContractHash:opt['expected-contract-hash']??null,
        prune:!!opt.prune,ask:text=>cli.question(text),
        show:message=>console.log(message),askToImport:guided,
      });
      process.stdout.write(JSON.stringify(result,null,2)+'\n');
    }finally{cli.close();}
    return;
  }
  if(!['import','manual'].includes(opt.mode))
    throw Error('Run the wizard in an interactive terminal or use --mode import|manual. --mode guided asks about importing the Backend.');
  if(opt.yes && !opt.apply)throw Error('--yes is valid only with --apply');
  if(opt.prune && !opt.apply)throw Error('--prune requires explicit --apply');
  const imported=opt.source?importBackendDecisions(opt.source,{
    expectedProjectId:opt['expected-project-id']??null,
    expectedContractHash:opt['expected-contract-hash']??null,
  }):null;
  const input=opt.mode==='import'
    ? (imported??importBackendDecisions(root,{
        expectedProjectId:opt['expected-project-id']??null,
        expectedContractHash:opt['expected-contract-hash']??null,
      }))
    : (()=>{if(!opt.interactive&&!opt.file)throw Error('Manual mode requires --file or --interactive');return null;})();
  const snapshot=opt.mode==='manual'
    ?manualFrontendDecisions(opt.interactive?await interactiveManual():asJson(resolve(opt.file)))
    :input;
  const effective=(opt.mode==='manual' && imported)
    ?reconcileManualWithBackend(snapshot.decisionSnapshot,imported):snapshot;
  if(effective.backendAuthority)
    process.stdout.write(formatFrontendSetupReview(effective,{root})+'\n');
  if(opt.prune && (!effective.backendAuthority || !effective.projectBound))
    throw Error('Feature removal requires an independently pinned Backend project ID and contract hash');
  if(opt.apply && effective.backendAuthority && !opt.yes)
    throw Error('Refusing unattended changes. Run in a terminal for review/approval, or use --yes with independently verified --expected-project-id and --expected-contract-hash.');
  if(opt.apply && effective.backendAuthority && opt.yes && !effective.projectBound)
    throw Error('Unattended import requires independent project ID and Backend contract hash pins');
  const result=opt.apply
    ?await applyReviewedSnapshot(root,effective,{
       source:opt.mode==='import'?(opt.source??root):opt.source??null,
       prune:!!opt.prune,
     })
    :saveFrontendSetup(root,effective,{apply:false});
  if(!opt.apply && effective.backendAuthority && effective.decisionSnapshot?.decisions?.frontendFeatures){
    const {syncProjectFeatures}=await import('./sync-project-features.mjs');
    result.featureSync=syncProjectFeatures(root,effective,{apply:false,prune:false});
  }
  process.stdout.write(JSON.stringify(result,null,2)+'\n');
}
if(process.argv[1] && import.meta.url===pathToFileURL(resolve(process.argv[1])).href){
  main().catch(e=>{process.stderr.write('Flutter setup wizard: '+e.message+'\n');process.exitCode=1;});
}

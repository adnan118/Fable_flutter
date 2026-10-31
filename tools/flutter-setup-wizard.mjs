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
    if(['apply','interactive'].includes(key)){out[key]=true;continue;}
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
  if(snapshot.mode==='import'){
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
async function interactiveManual(){
  const cli=createInterface({input:process.stdin,output:process.stdout});
  try{
    const ask=async(label,def)=>{const answer=(await cli.question(label+' ['+def+']: ')).trim();return answer||def;};
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
  }finally{cli.close();}
}
async function main(){
  const opt=explicitKeys(process.argv.slice(2));
  if(!['import','manual'].includes(opt.mode))throw Error('Use --mode import|manual');
  const root=resolve(opt.out??process.cwd());
  const input=opt.mode==='import'?
    importBackendDecisions(opt.source??root,{
      expectedProjectId:opt['expected-project-id']??null,
      expectedContractHash:opt['expected-contract-hash']??null,
    }):manualFrontendDecisions(opt.interactive?
      await interactiveManual():asJson(resolve(opt.file??'')));
  const result=saveFrontendSetup(root,input,{apply:!!opt.apply,sourceDir:opt.mode==='import'?(opt.source??root):null});
  process.stdout.write(JSON.stringify(result,null,2)+'\n');
}
if(process.argv[1] && import.meta.url===pathToFileURL(resolve(process.argv[1])).href){
  main().catch(e=>{process.stderr.write('Flutter setup wizard: '+e.message+'\n');process.exitCode=1;});
}

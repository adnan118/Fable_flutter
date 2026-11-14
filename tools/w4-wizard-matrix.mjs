/**
 * RC212 — exercise the real Flutter Wizard for the 12 W0 cases.
 * Backend kind (Fable/Other) x initiator (guided developer/headless agent)
 * x profile (minimal/standard/complex). A source gate is not live E2E.
 *
 * Fable paths REQUIRE an independently pinned real export per profile.
 * Other paths must remain pending/unverified and Fable DPoP-free.
 */
import {
  cpSync,existsSync,lstatSync,mkdtempSync,mkdirSync,readFileSync,
  readdirSync,rmSync,
} from 'node:fs';
import {createHash} from 'node:crypto';
import {tmpdir} from 'node:os';
import {basename,join,relative,resolve,sep} from 'node:path';
import {fileURLToPath} from 'node:url';
import {
  runGuidedFlutterSetup,importBackendDecisions,manualFrontendDecisions,
  saveFrontendSetup,applyReviewedSnapshot,
} from './flutter-setup-wizard.mjs';

export const W4_PROFILES=Object.freeze(['minimal','standard','complex']);
export const W4_KINDS=Object.freeze(['fable','other']);
export const W4_INITIATORS=Object.freeze(['developer','agent']);
const DEFAULT_SOURCE=resolve(fileURLToPath(new URL('..',import.meta.url)));
const COPY_EXCLUDES=new Set([
  '.git','node_modules','.dart_tool','.gradle','.idea','.vscode','.pub-cache',
  'build','coverage','dist','Pods','.next','.env','.env.local',
]);
const REQUIRED_OUTPUTS=Object.freeze([
  'assets/config/backend.json','assets/config/frontend-setup.json',
  '.fable/frontend-setup.json',
  'assets/config/frontend-owned-decisions.json',
  '.fable/frontend-owned-decisions.json',
]);
export function w4ScenarioId(kind,initiator,profile){
  return 'WIZ-'+kind.toUpperCase()+'-'+initiator.toUpperCase()+'-'+profile.toUpperCase();
}
export function w4ScenarioPlan(){
  return W4_KINDS.flatMap(kind=>W4_INITIATORS.flatMap(initiator=>
    W4_PROFILES.map(profile=>({id:w4ScenarioId(kind,initiator,profile),
      kind,initiator,profile}))));
}
function manifestForOther(profile){
  const projectId='w4-external-'+profile;
  const features=profile==='minimal'?[]:
    profile==='standard'?['deeplinks']:['deeplinks','offline'];
  const locales=profile==='complex'?['ar','en','tr']:['ar','en'];
  const adapter=profile==='complex'?'custom':'openapi';
  const ids=['identity','authentication','accounts','permissions','capabilities','commercial'];
  return {
    schemaVersion:1,kind:'manual.frontend-setup-decisions',
    projectId,backendAdapter:adapter,
    decisions:{
      project:{id:projectId,name:'W4 external '+profile,clients:['flutter'],capabilities:features},
      localization:{defaultLocale:'ar',supportedLocales:locales},
      authentication:{status:'unverified-external-contract',
        methods:null,sessions:null,operations:null},
      accounts:{status:'unverified-external-contract',
        identityModel:null,managedEntities:null},
      permissions:{status:'unverified-external-contract'},
      commercial:{status:'unverified-external-contract'},
    },
    steps:ids.map((id,index)=>({id,order:index+1,status:'manual-review',
      frontendAction:'Connect this choice to a verified external Backend API before production'})),
  };
}
export function w4OtherManifest(profile){
  if(!W4_PROFILES.includes(profile))throw Error('Unknown W4 Other Backend profile');
  return manifestForOther(profile);
}
function guidedOtherAnswers(manual){
  return prompt=>{
    if(prompt.includes('هل الباك المستخدم'))return 'لا';
    if(prompt.includes('نوع عقد الباك الآخر'))return manual.backendAdapter;
    if(prompt.startsWith('Project ID'))return manual.projectId;
    if(prompt.startsWith('Project display title'))return manual.decisions.project.name;
    if(prompt.startsWith('Supported locales'))return manual.decisions.localization.supportedLocales.join(',');
    if(prompt.startsWith('Fallback locale'))return manual.decisions.localization.defaultLocale;
    if(prompt.startsWith('Flutter-only UI capabilities'))
      return manual.decisions.project.capabilities.join(',');
    if(prompt.includes('اكتب «اعتمد»'))return 'APPROVE';
    throw Error('Unmapped guided Other Backend question: '+prompt.slice(0,100));
  };
}
function guidedFableAnswers(prompt){
  if(prompt.includes('هل الباك المستخدم'))return 'نعم';
  if(prompt.includes('هل تريد استيراد قرارات'))return 'نعم';
  if(prompt.includes('اكتب «اعتمد»'))return 'APPROVE';
  throw Error('Unmapped guided Fable question: '+prompt.slice(0,100));
}
function copyStarter(source,destination){
  const root=resolve(source);
  if(!lstatSync(root).isDirectory()||lstatSync(root).isSymbolicLink())
    throw Error('Flutter starter root must be a real directory');
  let copied=0;
  cpSync(root,destination,{recursive:true,
    filter:path=>{
      const rel=relative(root,path);
      if(rel==='' || rel==='.')return true;
      const segments=rel.split(sep);
      if(segments.some(s=>COPY_EXCLUDES.has(s)))return false;
      if(lstatSync(path).isSymbolicLink())
        throw Error('Flutter starter contains a symbolic link: '+rel);
      copied++;
      if(copied>100000)throw Error('Flutter starter exceeds safe copy limit');
      return true;
    },
  });
  return copied;
}
function sha(value){return createHash('sha256').update(value).digest('hex');}
function fingerprintProject(root){
  const files=[];
  const visit=dir=>{
    for(const name of readdirSync(dir).sort()){
      const path=join(dir,name);
      const rel=relative(root,path).replaceAll('\\','/');
      // Archives preserve historical contracts but include unique backup
      // directories, which are not part of the active generated project.
      if(rel==='.fable/retired-fable-contracts')continue;
      const st=lstatSync(path);
      if(st.isSymbolicLink() || (!st.isFile()&&!st.isDirectory()))
        throw Error('Generated Flutter project contains unsafe source entry: '+rel);
      if(st.isDirectory())visit(path);
      else files.push([rel,sha(readFileSync(path))]);
    }
  };
  visit(root);
  const lines=files.map(([p,h])=>p+'\0'+h).join('\n');
  return {fileCount:files.length,fingerprint:sha(lines),files};
}
function outputAudit(root,kind,profile,sourcePin){
  const issues=[];
  for(const path of REQUIRED_OUTPUTS)
    if(!existsSync(join(root,path)))issues.push('Missing actual Wizard output: '+path);
  const config=JSON.parse(readFileSync(join(root,'assets/config/backend.json'),'utf8'));
  const decisions=JSON.parse(readFileSync(join(root,'assets/config/frontend-setup.json'),'utf8'));
  if(kind==='fable'){
    if(config.backend?.kind!=='fable'||config.backend?.adapter!=='fable-contract'||
        config.backend?.status!=='ready'||config.contractImported!==true)
      issues.push('Fable adapter did not import a verified ready contract');
    if(decisions.projectBound!==true||decisions.contractHash!==sourcePin?.expectedContractHash||
       decisions.projectId!==sourcePin?.expectedProjectId)
      issues.push('Fable setup does not match independent project and contract pins');
    for(const name of ['contract.json','flutter-handoff.json','openapi.json',
      'mobile-core-operations.json'])
      if(!existsSync(join(root,'assets/contracts',name)))
        issues.push('Fable imported contract missing: '+name);
  }else{
    if(config.backend?.kind!=='other'||config.backend?.status!=='pending'||
       config.contractImported!==false||decisions.backendAuthority!==false)
      issues.push('External Backend was incorrectly activated as Fable');
    if(existsSync(join(root,'assets/contracts/contract.json')))
      issues.push('Stale Fable contract still active in Other Backend project');
    if(decisions.decisionSnapshot?.decisions?.authentication?.status!==
        'unverified-external-contract')
      issues.push('External Auth was incorrectly marked verified');
  }
  if(issues.length)throw Error(issues.join('; '));
  return {kind,profile,projectId:decisions.projectId,
    backendStatus:config.backend?.status,
    projectBound:Boolean(decisions.projectBound),
    contractImported:Boolean(config.contractImported),
    nativeDpopE2EVerified:false,
    featureBindingVerified:false};
}

export async function runW4WizardMatrix({
  fableExports={},workspaceRoot=null,keepWorkspace=false,
  materializeFlutterSource=false,flutterSourceRoot=DEFAULT_SOURCE,
}={}){
  const owned=!workspaceRoot;
  const workspace=workspaceRoot?resolve(workspaceRoot):
    mkdtempSync(join(tmpdir(),'fable-w4-rc212-'));
  const cases=[],issues=[];
  const pairs=new Map();
  try{
    for(const entry of w4ScenarioPlan()){
      const {id,kind,initiator,profile}=entry;
      const pin=fableExports[profile];
      if(kind==='fable'&&(!pin?.source||!pin?.expectedProjectId||
          !/^[a-f0-9]{64}$/.test(pin?.expectedContractHash??''))){
        cases.push({...entry,status:'BLOCKED',passed:false,
          issues:['A real independent Backend export and project+SHA pin are required'],
          fullFlutterProjectMaterialized:false});
        issues.push(id+': missing trusted Backend export');
        continue;
      }
      const project=join(workspace,id.toLowerCase());
      if(existsSync(project)){
        if(readdirSync(project).length)throw Error('W4 scenario destination is not empty: '+project);
      }else mkdirSync(project,{recursive:true});
      try{
        if(materializeFlutterSource)copyStarter(flutterSourceRoot,project);
        let applied;
        if(kind==='fable'){
          if(initiator==='developer')applied=await runGuidedFlutterSetup({
            root:project,source:pin.source,
            expectedProjectId:pin.expectedProjectId,
            expectedContractHash:pin.expectedContractHash,
            ask:guidedFableAnswers,show:()=>{},
          });
          else {
            const snapshot=importBackendDecisions(pin.source,{
              expectedProjectId:pin.expectedProjectId,
              expectedContractHash:pin.expectedContractHash,
            });
            applied=await applyReviewedSnapshot(project,snapshot,{source:pin.source});
          }
        }else {
          const other=w4OtherManifest(profile);
          if(initiator==='developer')applied=await runGuidedFlutterSetup({
            root:project,ask:guidedOtherAnswers(other),show:()=>{},
          });
          else applied=saveFrontendSetup(project,manualFrontendDecisions(other),{apply:true});
        }
        if(applied?.applied!==true)throw Error('Wizard did not apply the reviewed configuration');
        const safety=outputAudit(project,kind,profile,pin);
        const inventory=fingerprintProject(project);
        const pairKey=kind+':'+profile;
        const partner=pairs.get(pairKey);
        const parity=partner?partner.fingerprint===inventory.fingerprint:null;
        if(!partner)pairs.set(pairKey,{id,fingerprint:inventory.fingerprint});
        if(parity===false)throw Error('Guided/Agent generated source drift compared to '+partner.id);
        cases.push({...entry,status:'SOURCE_GENERATED',passed:true,
          issues:[],...safety,
          fingerprint:inventory.fingerprint,fileCount:inventory.fileCount,
          fullFlutterProjectMaterialized:Boolean(materializeFlutterSource),
          comparedWith:partner?.id??null,
          sourceOnly:true,liveE2EVerified:false});
      }catch(error){
        cases.push({...entry,status:'FAILED',passed:false,
          issues:[String(error.message??error)],
          fullFlutterProjectMaterialized:Boolean(materializeFlutterSource)});
        issues.push(id+': '+String(error.message??error));
      }
    }
    const paired=W4_KINDS.flatMap(kind=>W4_PROFILES.map(profile=>{
      const a=cases.find(c=>c.kind===kind&&c.profile===profile&&c.initiator==='developer');
      const b=cases.find(c=>c.kind===kind&&c.profile===profile&&c.initiator==='agent');
      const same=a?.passed&&b?.passed&&a.fingerprint===b.fingerprint;
      return {kind,profile,passed:Boolean(same),
        developer:a?.id??null,agent:b?.id??null};
    }));
    if(paired.some(p=>!p.passed))issues.push('At least one W4 Guided/Agent source pair is unverified or different');
    if(!materializeFlutterSource)issues.push('Full Flutter project materialization was not requested');
    return {schemaVersion:1,batch:'RC212-W4',
      passed:issues.length===0,sourceOnly: true,
      counts:{scenarios:cases.length,generated:cases.filter(c=>c.passed).length,
        blocked:cases.filter(c=>c.status==='BLOCKED').length,
        failed:cases.filter(c=>c.status==='FAILED').length,
        matchingPairs:paired.filter(p=>p.passed).length},
      cases,paired,issues,
      realFlutterBuildVerified:false,realOtherBackendContractVerified:false,
      nativeDpopVerified:false,liveE2EVerified:false,productionApproved:false,
      workspace:keepWorkspace?workspace:null};
  }finally{
    if(owned&&!keepWorkspace)rmSync(workspace,{recursive:true,force:true});
  }
}

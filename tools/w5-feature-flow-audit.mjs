/**
 * RC213 W5 — fail-closed, operation-level source chain. This is not proof
 * of executing a Flutter UI flow or of runtime authorization.
 */
import {existsSync,readFileSync} from 'node:fs';
import {join,resolve} from 'node:path';
import {createHash} from 'node:crypto';
import {readSafeFeatureEvidence} from './w5-safe-source-evidence.mjs';
import {verifyFableContract} from './verify-fable-contract.mjs';
import {FEATURE_OWNERSHIP} from './frontend-feature-ownership.mjs';

const MANIFEST='.fable/w5-operation-flows.json';
const SELECTION='.fable/mobile-features.json';
const BACKEND='assets/config/backend.json';
const FABLE_CONTRACT='assets/contracts/contract.json';
const OTHER_CONTRACT='assets/contracts/external-operations.json';
const OTHER_BINDINGS='assets/config/feature-operations.json';
const STAGES=['repository','state','ui','navigation','test'];
const METHODS=new Set(['GET','HEAD','POST','PUT','PATCH','DELETE']);
const MARKER=/^[\w.$/()'":\- ]{3,180}$/;
const SHA=/^[a-f0-9]{64}$/;
const read=rootPath=>JSON.parse(readFileSync(rootPath,'utf8'));
const sha=value=>createHash('sha256').update(JSON.stringify(value)).digest('hex');
const isObject=x=>x&&typeof x==='object'&&!Array.isArray(x);
const problem=(code,feature,operationId=null)=>({code,feature,...(operationId?{operationId}:{})});
function failRow(id,issues){return {operationId:id,sourceVerified:false,issues};}
function resolveOperation(contract,backend,operationId){
  const operations=contract?.operations??[];
  if(!Array.isArray(operations))return null;
  return operations.find(x=>(backend==='fable'?x.operationId:x.operationId)===operationId)??null;
}
function validateContractBinding(entry,contract,backend,externalBindings){
  const issues=[],id=entry.operationId;
  const declared=resolveOperation(contract,backend,id);
  if(!declared){issues.push('OPERATION_NOT_IN_ACTIVE_BACKEND_CONTRACT');return issues;}
  if(declared.method!==entry.method || declared.path!==entry.path)
    issues.push('OPERATION_METHOD_PATH_MISMATCH');
  if(backend==='other'){
    const links=externalBindings?.bindings?.[entry.feature];
    if(!isObject(links)||!Object.values(links).includes(id))
      issues.push('EXTERNAL_OPERATION_NOT_FEATURE_BOUND');
    if(declared.auth==='provider' || declared.path?.includes('/webhooks/'))
      issues.push('EXTERNAL_SERVER_ONLY_OPERATION');
    if(!['GET','HEAD'].includes(declared.method)&&declared.auth!=='bearer')
      issues.push('EXTERNAL_WRITE_REQUIRES_VERIFIED_BEARER_AUTH');
  }
  const declaredPermissions=Array.isArray(declared.permissions)?declared.permissions:
    declared.permission?[declared.permission]:[];
  if(entry.permission!==undefined && entry.permission!==null &&
     !declaredPermissions.includes(entry.permission))
    issues.push('SOURCE_PERMISSION_NOT_IN_CONTRACT');
  return issues;
}
/** Pure/overridable file reader is for isolated tests; CLI always uses secure Node reader. */
export function inspectW5SourceFlowPlan({
  selected,backendKind,manifest,contract,readEvidence,
  externalBindings=null,projectId,contractHash,
}={}){
  const issues=[],rows=[],features=[];
  if(!Array.isArray(selected)||selected.some(x=>typeof x!=='string'||!x)||
     new Set(selected).size!==selected.length)
    throw Error('W5_INVALID_SELECTED_FEATURES');
  if(!['fable','other'].includes(backendKind))throw Error('W5_BACKEND_KIND_UNSELECTED');
  if(typeof readEvidence!=='function')throw Error('W5_EVIDENCE_READER_REQUIRED');
  if(!manifest||manifest.schemaVersion!==1||manifest.kind!=='fable.w5-operation-flows'||
     manifest.projectId!==projectId||manifest.backendKind!==backendKind||
     manifest.contractHash!==contractHash||!Array.isArray(manifest.flows))
    return {schemaVersion:1,batch:'RC213-W5',sourceTracePassed:false,
      counts:{selected:selected.length,flowCount:0,sourceMapped:0,blocked:selected.length},
      features:selected.map(id=>({id,status:'BLOCKED',
        issues:['W5_EVIDENCE_MANIFEST_MISSING_OR_STALE']})),
      operations:[],issues:['W5_EVIDENCE_MANIFEST_MISSING_OR_STALE'],
      liveE2EVerified:false,productionApproved:false};
  if(manifest.flows.length>2000)throw Error('W5_TOO_MANY_OPERATION_FLOWS');
  const used=new Set(),byFeature=new Map();
  for(const entry of manifest.flows){
    const feature=entry?.feature,id=entry?.operationId;
    if(typeof feature!=='string'||!selected.includes(feature)||
       typeof id!=='string'||!id.trim()||id.length>150){
      issues.push('W5_UNKNOWN_OR_INVALID_OPERATION_FLOW');continue;
    }
    const key=feature+'\0'+id;
    if(used.has(key)){
      issues.push('W5_DUPLICATE_OPERATION_FLOW:'+feature);continue;
    }
    used.add(key);
    if(!byFeature.has(feature))byFeature.set(feature,[]);
    const gaps=[];
    const validMethod=typeof entry.method==='string'&&METHODS.has(entry.method);
    if(!validMethod||typeof entry.path!=='string'||!entry.path.startsWith('/')||
       entry.path.startsWith('//')||entry.path.includes('..')||
       entry.path.includes('*'))
      gaps.push('INVALID_OPERATION_METHOD_OR_PATH');
    if(!['backend','client'].includes(entry.mode))
      gaps.push('INVALID_FEATURE_FLOW_MODE');
    if(entry.mode==='client' && FEATURE_OWNERSHIP[feature]==='server')
      gaps.push('SERVER_FEATURE_CANNOT_PRETEND_TO_BE_CLIENT_ONLY');
    if(entry.mode==='backend'){
      gaps.push(...validateContractBinding(entry,contract,backendKind,externalBindings));
    }else if(entry.mode==='client' && backendKind==='other' &&
      contract?.operations?.some(x=>x.operationId===id)){
      gaps.push('CLIENT_ONLY_MUST_NOT_INVENT_EXTERNAL_API');
    }
    const states=entry.stages;
    if(!isObject(states))gaps.push('FLOW_SOURCE_STAGES_MISSING');
    else{
      const loaded={};
      for(const stage of STAGES){
        const part=states[stage];
        if(!isObject(part)||typeof part.path!=='string'||
           typeof part.marker!=='string'||!MARKER.test(part.marker)){
          gaps.push('FLOW_STAGE_DECLARATION_MISSING:'+stage);continue;
        }
        try{
          const body=readEvidence(part.path);
          if(typeof body!=='string'||!body.includes(part.marker))
            gaps.push('FLOW_STAGE_SYMBOL_NOT_FOUND:'+stage);
          else loaded[stage]=body;
        }catch{
          gaps.push('FLOW_STAGE_FILE_UNSAFE_OR_MISSING:'+stage);
        }
      }
      // These form an actual chain of source references. A marker in an
      // unrelated file is insufficient to record a connected operation.
      if(entry.mode==='backend' &&
         loaded.repository&&!loaded.repository.includes(id))
        gaps.push('REPOSITORY_OPERATION_ID_NOT_REFERENCED');
      for(const [prev,next] of [
        ['repository','state'],['state','ui'],['ui','navigation']]){
        if(loaded[prev]&&loaded[next] &&
           !loaded[next].includes(states[prev].marker))
          gaps.push('FLOW_LINK_NOT_FOUND:'+prev+'->'+next);
      }
      if(loaded.test && loaded.ui &&
         !loaded.test.includes(states.ui.marker) &&
         !loaded.test.includes(id))
        gaps.push('FLOW_TEST_DOES_NOT_REFERENCE_OPERATION_OR_UI');
    }
    if(entry.mode==='backend'){
      if(!isObject(entry.dto)||!isObject(entry.dto.request)||
         !isObject(entry.dto.response))
        gaps.push('TYPED_DTO_EVIDENCE_MISSING');
      else for(const type of ['request','response']){
        const part=entry.dto[type];
        try{
          const body=readEvidence(part.path);
          if(typeof part.marker!=='string'||!MARKER.test(part.marker)||
             !body.includes(part.marker))
            gaps.push('DTO_SOURCE_MARKER_MISSING:'+type);
        }catch{gaps.push('DTO_FILE_UNSAFE_OR_MISSING:'+type);}
      }
      if(!Array.isArray(entry.errorCases)||entry.errorCases.length===0||
         entry.errorCases.some(x=>typeof x!=='string'||!x))
        gaps.push('ERROR_CASES_NOT_DECLARED');
      if(!Array.isArray(entry.permissionCases)||entry.permissionCases.length===0)
        gaps.push('PERMISSION_CASES_NOT_DECLARED');
      // Trace declarations are never runtime test evidence.
    }
    const unique=[...new Set(gaps)];
    const row={feature,operationId:id,sourceVerified:unique.length===0,
      issues:unique};
    rows.push(row);byFeature.get(feature).push(row);
  }
  for(const id of selected){
    const list=byFeature.get(id)??[];
    const gap=[];
    if(!list.length)gap.push('SELECTED_FEATURE_HAS_NO_FLOW_EVIDENCE');
    if(list.some(x=>!x.sourceVerified))gap.push('SELECTED_FEATURE_HAS_UNVERIFIED_FLOWS');
    const complete=list.length>0&&gap.length===0;
    features.push({id,status:complete?'SOURCE_CHAIN_PRESENT_E2E_PENDING':'BLOCKED',
      operationCount:list.length,issues:gap});
  }
  const mapped=rows.filter(x=>x.sourceVerified).length;
  const resultIssues=[
    ...issues,...features.filter(x=>x.status==='BLOCKED')
      .map(x=>x.id+': '+x.issues.join(',')),
  ];
  return {schemaVersion:1,batch:'RC213-W5',
    sourceTracePassed:resultIssues.length===0,
    counts:{selected:selected.length,flowCount:rows.length,
      sourceMapped:mapped,blocked:features.filter(x=>x.status==='BLOCKED').length},
    features,operations:rows,issues:resultIssues,
    liveE2EVerified:false,productionApproved:false,
  };
}
export function auditW5FeatureFlows(root,{
  expectedProjectId=null,expectedContractHash=null,
}={}){
  root=resolve(root);
  if(!existsSync(join(root,SELECTION)))
    throw Error('W5_EXPLICIT_FEATURE_SELECTION_REQUIRED');
  const selection=read(join(root,SELECTION));
  const selected=selection?.features;
  if(!Array.isArray(selected))throw Error('W5_INVALID_FEATURE_SELECTION_FILE');
  const cfg=read(join(root,BACKEND));
  const kind=cfg?.backend?.kind;
  if(!['fable','other'].includes(kind))throw Error('W5_BACKEND_NOT_SELECTED');
  const manifest=existsSync(join(root,MANIFEST))?read(join(root,MANIFEST)):null;
  let contract,bindings=null,contractHash=null,projectId=manifest?.projectId??null;
  const sourceIssues=[];
  if(kind==='fable'){
    const p=join(root,FABLE_CONTRACT);
    if(!existsSync(p))throw Error('W5_FABLE_CONTRACT_MISSING');
    contract=read(p);contractHash=contract.contractHash;
    if(!expectedProjectId||!expectedContractHash)sourceIssues.push('INDEPENDENT_FABLE_PINS_MISSING');
    else{
      const proof=verifyFableContract(root,{mode:'project',
        expectedProjectId,expectedContractHash});
      if(!proof.ok)sourceIssues.push('FABLE_CONTRACT_PROJECT_VERIFICATION_FAILED:'+proof.failures.join(','));
    }
    projectId=contract.project?.id;
    if(cfg.contractImported!==true||cfg.backend.status!=='ready')
      sourceIssues.push('FABLE_BACKEND_NOT_READY');
  }else{
    contract=existsSync(join(root,OTHER_CONTRACT))?read(join(root,OTHER_CONTRACT)):null;
    bindings=existsSync(join(root,OTHER_BINDINGS))?read(join(root,OTHER_BINDINGS)):null;
    contractHash=contract?.sourceHash??null;
    if(cfg.contractImported!==true||cfg.backend.status!=='ready')
      sourceIssues.push('OTHER_BACKEND_NOT_READY');
    if(existsSync(join(root,FABLE_CONTRACT)))
      sourceIssues.push('STALE_FABLE_CONTRACT_IN_OTHER_BACKEND');
    if(!contract||contract.kind!=='fable.external-operation-catalog'||
       contract.adapter!==cfg.backend.adapter||
       !SHA.test(contract.sourceHash??'')||
       sha(contract.operations)!==contract.operationsHash)
      sourceIssues.push('EXTERNAL_CATALOG_INVALID_OR_UNVERIFIED');
    if(!bindings||bindings.kind!=='fable.feature-operation-bindings'||
       bindings.sourceHash!==contract?.sourceHash||
       bindings.operationsHash!==contract?.operationsHash)
      sourceIssues.push('EXTERNAL_FEATURE_BINDINGS_NOT_PINNED');
  }
  const result=inspectW5SourceFlowPlan({selected,backendKind:kind,manifest,
    contract,externalBindings:bindings,projectId,contractHash,
    readEvidence:path=>readSafeFeatureEvidence(root,path)});
  result.sourceIssues=sourceIssues;
  result.sourceTracePassed=result.sourceTracePassed&&sourceIssues.length===0;
  result.backendKind=kind;
  result.independentContractPinVerified=kind==='fable'&&sourceIssues.length===0;
  result.liveE2EVerified=false;result.productionApproved=false;
  return result;
}

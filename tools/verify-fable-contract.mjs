#!/usr/bin/env node
/**
 * Offline, read-only Fable Flutter contract acceptance gate.
 * Source mode verifies the import graph, not a live Backend or production state.
 * Project mode requires an explicit non-fixture project identity.
 */
import {readFileSync} from 'node:fs';
import {join, resolve} from 'node:path';
import {createHash} from 'node:crypto';
import {pathToFileURL} from 'node:url';

const digest = value => createHash('sha256').update(JSON.stringify(value)).digest('hex');
// Match Backend RC66 lib/client-contract-export.mjs canonical object order.
const canonical = value => Array.isArray(value) ? value.map(canonical) :
  value && typeof value==='object' ? Object.fromEntries(Object.entries(value)
    .filter(([,v])=>v!==undefined).sort(([a],[b])=>a.localeCompare(b))
    .map(([k,v])=>[k,canonical(v)])) : value;
const backendDigest = value => digest(canonical(value));
const sha256 = value => /^[a-f0-9]{64}$/.test(value ?? '');
const methods = new Set(['GET','POST','PUT','PATCH','DELETE','HEAD']);

export function verifyFableContract(root, {mode='source', expectedProjectId=null, expectedContractHash=null}={}) {
  const messages = [];
  const failures = [];
  const fail = (code) => failures.push(code);
  const read = (path) => {
    try {return JSON.parse(readFileSync(join(root,path), 'utf8'));}
    catch (_) {fail(`cannot_read_or_parse:${path}`);return null;}
  };
  const cfg = read('assets/config/backend.json');
  const contract = read('assets/contracts/contract.json');
  const handoff = read('assets/contracts/flutter-handoff.json');
  const openapi = read('assets/contracts/openapi.json');
  const core = read('assets/contracts/mobile-core-operations.json');
  if (!cfg || !contract || !handoff || !openapi || !core) return {ok:false,mode,failures,messages,productionReady:false};

  if (mode!=='source' && mode!=='project') fail('invalid_mode');
  if (cfg.kind!=='fable.mobile-backend-configuration' || cfg.schemaVersion!==1 ||
      cfg.backend?.kind!=='fable' || cfg.backend?.adapter!=='fable-contract' ||
      cfg.backend?.status!=='ready' || cfg.contractImported!==true) fail('backend_configuration_not_imported');
  if (contract.kind!=='fable.client-contract' || !contract.project || typeof contract.project.id!=='string' || !contract.project.id.trim()) fail('invalid_contract_project');
  if (!sha256(contract.contractHash)) fail('invalid_contract_hash');
  const {contractHash, ...unsignedContract}=contract;
  if(backendDigest(unsignedContract)!==contractHash) fail('contract_content_hash_mismatch');
  if (handoff.kind!=='fable.flutter-handoff' || handoff.schemaVersion!==1 || handoff.client!=='flutter') fail('invalid_handoff_schema');
  const {manifestHash, ...unsigned}=handoff;
  if (!sha256(manifestHash) || digest(unsigned)!==manifestHash) fail('handoff_integrity_mismatch');
  if (handoff.backend?.contractHash!==contract.contractHash || handoff.backend?.project?.id!==contract.project?.id ||
      handoff.backend?.project?.name!==contract.project?.name) fail('handoff_backend_identity_mismatch');
  if (openapi.openapi!=='3.1.0' || typeof openapi.paths!=='object' || !openapi.paths || Array.isArray(openapi.paths)) fail('invalid_openapi_document');
  if (core.kind!=='fable.mobile-core-operations' || core.schemaVersion!==1 || core.backendContractHash!==contract.contractHash ||
      !Array.isArray(core.operations) || !sha256(core.operationsHash) || digest(core.operations)!==core.operationsHash) fail('mobile_core_integrity_mismatch');

  const ids=new Set();
  for (const op of Array.isArray(core.operations)?core.operations:[]) {
    if (typeof op.operationId!=='string' || !op.operationId.trim() || ids.has(op.operationId) ||
        typeof op.path!=='string' || !op.path.startsWith('/') || op.path.startsWith('//') ||
        !methods.has(op.method) || typeof op.public!=='boolean') fail('invalid_mobile_core_operation');
    if(typeof op.operationId==='string')ids.add(op.operationId);
  }
  const catalogOps=new Map();
  if(!Array.isArray(contract.operations))fail('invalid_contract_operations');
  else for(const op of contract.operations){
    if(!op || typeof op.operationId!=='string' || catalogOps.has(op.operationId) ||
       !methods.has(op.method) || typeof op.path!=='string' || !sha256(op.contractHash)) {fail('invalid_contract_operation');continue;}
    const {contractHash:opHash,...unsignedOp}=op;
    if(backendDigest(unsignedOp)!==opHash)fail('contract_operation_hash_mismatch');
    catalogOps.set(op.operationId,op);
  }
  let projectOperations=0;
  for (const [path, routes] of Object.entries(openapi.paths || {})) {
    if (!path.startsWith('/') || path.startsWith('//') || !routes || typeof routes!=='object' || Array.isArray(routes)) {
      fail('invalid_openapi_route');continue;
    }
    for(const [verb,info] of Object.entries(routes)) {
      if(!methods.has(verb.toUpperCase()))continue;
      projectOperations++;
      if(!info || typeof info!=='object' || typeof info.operationId!=='string' ||
         typeof info['x-fable-public']!=='boolean' || !sha256(info['x-fable-contract-hash'])) fail('invalid_project_operation');
      else {
        const catalog=catalogOps.get(info.operationId);
        const backendPath=catalog?.path?.replace(/:([A-Za-z0-9_]+)/g,'{$1}');
        if(!catalog || backendPath!==path || catalog.method.toLowerCase()!==verb.toLowerCase() ||
           catalog.contractHash!==info['x-fable-contract-hash'] || catalog.public!==info['x-fable-public'])
          fail('openapi_contract_operation_mismatch');
        const overlap=core.operations?.find(op=>op.operationId===info.operationId);
        if(overlap && (overlap.method!==verb.toUpperCase() || overlap.path!==path || overlap.public!==info['x-fable-public']))
          fail('mobile_core_overlap_mismatch');
        if(!overlap && ids.has(info.operationId))fail('duplicate_project_operation_id');
      }
      if(typeof info?.operationId==='string') ids.add(info.operationId);
    }
  }
  if(Array.isArray(contract.operations) && projectOperations!==contract.operations.length)fail('project_operation_count_mismatch');
  // Surface backend session policy directly to the Flutter project wizard.
  // Legacy exports remain unknown; never silently assume multi-device.
  const declaredSessionPolicy=contract.core?.auth?.sessionPolicy;
  let sessionPolicy=null;
  if(declaredSessionPolicy!==undefined){
    const p=declaredSessionPolicy;
    if(!p || typeof p!=='object' || Array.isArray(p) ||
       !['single','multi'].includes(p.mode) ||
       !Number.isInteger(p.maxActive) || p.maxActive<0 || p.maxActive>100 ||
       (p.mode==='single' && p.maxActive!==1) ||
       !['revoke-oldest','reject-new'].includes(p.overflow) ||
       p.runtimeEndpoint!=='/auth/session-policy' || p.runtimeAuthoritative!==true){
      fail('invalid_session_policy_contract');
    }else{
      const allOps=[...(contract.operations??[]),...(core.operations??[])];
      if(!allOps.some(o=>o.operationId==='auth.session-policy' && o.method==='GET' &&
          o.path==='/auth/session-policy' && o.public===true)){
        fail('session_policy_route_missing');
      }else{
        sessionPolicy={mode:p.mode,maxActive:p.maxActive,overflow:p.overflow,
          runtimeEndpoint:p.runtimeEndpoint,runtimeAuthoritative:true,
          allowsMultipleSessions:p.mode==='multi' && (p.maxActive===0 || p.maxActive>1)};
      }
    }
  }
  const fixture=contract.project?.id==='test-project' || contract.project?.name==='fable-test';
  if(mode==='project') {
    if(!expectedProjectId || typeof expectedProjectId!=='string' || !expectedProjectId.trim()) fail('expected_project_id_required');
    if(fixture) fail('fixture_project_not_accepted');
    if(expectedProjectId && contract.project?.id!==expectedProjectId) fail('expected_project_id_mismatch');
    // The source-of-truth Backend export digest must be supplied independently;
    // a forged/matched project label does not make a client contract trusted.
    if(!sha256(expectedContractHash)) fail('expected_backend_export_hash_required');
    else if(expectedContractHash!==contract.contractHash) fail('expected_backend_export_hash_mismatch');
    // A project with only Auth may legitimately have zero business operations.
    // Never infer missing capabilities from the number of OpenAPI routes.
  } else if(fixture) messages.push('Starter/test project: structurally valid, NOT a project integration approval.');

  const result={ok:failures.length===0,mode,projectId:contract.project?.id||null,
    fixture,operationCount:projectOperations,mobileCoreOperations:Array.isArray(core.operations)?core.operations.length:0,
    contractHash:contract.contractHash,projectBound:mode==='project'&&failures.length===0,
    productionReady:false,sessionPolicy,failures,messages};
  return result;
}

function cli(argv) {
  let root=process.cwd(), mode='source', expectedProjectId=null, expectedContractHash=null;
  for(let i=0;i<argv.length;i++){
    if(argv[i]==='--root' && argv[i+1]) root=resolve(argv[++i]);
    else if(argv[i]==='--mode' && argv[i+1]) mode=argv[++i];
    else if(argv[i]==='--expected-project-id' && argv[i+1]) expectedProjectId=argv[++i];
    else if(argv[i]==='--expected-contract-hash' && argv[i+1]) expectedContractHash=argv[++i];
    else throw new Error(`Unsupported/missing CLI argument: ${argv[i]}`);
  }
  const result=verifyFableContract(root,{mode,expectedProjectId,expectedContractHash});
  process.stdout.write(JSON.stringify(result,null,2)+'\n');
  if(!result.ok)process.exitCode=2;
}
if(process.argv[1] && import.meta.url===pathToFileURL(resolve(process.argv[1])).href){
  try{cli(process.argv.slice(2));}
  catch(e){process.stderr.write(String(e.message)+'\n');process.exitCode=2;}
}
import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,mkdirSync,writeFileSync,readFileSync,symlinkSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join,dirname} from 'node:path';
import {createHash} from 'node:crypto';
import {inspectW5SourceFlowPlan,auditW5FeatureFlows} from '../tools/w5-feature-flow-audit.mjs';
import {readSafeFeatureEvidence,hasSafeFeatureEvidence} from '../tools/w5-safe-source-evidence.mjs';
import {parseW5Args} from '../tools/run-w5-feature-flow-audit.mjs';

const ID='external.notes.list',HASH='a'.repeat(64);
const hash=value=>createHash('sha256').update(JSON.stringify(value)).digest('hex');
function flow(feature='notifications',mode='backend'){
 return {
  feature,mode,operationId:mode==='client'?'client.deeplinks.open':ID,
  method:mode==='client'?'LOCAL':'GET',
  path:mode==='client'?'local:deeplinks/open':'/notes',
  stages:{
   repository:{path:'lib/repository.dart',marker:'NotesRepository'},
   state:{path:'lib/state.dart',marker:'NotesState'},
   ui:{path:'lib/notes_page.dart',marker:'NotesPage'},
   navigation:{path:'lib/navigation.dart',marker:'openNotes'},
   test:{path:'test/notes_test.dart',marker:'NotesPage'},
  },
  dto:{request:{path:'lib/dto.dart',marker:'NotesRequest'},
    response:{path:'lib/dto.dart',marker:'NotesResponse'}},
  errorCases:['401','403'],permissionCases:['denied'],
 };
}
const CATALOG={operations:[{operationId:ID,method:'GET',path:'/notes',auth:'bearer'}]};
const BINDINGS={bindings:{notifications:{list:ID}}};
function fakeRead(path){
 const f={
  'lib/repository.dart':`class NotesRepository { final operation = '${ID}'; }`,
  'lib/state.dart':'class NotesState { final NotesRepository repo; }',
  'lib/notes_page.dart':'class NotesPage { final NotesState state; }',
  'lib/navigation.dart':'void openNotes() { NotesPage(); }',
  'test/notes_test.dart':'testWidgets(\'NotesPage\', ...);',
  'lib/dto.dart':'class NotesRequest {} class NotesResponse {}',
 };
 if(!(path in f))throw Error('missing');
 return f[path];
}
function pure({selected=['notifications'],flows=[flow()],backendKind='other',
   contract=CATALOG,externalBindings=BINDINGS,readEvidence=fakeRead,
   contractHash=HASH,projectId='w5-real-project',requirements=null}={}){
 const scoped=requirements??{features:Object.fromEntries(selected.map(id=>[
  id,{needsBackend:id!=='deeplinks',operations:id==='deeplinks'?[]:
    [{operationId:ID,method:'GET',path:'/notes'}]},
 ]))};
 return inspectW5SourceFlowPlan({selected,backendKind,manifest:{
  schemaVersion:1,kind:'fable.w5-operation-flows',projectId,backendKind,
  contractHash,flows,
 },contract,externalBindings,readEvidence,projectId,contractHash,
   requirements:scoped});
}
function fixture(t){
 const root=mkdtempSync(join(tmpdir(),'fable-w5-rc213-'));
 t.after(()=>rmSync(root,{recursive:true,force:true}));
 const write=(name,body)=>{
  const file=join(root,name);mkdirSync(dirname(file),{recursive:true});
  writeFileSync(file,typeof body==='string'?body:JSON.stringify(body));
 };
 const catalog={schemaVersion:1,kind:'fable.external-operation-catalog',
  adapter:'openapi',sourceHash:HASH,operations:CATALOG.operations,
  operationsHash:hash(CATALOG.operations)};
 const bindings={schemaVersion:1,kind:'fable.feature-operation-bindings',
  adapter:'openapi',sourceHash:HASH,operationsHash:catalog.operationsHash,
  bindings:BINDINGS.bindings};
 write('.fable/mobile-features.json',{features:['notifications']});
 write('assets/config/backend.json',{kind:'fable.mobile-backend-configuration',
  backend:{kind:'other',adapter:'openapi',status:'ready'},contractImported:true});
 write('assets/contracts/external-operations.json',catalog);
 write('assets/config/feature-operations.json',bindings);
 write('.fable/w5-operation-flows.json',{
  schemaVersion:1,kind:'fable.w5-operation-flows',projectId:'w5-real-project',
  backendKind:'other',contractHash:HASH,flows:[flow()]});
 write('.fable/feature-integration-requirements.json',{
  schemaVersion:1,kind:'fable.feature-integration-requirements',
  features:{notifications:{needsBackend:true,
    operations:[{operationId:ID,method:'GET',path:'/notes'}]}},
 });
 for(const path of Object.keys(flow().stages).map(k=>flow().stages[k].path)
   .concat('lib/dto.dart'))write(path,fakeRead(path));
 return {root,write};
}
test('RC213 pure W5 gate validates five linked real-source declarations against current HTTP contract',()=>{
 const report=pure();
 assert.equal(report.sourceTracePassed,true,JSON.stringify(report.issues));
 assert.equal(report.counts.sourceMapped,1);
 assert.equal(report.productionApproved,false);
 assert.equal(report.liveE2EVerified,false);
});
test('RC213 W5 detects a missing Repository→State link, never marks source ready',()=>{
 const report=pure({readEvidence:path=>path==='lib/state.dart'?
  'class NotesState {}':fakeRead(path)});
 assert.equal(report.sourceTracePassed,false);
 assert.ok(report.operations[0].issues.includes('FLOW_LINK_NOT_FOUND:repository->state'));
});
test('RC213 W5 rejects operation missing from active external catalog',()=>{
 const report=pure({contract:{operations:[]}});
 assert.ok(report.operations[0].issues.includes('OPERATION_NOT_IN_ACTIVE_BACKEND_CONTRACT'));
});
test('RC213 W5 rejects a rewritten HTTP method/path',()=>{
 const bad=flow();bad.method='PATCH';
 assert.ok(pure({flows:[bad]}).operations[0].issues.includes('OPERATION_METHOD_PATH_MISMATCH'));
});
test('RC213 W5 rejects an operation not explicitly bound to selected external feature',()=>{
 const r=pure({externalBindings:{bindings:{notifications:{}}}});
 assert.ok(r.operations[0].issues.includes('EXTERNAL_OPERATION_NOT_FEATURE_BOUND'));
});
test('RC213 W5 refuses a server-owned feature posing as a client-only flow',()=>{
 const candidate=flow('auth','client');
 assert.ok(pure({selected:['auth'],flows:[candidate]}).operations[0].issues.includes(
  'SERVER_FEATURE_CANNOT_PRETEND_TO_BE_CLIENT_ONLY'));
});
test('RC213 W5 permits genuine local-only Deeplinks without inventing a Backend endpoint',()=>{
 const r=pure({selected:['deeplinks'],flows:[flow('deeplinks','client')]});
 assert.equal(r.sourceTracePassed,true,JSON.stringify(r));
});
test('RC213 W5 rejects missing typed DTO, permissions and error-case declarations',()=>{
 const bad=flow();delete bad.dto;bad.permissionCases=[];bad.errorCases=[];
 const r=pure({flows:[bad]});
 for(const code of ['TYPED_DTO_EVIDENCE_MISSING','PERMISSION_CASES_NOT_DECLARED','ERROR_CASES_NOT_DECLARED'])
  assert.ok(r.operations[0].issues.includes(code),code);
});
test('RC213 W5 rejects duplicate operation evidence and selected features without flows',()=>{
 const dup=pure({flows:[flow(),flow()]});
 assert.equal(dup.sourceTracePassed,false);
 assert.ok(dup.issues.some(x=>x.includes('W5_DUPLICATE_OPERATION_FLOW')));
 const empty=pure({flows:[]});
 assert.ok(empty.features[0].issues.includes('SELECTED_FEATURE_HAS_NO_FLOW_EVIDENCE'));
});
test('RC213 W5 actual filesystem audit source pass never certifies native/provider E2E',t=>{
 const f=fixture(t);
 const report=auditW5FeatureFlows(f.root);
 assert.equal(report.sourceTracePassed,true,JSON.stringify(report));
 assert.equal(report.independentContractPinVerified,false);
 assert.equal(report.productionApproved,false);
});
test('RC213 safe file reader rejects symlinks instead of reading external secrets',t=>{
 const f=fixture(t);
 f.write('secret.txt','secret');
 symlinkSync(join(f.root,'secret.txt'),join(f.root,'lib','linked.dart'));
 assert.throws(()=>readSafeFeatureEvidence(f.root,'lib/linked.dart'),/W5_EVIDENCE_SYMLINK/);
 assert.equal(hasSafeFeatureEvidence(f.root,'lib/linked.dart'),false);
});
test('RC213 actual W5 flow rejects symlinked source evidence, even if content has the expected symbol',t=>{
 const f=fixture(t),src=join(f.root,'lib/repository.dart');
 rmSync(src);
 symlinkSync(join(f.root,'lib/state.dart'),src);
 const result=auditW5FeatureFlows(f.root);
 assert.equal(result.sourceTracePassed,false);
 assert.ok(result.operations[0].issues.includes('FLOW_STAGE_FILE_UNSAFE_OR_MISSING:repository'));
});
test('RC213 detects stale external catalog integrity instead of accepting a forged operation',t=>{
 const f=fixture(t);
 const json=JSON.parse(readFileSync(join(f.root,'assets/contracts/external-operations.json')));
 json.operations[0].method='POST';
 f.write('assets/contracts/external-operations.json',json);
 const result=auditW5FeatureFlows(f.root);
 assert.equal(result.sourceTracePassed,false);
 assert.ok(result.sourceIssues.includes('EXTERNAL_CATALOG_INVALID_OR_UNVERIFIED'));
});
test('RC213 W5 with no per-operation ledger is blocked for the selected feature',t=>{
 const f=fixture(t);
 rmSync(join(f.root,'.fable/w5-operation-flows.json'));
 const report=auditW5FeatureFlows(f.root);
 assert.equal(report.sourceTracePassed,false);
 assert.equal(report.counts.blocked,1);
});
test('RC213 W5 blocks a selected backend feature missing its full required-operation scope',()=>{
 const r=pure({requirements:{features:{}}});
 assert.equal(r.sourceTracePassed,false);
 assert.ok(r.features[0].issues.includes('W5_PROJECT_OPERATION_SCOPE_NOT_DECLARED'));
});
test('RC213 W5 catches a declared second operation without a source implementation chain',()=>{
 const r=pure({requirements:{features:{notifications:{needsBackend:true,
  operations:[{operationId:ID,method:'GET',path:'/notes'},
    {operationId:'external.notes.delete',method:'DELETE',path:'/notes/{id}'}],
 }}}});
 assert.equal(r.sourceTracePassed,false);
 assert.ok(r.features[0].issues.includes('W5_REQUIRED_OPERATION_UNTRACED:external.notes.delete'));
});
test('RC213 W5 rejects extra Backend operation evidence outside the approved scope',()=>{
 const f=flow();f.operationId='external.notes.delete';f.method='DELETE';f.path='/notes/{id}';
 const r=pure({flows:[flow(),f]});
 assert.equal(r.sourceTracePassed,false);
 assert.ok(r.features[0].issues.some(x=>x.includes('W5_UNDECLARED_BACKEND_OPERATION:external.notes.delete')));
});
test('RC213 W5 rejects a manual needsBackend:false override for server-owned auth',()=>{
 const f=flow('auth','client');
 const r=pure({selected:['auth'],flows:[f],requirements:{features:{auth:{
  needsBackend:false,operations:[]}}}});
 assert.ok(r.features[0].issues.includes('W5_SERVER_FEATURE_BACKEND_SCOPE_REQUIRED'));
});
test('RC213 W5 CLI never accepts half of an independent Fable pin',()=>{
 assert.throws(()=>parseW5Args(['--expected-project-id','x']),/Both independent/);
 assert.throws(()=>parseW5Args(['--expected-project-id','x',
  '--expected-contract-hash','bad']),/64 lowercase/);
});

import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {renderTypedFeature} from '../tools/render-typed-feature-rc116.mjs';

const SHA='a'.repeat(64),H='b'.repeat(64),PRE='c'.repeat(64);
const pathOf=id=>'packages/features/fable_notes_ci/lib/src/data/fable_'+
  id.replaceAll('.','_')+'_repository.dart';
const base={
  className:'NotesCiGet',operationId:'notes_ci.get',method:'GET',
  path:'/notes_ci/:id',params:['id'],resultKind:'single',contractHash:H,
  fields:[{name:'id',type:'String',uuid:true,required:true}],
  bodyFields:[],sortFields:[],
};
const generate=op=>renderTypedFeature({
  featureId:'notes_ci',projectId:'rc371-test-project',
  contractHash:SHA,operations:[op],
});
test('RC371 signed UUID GET path is checked before the gateway dispatch',()=>{
  const op={...base,pathParamKinds:[{name:'id',type:'uuid'}]};
  const files=generate(op),repository=files.get(pathOf(op.operationId));
  assert.ok(repository);
  assert.match(repository,/The signed Backend\/OpenAPI path declares a UUID/);
  assert.match(repository,/RegExp\(r"\^\[a-fA-F0-9\]\{8\}/);
  assert.ok(repository.indexOf('if(!RegExp(r"^[a-fA-F0-9]{8}') <
    repository.indexOf('final response=await gateway.execute'));
  assert.match(repository,/TypedReadFailureKind.invalidInput/);
  const evidence=JSON.parse(files.get(
    'packages/features/fable_notes_ci/.fable-operation-evidence.json'));
  assert.deepEqual(evidence.operations[0].pathParamKinds,[{name:'id',type:'uuid'}]);
});
test('RC371 signed text path remains text; never guess it is a UUID',()=>{
  const op={...base,path:'/notes_ci/:slug',params:['slug'],
    pathParamKinds:[{name:'slug',type:'string'}]};
  const repo=generate(op).get(pathOf(op.operationId));
  assert.ok(repo);
  assert.match(repo,/slug\.trim\(\)\.isEmpty/);
  assert.doesNotMatch(repo,/The signed Backend\/OpenAPI path declares a UUID/);
  assert.doesNotMatch(repo,/hasMatch\(slug\)/);
});
test('RC371 malformed signed path-kind plan fails before rendering any package',()=>{
  for(const invalid of [
    [{name:'id',type:'number'}],
    [{name:'elsewhere',type:'uuid'}],
    [{name:'id',type:'uuid'},{name:'id',type:'uuid'}],
    [],
    'id-uuid',
  ]){
    assert.throws(()=>generate({...base,pathParamKinds:invalid}),
      /RC371 path parameter kinds/,JSON.stringify(invalid));
  }
});
for(const method of ['PATCH','DELETE']){
  test('RC371 '+method+' compares signed fresh-read UUID without case confusion',()=>{
    const op={...base,
      operationId:'notes_ci.'+(method==='PATCH'?'update':'delete'),
      className:'NotesCi'+(method==='PATCH'?'Update':'Delete'),
      method,resultKind:method==='DELETE'?'confirmed-delete':'single',
      fields:method==='DELETE'?[]:base.fields,
      bodyFields:method==='PATCH'
        ?[{name:'title',type:'String',required:false,maxLength:191}]:[],
      pathParamKinds:[{name:'id',type:'uuid'}],
      preconditionRead:{operationId:'notes_ci.get',contractHash:PRE,
        path:'/notes_ci/:id'},
    };
    const repo=generate(op).get(pathOf(op.operationId));
    assert.ok(repo);
    assert.match(repo,/result\["data"\]\["id"\] is! String/);
    assert.match(repo,/\(result\["data"\]\["id"\] as String\)\.toLowerCase\(\)!=id\.toLowerCase\(\)/);
    assert.ok(repo.indexOf('final fresh=await gateway.execute') <
      repo.indexOf('final ifMatch=etag.substring'));
  });
}
test('RC371 planner obtains path types only from independently signed Backend operation',()=>{
  const planner=readFileSync(
    new URL('../tools/plan-typed-feature-rc116.mjs',import.meta.url),'utf8');
  assert.match(planner,/sourceParams=op\.request\?\.params/);
  assert.match(planner,/\['string','uuid'\]\.includes\(p\.type\)/);
  assert.match(planner,/pathParamKinds=params\.map\(name=>/);
  assert.match(planner,/type:sourceParams\.find\(p=>p\.name===name\)\.type/);
});

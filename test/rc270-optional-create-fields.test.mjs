import test from 'node:test';
import assert from 'node:assert/strict';
import {planTypedFeature} from '../tools/plan-typed-feature-rc116.mjs';
import {renderTypedFeature} from '../tools/render-typed-feature-rc116.mjs';

function fixture(){
  const id='orders_ci.record.create';
  const route='/orders/records';
  const responseFields=[
    {name:'id',type:'uuid',optional:false},
    {name:'title',type:'string',optional:false},
  ];
  return {
    featureId:'orders_ci',
    contract:{
      kind:'fable.client-contract',
      project:{id:'signed-project'},
      contractHash:'a'.repeat(64),
      operations:[{
        operationId:id,method:'POST',path:route,feature:'orders_ci',
        public:false,permissions:['orders.create'],contractHash:'b'.repeat(64),
        request:{params:[],query:[],headers:[],body:{type:'object',fields:[
          {name:'title',type:'string',optional:false},
          {name:'notes',type:'text',optional:true},
          {name:'parentId',type:'uuid',optional:true},
        ]}},
        response:{kind:'fable-success-envelope',
          data:{type:'object',fields:responseFields}},
      }],
    },
    openapi:{
      openapi:'3.1.0',
      paths:{[route]:{post:{
        operationId:id,'x-fable-contract-hash':'b'.repeat(64),
        'x-fable-public':false,
        security:[{bearerAuth:[]}],
        parameters:[],
        requestBody:{required:true,content:{'application/json':{
          schema:{type:'object',additionalProperties:false,properties:{
            title:{type:'string'},
            notes:{type:'string'},
            parentId:{type:'string',format:'uuid'},
          },required:['title']},
        }}},
        responses:{'201':{content:{'application/json':{
          schema:{type:'object',properties:{
            success:{const:true},
            data:{type:'object',properties:{
              id:{type:'string',format:'uuid'},
              title:{type:'string'},
            },required:['id','title']},
          },required:['success','data']},
        }}}},
      }}},
    },
    requirements:{
      kind:'fable.feature-integration-requirements',schemaVersion:1,
      features:{orders_ci:{needsBackend:true,
        operations:[{operationId:id,method:'POST',path:route}]}},
    },
    selectedFeatures:['orders_ci'],
  };
}

test('RC270 generates nullable optional DTO and omits untouched fields on create',()=>{
  const plan=planTypedFeature(fixture());
  assert.deepEqual(plan.operations[0].bodyFields.map(f=>[f.name,f.required]),[
    ['title',true],['notes',false],['parentId',false],
  ]);
  const files=renderTypedFeature(plan);
  const p='packages/features/fable_orders_ci/';
  const body=files.get(p+'lib/src/data/orders_ci_record_create_create_request.dart');
  const port=files.get(p+'lib/src/domain/orders_ci_record_create_repository.dart');
  const useCase=files.get(p+'lib/src/application/orders_ci_record_create_use_case.dart');
  const ui=files.get(p+'lib/src/presentation/orders_ci_record_create_page.dart');
  assert.match(body,/required this\.title, this\.notes, this\.parentId/);
  assert.match(body,/final String\? notes;/);
  assert.match(body,/final String\? parentId;/);
  assert.match(body,/if\(notes!=null\) "notes": notes/);
  assert.match(body,/if\(parentId!=null\) "parentId": parentId/);
  assert.match(body,/parentId!=null && !RegExp/);
  assert.match(port,/create\(\{required String title, String\? notes, String\? parentId\}\)/);
  assert.match(useCase,/call\(\{required String title, String\? notes, String\? parentId\}\)/);
  assert.doesNotMatch(useCase,/if\(notes\.trim\(\)\.isEmpty\)/);
  assert.match(ui,/notes: \(_notes\.text\.trim\(\)\.isEmpty\?null:_notes\.text\.trim\(\)\)/);
  assert.match(ui,/parentId: \(_parentId\.text\.trim\(\)\.isEmpty\?null:_parentId\.text\.trim\(\)\)/);
  assert.match(ui,/state is OrdersCiRecordCreateReady \|\| state is OrdersCiRecordCreateFailed/);
  assert.match(ui,/Check Backend, then start a new create/);
  assert.match(ui,/_controller\.invalidate\(\)/);
  assert.match(ui,/before attempting another create, check the Backend state/i);
  assert.doesNotMatch(ui,/package:fable_core|Dio|dynamic/);
});

test('RC270 rejects optional-field drift between source signature and OpenAPI',()=>{
  const changes=[
    f=>{f.contract.operations[0].request.body.fields[1].optional=false;},
    f=>{f.openapi.paths['/orders/records'].post.requestBody.content['application/json'].schema.required.push('notes');},
    f=>{f.contract.operations[0].request.body.fields.pop();},
    f=>{f.openapi.paths['/orders/records'].post.requestBody.content['application/json'].schema.properties.parentId.format='date-time';},
    f=>{f.openapi.paths['/orders/records'].post.requestBody.content['application/json'].schema.required=[];},
    f=>{f.openapi.paths['/orders/records'].post.requestBody.content['application/json'].schema.required.push('unknownField');},
    f=>{f.contract.operations[0].request.body.fields[1].protectedAuth=true;},
  ];
  for(const change of changes){
    const source=fixture();
    change(source);
    assert.throws(()=>planTypedFeature(source),/RC116 typed feature/);
  }
});

test('RC270 keeps legacy fully required create and signed GET behavior valid',()=>{
  const p=fixture();
  p.contract.operations[0].request.body.fields.splice(1);
  const schema=p.openapi.paths['/orders/records'].post.requestBody.content['application/json'].schema;
  delete schema.properties.notes;
  delete schema.properties.parentId;
  const plan=planTypedFeature(p);
  assert.equal(plan.operations[0].bodyFields.length,1);
  assert.equal(plan.operations[0].bodyFields[0].required,true);
  const body=renderTypedFeature(plan).get('packages/features/fable_orders_ci/lib/src/data/orders_ci_record_create_create_request.dart');
  assert.match(body,/required this\.title/);
  assert.doesNotMatch(body,/String\?/);
});

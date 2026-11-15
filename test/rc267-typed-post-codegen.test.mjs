import test from 'node:test';
import assert from 'node:assert/strict';
import {planTypedFeature} from '../tools/plan-typed-feature-rc116.mjs';
import {renderTypedFeature} from '../tools/render-typed-feature-rc116.mjs';

const projectHash='a'.repeat(64);
const signedHash='b'.repeat(64);
function fixture(){
  const operationId='orders_ci.record.create';
  const path='/orders/records';
  const dataSchema={type:'object',properties:{
    id:{type:'string'},title:{type:'string'},
  },required:['id','title']};
  const response={type:'object',properties:{
    success:{const:true},data:dataSchema,
  },required:['success','data']};
  return {
    featureId:'orders_ci',
    contract:{
      kind:'fable.client-contract',project:{id:'source-test-project'},
      contractHash:projectHash,operations:[{
        operationId,method:'POST',path,feature:'orders_ci',
        public:false,permissions:['orders.create'],contractHash:signedHash,
        request:{params:[],body:{type:'object',fields:[
          {name:'title',type:'string',optional:false},
        ]}},
        response:{kind:'fable-success-envelope',
          data:{type:'object',fields:[
            {name:'id',type:'string',optional:false},
            {name:'title',type:'string',optional:false},
          ]}},
      }],
    },
    openapi:{openapi:'3.1.0',paths:{[path]:{post:{
      operationId,'x-fable-public':false,
      'x-fable-contract-hash':signedHash,
      security:[{bearerAuth:[]}],
      parameters:[],
      requestBody:{required:true,content:{'application/json':{
        schema:{type:'object',additionalProperties:false,
          properties:{title:{type:'string',minLength:1,maxLength:191}},
          required:['title']},
      }}},
      responses:{'201':{content:{'application/json':{schema:response}}}},
    }}}},
    requirements:{
      kind:'fable.feature-integration-requirements',schemaVersion:1,
      features:{orders_ci:{needsBackend:true,
        operations:[{operationId,method:'POST',path}]}},
    },
    selectedFeatures:['orders_ci'],
  };
}

test('RC267 signed create POST has a typed request, confirmed screen and no generic write transport',()=>{
  const plan=planTypedFeature(fixture());
  assert.equal(plan.operations[0].method,'POST');
  assert.deepEqual(plan.operations[0].bodyFields.map(f=>f.name),['title']);
  const files=renderTypedFeature(plan);
  const root='packages/features/fable_orders_ci/';
  const req=files.get(root+'lib/src/data/orders_ci_record_create_create_request.dart');
  const repo=files.get(root+'lib/src/data/fable_orders_ci_record_create_repository.dart');
  const port=files.get(root+'lib/src/domain/orders_ci_record_create_repository.dart');
  const controller=files.get(root+'lib/src/presentation/orders_ci_record_create_controller.dart');
  const page=files.get(root+'lib/src/presentation/orders_ci_record_create_page.dart');
  const navigation=files.get(root+'lib/src/project_feature.dart');
  const testSource=files.get(root+'test/orders_ci_record_create_page_test.dart');
  assert.match(req,/class OrdersCiRecordCreateCreateRequest/);
  assert.match(req,/title.length>191/);
  assert.match(req,/\"title\": title/);
  assert.match(repo,/gateway.execute\(\"orders_ci.record.create\",body:/);
  assert.match(repo,/op.method!=\"POST\"/);
  assert.match(repo,/gateway.session.identityRevision!=identity/);
  assert.match(port,/create\(\{required String title\}\)/);
  assert.match(controller,/Future<void> submit\(\{required String title\}\)/);
  assert.match(page,/Confirm record creation/);
  assert.match(page,/originalIdentity!=_identityEpoch/);
  assert.match(page,/verify Backend before retry/);
  assert.doesNotMatch(page,/package:fable_core|Dio|Map<String,dynamic>/);
  assert.match(navigation,/op0.method!=\"POST\"/);
  assert.match(testSource,/await tester.tap\(find.text\(\"Confirm create\"\)\)/);
});

test('RC267 rejects unsigned, ambiguous, dangerous or unsupported create operations',()=>{
  const changes=[
    f=>{f.contract.operations[0].contractHash='c'.repeat(64);},
    f=>{f.openapi.paths['/orders/records'].post.security=[];},
    f=>{f.openapi.paths['/orders/records'].post.requestBody.required=false;},
    f=>{f.openapi.paths['/orders/records'].post.requestBody.content['application/json'].schema.additionalProperties=true;},
    f=>{f.openapi.paths['/orders/records'].post.requestBody.content['application/json'].schema.properties.title.type='number';},
    f=>{f.openapi.paths['/orders/records'].post.requestBody.content['application/json'].schema.properties.title.maxLength=2000;},
    f=>{f.contract.operations[0].request.body.fields[0].name='userId';},
    f=>{f.contract.operations[0].request.body.fields[0].optional=true;},
    f=>{f.contract.operations[0].request.body.fields[0].type='json';},
    f=>{f.contract.operations[0].permissions=[];},
    f=>{f.requirements.features.orders_ci.operations[0].method='PATCH';},
    f=>{f.contract.operations[0].method='DELETE';},
    f=>{f.contract.operations[0].feature='payments';},
    f=>{f.contract.operations[0].path='/orders/payments';f.requirements.features.orders_ci.operations[0].path='/orders/payments';},
  ];
  for(const change of changes){
    const f=fixture();change(f);
    assert.throws(()=>planTypedFeature(f),/RC116 typed feature/);
  }
});

test('RC267 never enables POST for auth, payments or unselected features',()=>{
  for(const feature of ['auth','payments','access_control','biometrics']){
    const f=fixture();
    f.featureId=feature;
    f.contract.operations[0].feature=feature;
    f.requirements.features={[feature]:f.requirements.features.orders_ci};
    f.selectedFeatures=[feature];
    assert.throws(()=>planTypedFeature(f),/RC116 typed feature/);
  }
  const f=fixture();
  f.selectedFeatures=[];
  assert.throws(()=>planTypedFeature(f),/RC116 typed feature/);
});

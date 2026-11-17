import test from 'node:test';
import assert from 'node:assert/strict';
import {planTypedFeature} from '../tools/plan-typed-feature-rc116.mjs';
import {renderTypedFeature} from '../tools/render-typed-feature-rc116.mjs';

const hash='a'.repeat(64),opHash='b'.repeat(64);
const root='packages/features/fable_pricing_ci/';
function fixture() {
  const path='/pricing_ci',operationId='pricing_ci.item.get';
  const data={type:'object',properties:{
    amount:{type:'string'},title:{type:'string'},
  },required:['amount','title']};
  return {
    featureId:'pricing_ci',selectedFeatures:['pricing_ci'],
    contract:{kind:'fable.client-contract',contractHash:hash,
      project:{id:'source-only-decimal'},
      operations:[{
        operationId,method:'GET',path,feature:'pricing_ci',
        public:false,contractHash:opHash,permissions:['pricing_ci.read'],
        request:{params:[],query:[],headers:[]},
        response:{kind:'fable-success-envelope',data:{
          type:'object',fields:[
            {name:'amount',type:'decimal',optional:false},
            {name:'title',type:'string',optional:false},
          ],
        }},
      }],
    },
    openapi:{openapi:'3.1.0',paths:{[path]:{get:{
      operationId,'x-fable-contract-hash':opHash,'x-fable-public':false,
      security:[{bearerAuth:[]}],parameters:[],
      responses:{'200':{content:{'application/json':{schema:{
        type:'object',properties:{success:{const:true},data},required:['success','data'],
      }}}}},
    }}}},
    requirements:{kind:'fable.feature-integration-requirements',schemaVersion:1,
      features:{pricing_ci:{needsBackend:true,operations:[{operationId,method:'GET',path}]}}},
  };
}
test('RC336 only source-signed Decimal response fields produce exact String values',()=>{
  const plan=planTypedFeature(fixture());
  const fields=plan.operations[0].fields;
  assert.deepEqual(fields.map(f=>({name:f.name,type:f.type,decimal:f.decimal??false})),[
    {name:'amount',type:'String',decimal:true},
    {name:'title',type:'String',decimal:false},
  ]);
  const files=renderTypedFeature(plan);
  const entity=files.get(root+'lib/src/domain/pricing_ci_item_get_entity.dart');
  const dto=files.get(root+'lib/src/data/pricing_ci_item_get_dto.dart');
  const sample=files.get(root+'test/pricing_ci_item_get_dto_test.dart');
  assert.match(entity,/final String amount;/);
  assert.match(dto,/if\(amount is! String\)/);
  assert.match(dto,/Invalid amount exact Decimal field/);
  assert.match(dto,/RegExp\(r"\^-\?/);
  assert.match(dto,/e\[\+-\]\?/);
  assert.doesNotMatch(dto,/amount\.toDouble\(\)|num\.parse\(amount\)|double\.parse\(amount\)/);
  assert.match(sample,/"amount": "19\.99"/);
});
test('RC336 mismatched OpenAPI number or unsigned Decimal claim fails closed',()=>{
  const negativeNumber=fixture();
  negativeNumber.openapi.paths['/pricing_ci'].get.responses['200']
    .content['application/json'].schema.properties.data.properties.amount={type:'number'};
  assert.throws(()=>planTypedFeature(negativeNumber),/RC116 typed feature/);
  const negativeString=fixture();
  negativeString.contract.operations[0].response.data.fields[0].type='int';
  assert.throws(()=>planTypedFeature(negativeString),/RC116 typed feature/);
  const missing=fixture();
  delete missing.openapi.paths['/pricing_ci'].get.responses['200']
    .content['application/json'].schema.properties.data.properties.amount;
  assert.throws(()=>planTypedFeature(missing),/RC116 typed feature/);
});
test('RC336 generated list items preserve source-signed Decimal without precision loss',()=>{
  const op={
    operationId:'pricing_ci.list.unpaginated',method:'GET',path:'/pricing_ci/all',
    contractHash:opHash,className:'PricingCiListUnpaginated',
    fields:[{name:'amount',type:'String',required:true,decimal:true}],
    params:[],bodyFields:[],resultKind:'unpaginated-list',
    supportsSearch:false,filters:[],sortFields:[],
  };
  const files=renderTypedFeature({
    featureId:'pricing_ci',projectId:'source-only-decimal',contractHash:hash,
    operations:[op],
  });
  const entity=files.get(root+'lib/src/domain/pricing_ci_list_unpaginated_entity.dart');
  const dto=files.get(root+'lib/src/data/pricing_ci_list_unpaginated_dto.dart');
  assert.match(entity,/final String amount;/);
  assert.match(dto,/Invalid amount exact Decimal field/);
  assert.doesNotMatch(dto,/toDouble\(\)/);
  assert.match(dto,/amount is! String/);
});

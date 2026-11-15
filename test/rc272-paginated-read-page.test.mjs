import test from 'node:test';
import assert from 'node:assert/strict';
import {planTypedFeature} from '../tools/plan-typed-feature-rc116.mjs';
import {renderTypedFeature} from '../tools/render-typed-feature-rc116.mjs';

function fixture(){
  const id='catalog.list.paginated',path='/catalog';
  const signedQuery=[
    {key:'page',type:'integer',minimum:1},
    {key:'limit',type:'integer',minimum:1,maximum:100},
    {key:'mode',type:'string',enum:['page','search']},
    {key:'q',type:'string'},
  ];
  const metadata={
    oneOf:[
      {type:'object',properties:{
        mode:{const:'page'},page:{type:'integer'},limit:{type:'integer'},
        total:{type:'integer'},totalPages:{type:'integer'},
      },required:['mode','page','limit','total','totalPages']},
      {type:'object',properties:{
        mode:{const:'search'},limit:{type:'integer'},count:{type:'integer'},
      },required:['mode','limit','count']},
    ],
  };
  const items={type:'array',items:{type:'object',properties:{
    id:{type:'string',format:'uuid'},title:{type:'string'},
  },required:['id','title']}};
  return {
    featureId:'catalog',selectedFeatures:['catalog'],
    contract:{kind:'fable.client-contract',project:{id:'signed-test-project'},
      contractHash:'a'.repeat(64),operations:[{
        operationId:id,method:'GET',path,feature:'catalog',
        public:false,permissions:['catalog.list.paginated'],
        contractHash:'b'.repeat(64),
        request:{params:[],query:signedQuery,headers:[]},
        response:{kind:'fable-success-envelope',data:{
          type:'list-result',
          item:{type:'object',fields:[
            {name:'id',type:'uuid',optional:false},
            {name:'title',type:'string',optional:false},
          ]},
          meta:{modes:['page','search'],
            page:{page:'integer',limit:'integer',total:'integer',totalPages:'integer'},
            search:{limit:'integer',count:'integer'}},
        }},
      }]},
    openapi:{openapi:'3.1.0',paths:{[path]:{get:{
      operationId:id,'x-fable-public':false,
      'x-fable-contract-hash':'b'.repeat(64),
      security:[{bearerAuth:[]}],
      parameters:signedQuery.map(q=>({
        name:q.key,in:'query',required:false,schema:{
          type:q.type,...(q.minimum!==undefined?{minimum:q.minimum}:{}),
          ...(q.maximum!==undefined?{maximum:q.maximum}:{}),
          ...(q.enum!==undefined?{enum:q.enum}:{}),
        },
      })),
      responses:{'200':{content:{'application/json':{schema:{
        type:'object',properties:{
          success:{const:true},
          data:{type:'object',properties:{items,meta:metadata},
            required:['items','meta']},
        },required:['success','data'],
      }}}}},
    }}}},
    requirements:{kind:'fable.feature-integration-requirements',
      schemaVersion:1,features:{catalog:{needsBackend:true,
        operations:[{operationId:id,method:'GET',path}]}}},
  };
}

test('RC272 emits signed page-mode query, typed page metadata and previous/next UI',()=>{
  const plan=planTypedFeature(fixture());
  assert.equal(plan.operations[0].resultKind,'paginated-list');
  const files=renderTypedFeature(plan),prefix='packages/features/fable_catalog/';
  const port=files.get(prefix+'lib/src/domain/catalog_list_paginated_repository.dart');
  const useCase=files.get(prefix+'lib/src/application/catalog_list_paginated_use_case.dart');
  const adapter=files.get(prefix+'lib/src/data/fable_catalog_list_paginated_repository.dart');
  const entity=files.get(prefix+'lib/src/domain/catalog_list_paginated_entity.dart');
  const dto=files.get(prefix+'lib/src/data/catalog_list_paginated_dto.dart');
  const page=files.get(prefix+'lib/src/presentation/catalog_list_paginated_page.dart');
  const widget=files.get(prefix+'test/catalog_list_paginated_page_test.dart');
  const dtoTest=files.get(prefix+'test/catalog_list_paginated_dto_test.dart');
  assert.match(port,/load\(\{required int page\}\)/);
  assert.match(useCase,/page<1 \|\| page>100000/);
  assert.match(adapter,/"page":page,"limit":20,"mode":"page"/);
  assert.match(adapter,/entity\.page!=page/);
  assert.match(dto,/meta\['mode'\]!='page'/);
  assert.match(dto,/meta\['totalPages'\] as int/);
  assert.match(dto,/input\.length>20/);
  assert.match(entity,/final int page,limit,total,totalPages/);
  assert.match(page,/Previous page/);
  assert.match(page,/Next page/);
  assert.match(page,/_page=1;/);
  assert.match(page,/state\.value\.page<state\.value\.totalPages/);
  assert.match(dtoTest,/"mode":"page","page":1,"limit":20/);
  assert.match(widget,/page:1,limit:20,total:1,totalPages:1/);
  assert.doesNotMatch(page,/Dio|package:fable_core|Map<String,dynamic>/);
});

test('RC272 refuses unsigned pagination, untrusted query binding and malformed page metadata',()=>{
  const mutations=[
    f=>{f.contract.operations[0].request.query[0].minimum=0;},
    f=>{f.contract.operations[0].request.query[1].maximum=1000;},
    f=>{f.openapi.paths['/catalog'].get.parameters[0].schema.type='string';},
    f=>{f.openapi.paths['/catalog'].get.parameters[2].schema.enum=['search'];},
    f=>{f.contract.operations[0].request.query.push({key:'secret',type:'string',required:true});},
    f=>{f.contract.operations[0].request.headers=['X-Admin'];},
    f=>{f.contract.operations[0].request.body={type:'object'};},
    f=>{f.contract.operations[0].response.data.meta.modes=['search'];},
    f=>{f.contract.operations[0].response.data.item.fields[1].type='boolean';},
    f=>{f.openapi.paths['/catalog'].get.responses['200'].content['application/json'].schema.properties.data.properties.meta.oneOf.splice(1);},
    f=>{f.openapi.paths['/catalog'].get.responses['200'].content['application/json'].schema.properties.data.properties.meta.oneOf[0].properties.total.type='number';},
    f=>{f.openapi.paths['/catalog'].get.responses['200'].content['application/json'].schema.properties.data.properties.meta.oneOf[0].properties.mode.const='other';},
  ];
  for(const mutate of mutations){
    const f=fixture();mutate(f);
    assert.throws(()=>planTypedFeature(f),/RC116 typed feature/);
  }
});

test('RC272 preserves unpaginated and single-item reads in the same generator',()=>{
  const f=fixture(),op=f.contract.operations[0];
  op.operationId='catalog.item.get';
  op.request.query=[];
  op.response.data=op.response.data.item;
  const route=f.openapi.paths['/catalog'].get;
  route.operationId=op.operationId;route.parameters=[];
  route.responses['200'].content['application/json'].schema.properties.data=
    route.responses['200'].content['application/json'].schema.properties.data.properties.items.items;
  f.requirements.features.catalog.operations[0].operationId=op.operationId;
  const plan=planTypedFeature(f),files=renderTypedFeature(plan);
  assert.equal(plan.operations[0].resultKind,'single');
  const view=files.get('packages/features/fable_catalog/lib/src/presentation/catalog_item_get_page.dart');
  assert.match(view,/Authenticated source-bound GET/);
  assert.doesNotMatch(view,/Next page/);
});

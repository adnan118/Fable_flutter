import test from 'node:test';
import assert from 'node:assert/strict';
import {planTypedFeature} from '../tools/plan-typed-feature-rc116.mjs';
import {renderTypedFeature} from '../tools/render-typed-feature-rc116.mjs';

function fixture({newSearchMeta=true}={}){
  const id='catalog.list.paginated',path='/catalog';
  const q=[
    {key:'page',type:'integer',minimum:1},
    {key:'limit',type:'integer',minimum:1,maximum:100},
    {key:'mode',type:'string',enum:['page','search']},
    {key:'q',type:'string'},
  ];
  const sMeta=newSearchMeta
    ? {page:'integer',limit:'integer',total:'integer',totalPages:'integer',count:'integer'}
    : {limit:'integer',count:'integer'};
  const pageAlt={type:'object',properties:{
    mode:{const:'page'},page:{type:'integer'},limit:{type:'integer'},
    total:{type:'integer'},totalPages:{type:'integer'},
  },required:['mode','page','limit','total','totalPages']};
  const searchAlt={type:'object',properties:{
    mode:{const:'search'},
    ...Object.fromEntries(Object.keys(sMeta).map(k=>[k,{type:'integer'}])),
  },required:['mode',...Object.keys(sMeta)]};
  return {
    featureId:'catalog',selectedFeatures:['catalog'],
    contract:{kind:'fable.client-contract',project:{id:'signed-test-project'},
      contractHash:'a'.repeat(64),operations:[{
        operationId:id,method:'GET',path,feature:'catalog',
        public:false,permissions:['catalog.list.paginated'],
        contractHash:'b'.repeat(64),
        request:{params:[],query:q,headers:[]},
        response:{kind:'fable-success-envelope',data:{
          type:'list-result',
          item:{type:'object',fields:[
            {name:'id',type:'uuid',optional:false},
            {name:'title',type:'string',optional:false},
          ]},
          meta:{modes:['page','search'],
            page:{page:'integer',limit:'integer',total:'integer',totalPages:'integer'},
            search:sMeta,
          },
        }},
      }]},
    openapi:{openapi:'3.1.0',paths:{[path]:{get:{
      operationId:id,'x-fable-public':false,
      'x-fable-contract-hash':'b'.repeat(64),security:[{bearerAuth:[]}],
      parameters:q.map(x=>({name:x.key,in:'query',required:false,schema:{
        type:x.type,...(x.minimum!==undefined?{minimum:x.minimum}:{}),
        ...(x.maximum!==undefined?{maximum:x.maximum}:{}),
        ...(x.enum?{enum:x.enum}:{}),
      }})),
      responses:{'200':{content:{'application/json':{schema:{
        type:'object',properties:{
          success:{const:true},
          data:{type:'object',properties:{
            items:{type:'array',items:{type:'object',properties:{
              id:{type:'string',format:'uuid'},title:{type:'string'},
            },required:['id','title']}},
            meta:{oneOf:[pageAlt,searchAlt]},
          },required:['items','meta']},
        },required:['success','data'],
      }}}}},
    }}}},
    requirements:{kind:'fable.feature-integration-requirements',
      schemaVersion:1,features:{catalog:{needsBackend:true,
        operations:[{operationId:id,method:'GET',path}]}}},
  };
}


function filteredFixture(){
  const f=fixture();
  const op=f.contract.operations[0];
  op.response.data.item.fields.push(
    {name:'status',type:'string',optional:true},
    {name:'published',type:'boolean',optional:false});
  const route=f.openapi.paths['/catalog'].get;
  const schema=route.responses['200'].content['application/json']
    .schema.properties.data.properties.items.items;
  schema.properties.status={type:'string'};
  schema.properties.published={type:'boolean'};
  schema.required.push('published');
  op.request.query.push({key:'status',type:'string'},
    {key:'published',type:'string',enum:['true','false']});
  route.parameters.push(
    {name:'status',in:'query',required:false,schema:{type:'string'}},
    {name:'published',in:'query',required:false,
      schema:{type:'string',enum:['true','false']}});
  return f;
}

test('RC278 contract-signed text and boolean equality filters propagate across every infinite-scroll page',()=>{
  const plan=planTypedFeature(filteredFixture());
  const op=plan.operations[0];
  assert.deepEqual(op.filters,[{name:'status',type:'text'},
    {name:'published',type:'boolean'}]);
  const out=renderTypedFeature(plan),base='packages/features/fable_catalog/';
  const port=out.get(base+'lib/src/domain/catalog_list_paginated_repository.dart');
  const adapter=out.get(base+'lib/src/data/fable_catalog_list_paginated_repository.dart');
  const useCase=out.get(base+'lib/src/application/catalog_list_paginated_use_case.dart');
  const state=out.get(base+'lib/src/presentation/catalog_list_paginated_controller.dart');
  const ui=out.get(base+'lib/src/presentation/catalog_list_paginated_page.dart');
  const widgetTest=out.get(base+'test/catalog_list_paginated_page_test.dart');
  assert.match(port,/String\? status, String\? published/);
  assert.match(useCase,/status: status, published: published/);
  assert.match(adapter,/if\(status!=null && status.trim\(\).isNotEmpty\)"status":status.trim\(\)/);
  assert.match(adapter,/if\(published!=null && published.trim\(\).isNotEmpty\)"published":published.trim\(\)/);
  assert.match(adapter,/published.trim\(\)!="true" && published.trim\(\)!="false"/);
  assert.match(state,/_status=status\?\.trim\(\)/);
  assert.match(state,/search:_search,status:_status,published:_published/);
  assert.match(ui,/Exact filter: status/);
  assert.match(ui,/Exact filter: published/);
  assert.match(ui,/DropdownButtonFormField<String>/);
  assert.match(ui,/status:\(_filterstatus.text.trim\(\).isEmpty\?null:_filterstatus.text.trim\(\)\)/);
  assert.match(ui,/published:_filterpublished/);
  assert.match(widgetTest,/String\? status,String\? published/);
  assert.doesNotMatch(ui,/Dio|package:fable_core|Map<String,dynamic>/);
});

test('RC278 refuses query/schema drift and never generates controls for protected or unverified filters',()=>{
  const failures=[
    f=>{f.openapi.paths['/catalog'].get.parameters.at(-1).schema.enum=['maybe','true'];},
    f=>{f.contract.operations[0].request.query.at(-1).required=true;},
    f=>{f.openapi.paths['/catalog'].get.parameters.pop();},
  ];
  for(const change of failures){
    const f=filteredFixture();change(f);
    assert.throws(()=>planTypedFeature(f),/RC116 typed feature/);
  }
  const sensitive=filteredFixture();
  sensitive.contract.operations[0].response.data.item.fields.find(x=>x.name==='status').protectedAuth=true;
  sensitive.contract.operations[0].response.data.item.fields.find(x=>x.name==='published').sensitiveFilterSort=true;
  assert.deepEqual(planTypedFeature(sensitive).operations[0].filters,[]);
});

test('RC278 older signed Backend pagination remains unchanged without filter controls',()=>{
  const op=planTypedFeature(fixture()).operations[0];
  assert.deepEqual(op.filters,[]);
  const files=renderTypedFeature(planTypedFeature(fixture()));
  const page=files.get('packages/features/fable_catalog/lib/src/presentation/catalog_list_paginated_page.dart');
  assert.doesNotMatch(page,/Exact filter:/);
  assert.match(page,/ListView\.builder/);
});

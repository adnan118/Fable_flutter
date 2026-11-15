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

test('RC273 signed RC274 search + infinite scroll uses same operation across all pages',()=>{
  const plan=planTypedFeature(fixture());
  assert.equal(plan.operations[0].supportsSearch,true);
  const files=renderTypedFeature(plan),root='packages/features/fable_catalog/';
  const port=files.get(root+'lib/src/domain/catalog_list_paginated_repository.dart');
  const repo=files.get(root+'lib/src/data/fable_catalog_list_paginated_repository.dart');
  const dto=files.get(root+'lib/src/data/catalog_list_paginated_dto.dart');
  const controller=files.get(root+'lib/src/presentation/catalog_list_paginated_controller.dart');
  const page=files.get(root+'lib/src/presentation/catalog_list_paginated_page.dart');
  const widget=files.get(root+'test/catalog_list_paginated_page_test.dart');
  assert.match(port,/load\(\{required int page, String\? search\}\)/);
  assert.match(repo,/"mode":search!=null && search.trim\(\).isNotEmpty\?"search":"page"/);
  assert.match(repo,/if\(search!=null && search.trim\(\).isNotEmpty\)"q":search.trim\(\)/);
  assert.match(dto, /meta\['mode'\]!='search'/);
  assert.match(dto, /meta\['count'\]!=input.length/);
  assert.match(dto, /mode:meta\["mode"\]=="search"\?CatalogListPaginatedListMode.search:CatalogListPaginatedListMode.page/);
  assert.match(repo, /entity.mode!=requestedMode/);
  assert.match(repo, /Backend returned a different search mode/);
  const entity=files.get(root+'lib/src/domain/catalog_list_paginated_entity.dart');
  assert.match(entity,/enum CatalogListPaginatedListMode \{ page, search \}/);
  assert.match(entity,/required this.mode/);
  assert.match(widget,/mode:\(search!=null && search.isNotEmpty\?CatalogListPaginatedListMode.search:CatalogListPaginatedListMode.page\)/);
  assert.match(controller,/final List<CatalogListPaginatedItem> _items/);
  assert.match(controller,/_items\.addAll\(data.items\)/);
  assert.match(controller,/if\(_closed \|\| _epoch!=epoch\)return/);
  assert.match(controller,/void reset\(\{String search=""\}\)/);
  assert.match(controller,/_nextPage=requested\+1/);
  assert.match(page,/ScrollController _scroll=ScrollController/);
  assert.match(page,/ListView\.builder/);
  assert.match(page,/_scroll\.position\.extentAfter<400/);
  assert.match(page,/onSubmitted:\(_\)=>_refresh\(\)/);
  assert.match(page,/Search across all authorized records/);
  assert.match(page,/Retry failed page/);
  assert.doesNotMatch(page,/Previous page|Next page/);
  assert.match(widget,/repository\.searches,contains\("needle"\)/);
});

test('RC273 older signed search metadata still works for infinite page scrolling without unsafe search',()=>{
  const plan=planTypedFeature(fixture({newSearchMeta:false}));
  assert.equal(plan.operations[0].supportsSearch,false);
  const files=renderTypedFeature(plan);
  const prefix='packages/features/fable_catalog/';
  const repo=files.get(prefix+'lib/src/data/fable_catalog_list_paginated_repository.dart');
  const page=files.get(prefix+'lib/src/presentation/catalog_list_paginated_page.dart');
  assert.match(page,/ListView\.builder/);
  assert.doesNotMatch(page,/Search across all authorized records/);
  assert.match(repo,/"mode":"page"/);
  assert.match(repo,/entity.mode!=CatalogListPaginatedListMode.page/);
  assert.doesNotMatch(repo,/"q":search\.trim/);
});

test('RC273 rejects fake signed search paging and query parameter tampering',()=>{
  const mutations=[
    f=>{delete f.contract.operations[0].response.data.meta.search.total;},
    f=>{f.openapi.paths['/catalog'].get.responses['200'].content['application/json'].schema.properties.data.properties.meta.oneOf[1].properties.total.type='string';},
    f=>{f.openapi.paths['/catalog'].get.parameters.pop();},
    f=>{f.contract.operations[0].request.query.find(q=>q.key==='q').type='integer';},
    f=>{f.contract.operations[0].request.query.find(q=>q.key==='q').required=true;},
    f=>{f.contract.operations[0].request.headers.push('X-Admin');},
  ];
  for(const mutation of mutations){
    const f=fixture();mutation(f);
    assert.throws(()=>planTypedFeature(f),/RC116 typed feature/);
  }
});

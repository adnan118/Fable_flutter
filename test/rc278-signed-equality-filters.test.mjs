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

function numericRangeFixture({type='int'}={}){
  const f=fixture(),name='quantity';
  const signed=f.contract.operations[0];
  const route=f.openapi.paths['/catalog'].get;
  const items=route.responses['200'].content['application/json']
    .schema.properties.data.properties.items.items;
  signed.response.data.item.fields.push({name,type,optional:false});
  items.properties[name]={type:type==='int'?'integer':'number'};
  items.required.push(name);
  for(const key of [name,name+'Min',name+'Max']){
    signed.request.query.push({key,type:'number'});
    route.parameters.push({name:key,in:'query',required:false,
      schema:{type:'number'}});
  }
  return f;
}

test('RC280 signed integer range has atomic min/max filtering throughout infinite scroll',()=>{
  const plan=planTypedFeature(numericRangeFixture());
  assert.deepEqual(plan.operations[0].filters,[
    {name:'quantityMin',type:'int'},{name:'quantityMax',type:'int'}]);
  const out=renderTypedFeature(plan);
  const base='packages/features/fable_catalog/lib/src/';
  const port=out.get(base+'domain/catalog_list_paginated_repository.dart');
  const adapter=out.get(base+'data/fable_catalog_list_paginated_repository.dart');
  const state=out.get(base+'presentation/catalog_list_paginated_controller.dart');
  const page=out.get(base+'presentation/catalog_list_paginated_page.dart');
  const widgetTest=out.get('packages/features/fable_catalog/test/catalog_list_paginated_page_test.dart');
  assert.match(port,/String\? quantityMin, String\? quantityMax/);
  assert.match(adapter,/int\.tryParse\(quantityMin\.trim\(\)\)/);
  assert.match(adapter,/parsed < -2147483648 \|\| parsed > 2147483647/);
  assert.match(adapter,/double\.parse\(quantityMin\.trim\(\)\)>double\.parse\(quantityMax\.trim\(\)\)/);
  assert.match(adapter,/"quantityMin":quantityMin\.trim\(\)/);
  assert.match(adapter,/"quantityMax":quantityMax\.trim\(\)/);
  assert.match(state,/quantityMin:_quantityMin,quantityMax:_quantityMax/);
  assert.match(page,/Minimum: quantity/);
  assert.match(page,/Maximum: quantity/);
  assert.match(page,/TextInputType\.numberWithOptions\(signed:true,decimal:false\)/);
  assert.match(widgetTest,/String\? quantityMin,String\? quantityMax/);
  assert.doesNotMatch(page,/Map<String,dynamic>|Dio|package:fable_core/);
});

test('RC280 signed decimal filters require finite numbers and use decimal input',()=>{
  const plan=planTypedFeature(numericRangeFixture({type:'decimal'}));
  assert.deepEqual(plan.operations[0].filters,[
    {name:'quantityMin',type:'decimal'},{name:'quantityMax',type:'decimal'}]);
  const files=renderTypedFeature(plan),root='packages/features/fable_catalog/lib/src/';
  assert.match(files.get(root+'data/fable_catalog_list_paginated_repository.dart'),
    /double\.tryParse\(quantityMin\.trim\(\)\)/);
  assert.match(files.get(root+'data/fable_catalog_list_paginated_repository.dart'),/!parsed\.isFinite/);
  assert.match(files.get(root+'presentation/catalog_list_paginated_page.dart'),
    /TextInputType\.numberWithOptions\(signed:true,decimal:true\)/);
});

test('RC280 refuses missing, drifted and sensitive numeric range pairs',()=>{
  const missing=numericRangeFixture();
  missing.contract.operations[0].request.query.pop();
  missing.openapi.paths['/catalog'].get.parameters.pop();
  assert.deepEqual(planTypedFeature(missing).operations[0].filters,[]);
  const hidden=numericRangeFixture();
  hidden.contract.operations[0].response.data.item.fields.at(-1).protectedAuth=true;
  assert.deepEqual(planTypedFeature(hidden).operations[0].filters,[]);
  const changed=numericRangeFixture();
  changed.openapi.paths['/catalog'].get.parameters.at(-1).schema.type='string';
  assert.throws(()=>planTypedFeature(changed),/RC116 typed feature/);
  const unknown=numericRangeFixture();
  unknown.contract.operations[0].request.query.at(-1).type='string';
  unknown.openapi.paths['/catalog'].get.parameters.at(-1).schema.type='string';
  assert.deepEqual(planTypedFeature(unknown).operations[0].filters,[]);
});

function signedDateRangeFixture(){
  const f=fixture(),name='publishedAt';
  const signed=f.contract.operations[0];
  const route=f.openapi.paths['/catalog'].get;
  const items=route.responses['200'].content['application/json']
    .schema.properties.data.properties.items.items;
  signed.response.data.item.fields.push({name,type:'datetime',optional:false});
  items.properties[name]={type:'string',format:'date-time'};
  items.required.push(name);
  for(const key of [name,name+'From',name+'To']){
    signed.request.query.push({key,type:'string',format:'date-time'});
    route.parameters.push({name:key,in:'query',required:false,
      schema:{type:'string',format:'date-time'}});
  }
  return f;
}

test('RC281 fully signed datetime bounds generate real calendar controls and UTC inputs',()=>{
  const plan=planTypedFeature(signedDateRangeFixture());
  assert.deepEqual(plan.operations[0].filters,[
    {name:'publishedAtFrom',type:'datetime'},
    {name:'publishedAtTo',type:'datetime'}]);
  const files=renderTypedFeature(plan),base='packages/features/fable_catalog/lib/src/';
  const adapter=files.get(base+'data/fable_catalog_list_paginated_repository.dart');
  const controller=files.get(base+'presentation/catalog_list_paginated_controller.dart');
  const page=files.get(base+'presentation/catalog_list_paginated_page.dart');
  assert.match(adapter,/DateTime\.tryParse\(iso\)/);
  assert.match(adapter,/parsed\.toUtc\(\)\.toIso8601String\(\)!=iso/);
  assert.match(adapter,/DateTime\.parse\(publishedAtFrom\.trim\(\)\)\.isAfter/);
  assert.match(adapter,/"publishedAtFrom":publishedAtFrom\.trim\(\)/);
  assert.match(adapter,/"publishedAtTo":publishedAtTo\.trim\(\)/);
  assert.match(controller,/publishedAtFrom:_publishedAtFrom,publishedAtTo:_publishedAtTo/);
  assert.match(page,/showDatePicker\(context:context/);
  assert.match(page,/From: publishedAt/);
  assert.match(page,/To: publishedAt/);
  assert.match(page,/DateTime\.utc\(chosen\.year,chosen\.month,chosen\.day,0,0,0,0\)/);
  assert.match(page,/DateTime\.utc\(chosen\.year,chosen\.month,chosen\.day,23,59,59,999\)/);
  assert.match(page,/epoch!=_identityEpoch/);
  assert.doesNotMatch(page,/Dio|package:fable_core|Map<String,dynamic>/);
});

test('RC281 missing or unsafe date bounds never become generic filters',()=>{
  const noTo=signedDateRangeFixture();
  noTo.contract.operations[0].request.query.pop();
  noTo.openapi.paths['/catalog'].get.parameters.pop();
  assert.deepEqual(planTypedFeature(noTo).operations[0].filters,[]);
  const sensitive=signedDateRangeFixture();
  sensitive.contract.operations[0].response.data.item.fields.at(-1).sensitiveFilterSort=true;
  assert.deepEqual(planTypedFeature(sensitive).operations[0].filters,[]);
  const noFormat=signedDateRangeFixture();
  delete noFormat.contract.operations[0].request.query.at(-1).format;
  delete noFormat.openapi.paths['/catalog'].get.parameters.at(-1).schema.format;
  assert.deepEqual(planTypedFeature(noFormat).operations[0].filters,[]);
  const drift=signedDateRangeFixture();
  drift.openapi.paths['/catalog'].get.parameters.at(-1).schema.format='date';
  assert.throws(()=>planTypedFeature(drift),/RC116 typed feature/);
});

function signedSortFixture(){
  const f=fixture();
  const q={key:'sort',type:'string',sortAllowedFields:['title','createdAt']};
  f.contract.operations[0].request.query.push(q);
  f.openapi.paths['/catalog'].get.parameters.push({
    name:'sort',in:'query',required:false,schema:{type:'string'},
    'x-fable-sort-allowlist':['title','createdAt'],
  });
  return f;
}

test('RC282 signed sorting is passed to every page and resets Infinite Scroll',()=>{
  const p=planTypedFeature(signedSortFixture());
  const op=p.operations[0];
  assert.deepEqual(op.sortFields,['title','createdAt']);
  const files=renderTypedFeature(p),base='packages/features/fable_catalog/lib/src/';
  const adapter=files.get(base+'data/fable_catalog_list_paginated_repository.dart');
  const controller=files.get(base+'presentation/catalog_list_paginated_controller.dart');
  const page=files.get(base+'presentation/catalog_list_paginated_page.dart');
  const repository=files.get(base+'domain/catalog_list_paginated_repository.dart');
  const widgetTest=files.get('packages/features/fable_catalog/test/catalog_list_paginated_page_test.dart');
  assert.match(repository,/String\? sort/);
  assert.match(adapter,/sortAllowed=<String>\{"title","-title","createdAt","-createdAt"\}/);
  assert.match(adapter,/!sortAllowed\.contains\(sort\)/);
  assert.match(adapter,/if\(sort!=null && sort\.isNotEmpty\)"sort":sort/);
  assert.match(controller,/_sort=sort;/);
  assert.match(controller,/sort:_sort/);
  assert.match(page,/String\? _sort;/);
  assert.match(page,/Sort/);
  assert.match(page,/title ascending/);
  assert.match(page,/createdAt descending/);
  assert.match(page,/sort:_sort/);
  assert.match(page,/_sort=null;/);
  assert.match(widgetTest,/String\? sort/);
});

test('RC282 absent or divergent sortable allowlist fails closed',()=>{
  const legacy=fixture();
  assert.deepEqual(planTypedFeature(legacy).operations[0].sortFields,[]);
  const drift=signedSortFixture();
  drift.openapi.paths['/catalog'].get.parameters.at(-1)['x-fable-sort-allowlist']=['title'];
  assert.throws(()=>planTypedFeature(drift),/RC116 typed feature/);
  const missing=signedSortFixture();
  delete missing.openapi.paths['/catalog'].get.parameters.at(-1)['x-fable-sort-allowlist'];
  assert.throws(()=>planTypedFeature(missing),/RC116 typed feature/);
  const sensitive=signedSortFixture();
  sensitive.contract.operations[0].request.query.at(-1).sortAllowedFields=['password'];
  sensitive.openapi.paths['/catalog'].get.parameters.at(-1)['x-fable-sort-allowlist']=['password'];
  assert.deepEqual(planTypedFeature(sensitive).operations[0].sortFields,[]);
});

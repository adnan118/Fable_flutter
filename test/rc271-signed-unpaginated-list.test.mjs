import test from 'node:test';
import assert from 'node:assert/strict';
import {planTypedFeature} from '../tools/plan-typed-feature-rc116.mjs';
import {renderTypedFeature} from '../tools/render-typed-feature-rc116.mjs';

function listFixture(){
  const id='catalog.list.unpaginated',path='/catalog';
  const itemSchema={
    type:'object',properties:{
      id:{type:'string',format:'uuid'},
      title:{type:'string'},
      updatedAt:{type:'string',format:'date-time'},
    },required:['id','title'],
  };
  const dataSchema={
    type:'object',properties:{
      items:{type:'array',items:itemSchema},
      meta:{type:'object',properties:{
        mode:{const:'unpaginated'},
        count:{type:'integer'},
        maxRows:{type:'integer'},
        limitExceeded:{type:'boolean'},
      },required:['mode','count','maxRows','limitExceeded']},
    },required:['items','meta'],
  };
  return {
    featureId:'catalog',selectedFeatures:['catalog'],
    contract:{
      kind:'fable.client-contract',project:{id:'catalog-source-fixture'},
      contractHash:'a'.repeat(64),operations:[{
        operationId:id,method:'GET',path,feature:'catalog',
        public:false,permissions:['catalog.read'],contractHash:'b'.repeat(64),
        request:{params:[],query:[],headers:[]},
        response:{kind:'fable-success-envelope',data:{
          type:'list-result',
          item:{type:'object',fields:[
            {name:'id',type:'uuid',optional:false},
            {name:'title',type:'string',optional:false},
            {name:'updatedAt',type:'datetime',optional:true},
          ]},
          meta:{modes:['unpaginated'],unpaginated:{
            count:'integer',maxRows:'integer',limitExceeded:'boolean',
          }},
        }},
      }],
    },
    openapi:{openapi:'3.1.0',paths:{[path]:{get:{
      operationId:id,'x-fable-contract-hash':'b'.repeat(64),
      'x-fable-public':false,security:[{bearerAuth:[]}],
      parameters:[],
      responses:{'200':{content:{'application/json':{
        schema:{type:'object',properties:{
          success:{const:true},data:dataSchema,
        },required:['success','data']},
      }}}},
    }}}},
    requirements:{kind:'fable.feature-integration-requirements',
      schemaVersion:1,features:{catalog:{needsBackend:true,
        operations:[{operationId:id,method:'GET',path}]}}},
  };
}
test('RC271 signed unpaginated list produces typed immutable item DTO and navigable list UI',()=>{
  const plan=planTypedFeature(listFixture());
  assert.equal(plan.operations[0].resultKind,'unpaginated-list');
  assert.deepEqual(plan.operations[0].fields.map(f=>[f.name,f.required]),[
    ['id',true],['title',true],['updatedAt',false],
  ]);
  const files=renderTypedFeature(plan);
  const root='packages/features/fable_catalog/';
  const entity=files.get(root+'lib/src/domain/catalog_list_unpaginated_entity.dart');
  const dto=files.get(root+'lib/src/data/catalog_list_unpaginated_dto.dart');
  const adapter=files.get(root+'lib/src/data/fable_catalog_list_unpaginated_repository.dart');
  const page=files.get(root+'lib/src/presentation/catalog_list_unpaginated_page.dart');
  const dtoTest=files.get(root+'test/catalog_list_unpaginated_dto_test.dart');
  const pageTest=files.get(root+'test/catalog_list_unpaginated_page_test.dart');
  assert.match(entity,/final class CatalogListUnpaginatedItem/);
  assert.match(entity,/final List<CatalogListUnpaginatedItem> items/);
  assert.match(dto,/input\.length>5000/);
  assert.match(dto,/meta\['mode'\]!='unpaginated'/);
  assert.match(dto,/List<CatalogListUnpaginatedItem>\.unmodifiable\(items\)/);
  assert.match(adapter,/gateway\.session\.identityRevision!=identity/);
  assert.match(page,/state\.value\.items\.skip\(_rowOffset\)\.take\(100\)/);
  assert.match(page,/state\.value\.limitExceeded/);
  assert.match(page,/No records available/);
  assert.match(dtoTest,/json\.remove\("meta"\)/);
  assert.match(pageTest,/CatalogListUnpaginatedItem\(/);
  assert.doesNotMatch(page,/Dio|package:fable_core|Map<String,dynamic>/);
  assert.equal(files.has(root+'lib/src/project_feature.dart'),true);
});

test('RC271 refuses pagination, query, unsigned item drift and malformed metadata',()=>{
  const failures=[
    f=>{f.contract.operations[0].request.query=[{key:'page',type:'integer'}];},
    f=>{f.contract.operations[0].request.headers=['X-Domain'];},
    f=>{f.contract.operations[0].response.data.meta.modes=['page'];},
    f=>{f.contract.operations[0].response.data.meta.modes=['unpaginated','page'];},
    f=>{f.contract.operations[0].operationId='catalog.list.paginated';f.requirements.features.catalog.operations[0].operationId='catalog.list.paginated';f.openapi.paths['/catalog'].get.operationId='catalog.list.paginated';},
    f=>{f.contract.operations[0].response.data.item.fields[0].type='decimal';},
    f=>{f.openapi.paths['/catalog'].get.responses['200'].content['application/json'].schema.properties.data.properties.items.items.properties.id.format='date-time';},
    f=>{f.openapi.paths['/catalog'].get.responses['200'].content['application/json'].schema.properties.data.properties.meta.properties.mode.const='page';},
    f=>{f.openapi.paths['/catalog'].get.responses['200'].content['application/json'].schema.properties.data.required=['items'];},
    f=>{f.contract.operations[0].response.data.type='array';},
  ];
  for(const change of failures){
    const f=listFixture();change(f);
    assert.throws(()=>planTypedFeature(f),/RC116 typed feature/);
  }
});

test('RC271 preserves a strict one-object GET contract without inventing list metadata',()=>{
  const f=listFixture();
  const op=f.contract.operations[0];
  op.operationId='catalog.item.get';
  op.response.data=op.response.data.item;
  const route=f.openapi.paths['/catalog'].get;
  route.operationId=op.operationId;
  route.responses['200'].content['application/json'].schema.properties.data=
    route.responses['200'].content['application/json'].schema.properties.data.properties.items.items;
  f.requirements.features.catalog.operations[0].operationId=op.operationId;
  const plan=planTypedFeature(f);
  assert.equal(plan.operations[0].resultKind,'single');
  const result=renderTypedFeature(plan);
  const page=result.get('packages/features/fable_catalog/lib/src/presentation/catalog_item_get_page.dart');
  assert.match(page,/Authenticated source-bound GET/);
  assert.doesNotMatch(page,/limitExceeded/);
});

test('RC333 optionally signed unpaginated filters do not block safe read-only typed UI',()=>{
  const f=listFixture();
  const signed=[
    {key:'q',type:'string'},
    {key:'sort',type:'string',sortAllowedFields:['createdAt']},
    {key:'createdAtFrom',type:'string',format:'date-time'},
    {key:'createdAtTo',type:'string',format:'date-time'},
    {key:'fableRevisionMin',type:'number'},
  ];
  f.contract.operations[0].request.query=signed;
  f.openapi.paths['/catalog'].get.parameters=signed.map(q=>({
    name:q.key,in:'query',required:false,
    schema:{type:q.type,...(q.format?{format:q.format}:{})},
    ...(q.sortAllowedFields?{'x-fable-sort-allowlist':q.sortAllowedFields}:{}),
  }));
  const plan=planTypedFeature(f);
  assert.equal(plan.operations[0].resultKind,'unpaginated-list');
  assert.equal(plan.operations[0].filters.length,0);
  const files=renderTypedFeature(plan);
  const repo=files.get(
    'packages/features/fable_catalog/lib/src/data/fable_catalog_list_unpaginated_repository.dart');
  assert.ok(repo.includes('gateway.execute("catalog.list.unpaginated")'));
  assert.doesNotMatch(repo,/query:<String,dynamic>/);
  const page=files.get(
    'packages/features/fable_catalog/lib/src/presentation/catalog_list_unpaginated_page.dart');
  assert.ok(page.includes('Previous 100'));
  assert.ok(page.includes('Next 100'));
});

test('RC333 refuses unpaginated query spoofing, required filters and OpenAPI drift',()=>{
  const make=()=>{
    const f=listFixture();
    f.contract.operations[0].request.query=[
      {key:'q',type:'string'},
    ];
    f.openapi.paths['/catalog'].get.parameters=[
      {name:'q',in:'query',required:false,schema:{type:'string'}},
    ];
    return f;
  };
  const changes=[
    f=>{f.contract.operations[0].request.query[0].required=true;},
    f=>{f.openapi.paths['/catalog'].get.parameters[0].required=true;},
    f=>{f.openapi.paths['/catalog'].get.parameters[0].schema.type='number';},
    f=>{f.openapi.paths['/catalog'].get.parameters[0].name='sneaky';},
    f=>{f.contract.operations[0].request.query.push({key:'q',type:'string'});},
    f=>{f.contract.operations[0].request.query[0].key='page';},
    f=>{f.contract.operations[0].request.query[0].key='__proto__';},
    f=>{f.contract.operations[0].request.query[0].type='object';},
    f=>{f.openapi.paths['/catalog'].get.parameters.push({name:'X-Admin',in:'header'});},
    f=>{f.contract.operations[0].request.headers=['X-Unbound-Context'];},
  ];
  for(const change of changes){
    const f=make();change(f);
    assert.throws(()=>planTypedFeature(f),/RC116 typed feature/);
  }
});

import test from 'node:test';
import assert from 'node:assert/strict';
import {renderTypedFeature} from '../tools/render-typed-feature-rc116.mjs';

const plan=()=>({
  featureId:'catalog',projectId:'sample-signed-project',contractHash:'a'.repeat(64),
  operations:[{
    operationId:'catalog.list.paginated',method:'GET',path:'/catalog',
    contractHash:'b'.repeat(64),className:'CatalogListPaginated',
    fields:[{name:'id',type:'String',required:true},
      {name:'title',type:'String',required:true}],
    params:[],bodyFields:[],resultKind:'paginated-list',supportsSearch:true,
  }],
});

test('RC275 infinite list exposes constant-cost immutable view instead of cloning every build',()=>{
  const files=renderTypedFeature(plan()),prefix='packages/features/fable_catalog/';
  const state=files.get(prefix+'lib/src/presentation/catalog_list_paginated_controller.dart');
  assert.match(state,/import 'dart:collection';/);
  assert.match(state,/late final UnmodifiableListView<CatalogListPaginatedItem> _readOnlyItems=/);
  assert.match(state,/UnmodifiableListView<CatalogListPaginatedItem>\(_items\)/);
  assert.match(state,/List<CatalogListPaginatedItem> get items=>_readOnlyItems/);
  assert.doesNotMatch(state,/List<CatalogListPaginatedItem>\.unmodifiable\(_items\)/);
});

test('RC275 corrupt middle page becomes explicit retry instead of silently truncating global results',()=>{
  const files=renderTypedFeature(plan()),prefix='packages/features/fable_catalog/';
  const state=files.get(prefix+'lib/src/presentation/catalog_list_paginated_controller.dart');
  const widget=files.get(prefix+'test/catalog_list_paginated_page_test.dart');
  assert.match(state,/data\.items\.isEmpty && requested<data\.totalPages/);
  assert.match(state,/requested==1 && data\.items\.isEmpty && data\.total>0/);
  assert.match(state,/_error=TypedReadFailureKind\.invalidResponse/);
  assert.match(state,/_completed=requested>=data\.totalPages \|\|/);
  assert.doesNotMatch(state,/_completed=.*data\.items\.isEmpty/);
  assert.match(widget,/bool emptyIntermediate=false;/);
  assert.match(widget,/emptyIntermediate\?<CatalogListPaginatedItem>\[\]/);
  assert.match(widget,/repository=_FakeRepository\(\)\.\.emptyIntermediate=true/);
  assert.match(widget,/find\.textContaining\("Retry failed page"\),findsOneWidget/);
  assert.match(widget,/find\.text\("All results loaded"\),findsNothing/);
});

test('RC275 preserves old contracts with page-only infinite scroll',()=>{
  const old=plan();
  old.operations[0].supportsSearch=false;
  const files=renderTypedFeature(old),prefix='packages/features/fable_catalog/';
  const page=files.get(prefix+'lib/src/presentation/catalog_list_paginated_page.dart');
  assert.match(page,/ListView\.builder/);
  assert.doesNotMatch(page,/Search across all authorized records/);
  assert.doesNotMatch(page,/Previous page|Next page/);
});

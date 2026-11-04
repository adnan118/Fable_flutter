import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,mkdirSync,writeFileSync,rmSync,symlinkSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join,dirname} from 'node:path';
import {
  auditFeatureArchitectures,checkLayerSource,checkFeatureArchitecture,
} from '../tools/enforce-feature-architecture-rc115.mjs';

const prefix='packages/features/fable_orders/';
const marker={
  schemaVersion:1,kind:'fable.flutter-feature-architecture',
  featureId:'orders',mode:'four-layer-typed',enforced:true,
};
function put(root,path,content){
  const dest=join(root,path);
  mkdirSync(dirname(dest),{recursive:true});
  writeFileSync(dest,content);
  return dest;
}
function fixture({manifest=true}={}){
  const root=mkdtempSync(join(tmpdir(),'fable-rc115-'));
  const src=prefix+'lib/src/';
  if(manifest)put(root,prefix+'.fable-architecture.json',JSON.stringify(marker));
  put(root,src+'domain/order.dart',
    "import 'dart:async';\nabstract interface class OrderPort { Future<int> read(); }");
  put(root,src+'application/load_order.dart',
    "import '../domain/order.dart';\nfinal class LoadOrder { const LoadOrder(this.port); final OrderPort port; Future<int> execute()=>port.read(); }");
  put(root,src+'data/order_source.dart',
    "import 'package:dio/dio.dart';\nimport '../domain/order.dart';\nfinal class OrderData { OrderData(this.dio); final Dio dio; }");
  put(root,src+'presentation/order_state.dart',
    "import 'package:flutter/foundation.dart';\nimport '../application/load_order.dart';\nfinal class OrderState extends ChangeNotifier { OrderState(this.useCase); final LoadOrder useCase; }");
  return root;
}
function withFixture(fn,opts){
  const root=fixture(opts);
  try{return fn(root);}
  finally{rmSync(root,{recursive:true,force:true});}
}

test('RC115 audits every newly layered feature, not a Media-only path',()=>{
  withFixture(root=>{
    put(root,'packages/features/fable_auth/lib/legacy.dart','// old feature');
    const audit=auditFeatureArchitectures(root);
    assert.deepEqual(audit.findings,[]);
    assert.deepEqual(audit.adopted,['orders']);
    assert.deepEqual(audit.legacy,['auth']);
  });
});

test('RC115 brand-new feature cannot bypass enforcement by omitting all four layers',()=>{
  withFixture(root=>{
    put(root,'packages/features/fable_payroll/lib/fable_payroll.dart',
      'final class NotActuallyArchitected {}');
    const report=auditFeatureArchitectures(root);
    assert.ok(report.findings.some(x=>x.includes(
      'payroll: new feature lacks typed four-layer architecture and manifest')),
      report.findings.join('\n'));
    assert.ok(report.adopted.includes('payroll'));
  });
});

test('RC115 manifest deletion cannot silently disable a layered feature audit',()=>{
  withFixture(root=>{
    const report=auditFeatureArchitectures(root);
    assert.ok(report.adopted.includes('orders'));
    assert.ok(report.findings.some(x=>x.includes('architecture manifest missing')));
  },{manifest:false});
});

test('RC115 missing layer and forged manifest fail closed',()=>{
  withFixture(root=>{
    put(root,prefix+'.fable-architecture.json',
      JSON.stringify({...marker,featureId:'billing'}));
    assert.ok(checkFeatureArchitecture(root,'orders').some(
      x=>x.includes('invalid architecture manifest')));
    rmSync(join(root,prefix,'lib/src/presentation/order_state.dart'));
    assert.ok(checkFeatureArchitecture(root,'orders').some(
      x=>x.includes('presentation contains no Dart source')));
  });
});

test('RC115 refuses imports from Application to Data and Presentation to HTTP',()=>{
  withFixture(root=>{
    put(root,prefix+'lib/src/application/load_order.dart',
      "import '../data/order_source.dart';");
    put(root,prefix+'lib/src/presentation/order_state.dart',
      "import 'package:dio/dio.dart';");
    const problems=auditFeatureArchitectures(root).findings;
    assert.ok(problems.some(x=>x.includes('application -> data')),problems.join('\n'));
    assert.ok(problems.some(x=>x.includes('forbidden external package package:dio')),
      problems.join('\n'));
  });
});

test('RC115 rejects cross-feature, legacy and ambiguous imports from Application',()=>{
  const file=prefix+'lib/src/application/example.dart';
  for(const invalid of [
    "import 'package:fable_payments/fable_payments.dart';",
    "import 'package:fable_orders/src/presentation/state.dart';",
    "import '../legacy.dart';",
    "import '../../../other/secret.dart';",
    "import 'package:shared_preferences/shared_preferences.dart';",
  ]){
    assert.ok(checkLayerSource({featureId:'orders',layer:'application',
      source:invalid,file}).length>0,invalid);
  }
});

test('RC115 rejects dynamic in public Domain/Application/Presentation source',()=>{
  for(const layer of ['domain','application','presentation']){
    const problems=checkLayerSource({featureId:'orders',layer,
      source:'Future<Map<String,dynamic>> load();',
      file:prefix+'lib/src/'+layer+'/file.dart'});
    assert.ok(problems.some(x=>x.includes('contains dynamic')),layer);
  }
  assert.deepEqual(checkLayerSource({featureId:'orders',layer:'data',
    source:'Map<String,dynamic> parse(Object? body)=>{};',
    file:prefix+'lib/src/data/mapper.dart'}),[]);
});

test('RC115 detects attempted source symlink bypass',()=>{
  withFixture(root=>{
    const dir=join(root,prefix,'lib/src/domain');
    const target=put(root,prefix+'lib/src/application/source.dart','final class A {}');
    symlinkSync(target,join(dir,'alias.dart'));
    const issues=checkFeatureArchitecture(root,'orders');
    assert.ok(issues.some(x=>x.includes('symlink in enforced source tree')));
  });
});

test('RC115 pure Domain can use Dart standard libraries but not platform I/O',()=>{
  const file=prefix+'lib/src/domain/result.dart';
  assert.deepEqual(checkLayerSource({featureId:'orders',layer:'domain',
    source:"import 'dart:typed_data';\nimport 'order.dart';",
    file}),[]);
  assert.ok(checkLayerSource({featureId:'orders',layer:'domain',
    source:"import 'dart:io';",file}).length>0);
  assert.ok(checkLayerSource({featureId:'orders',layer:'domain',
    source:'class Test { final Dio http; }',file}).length>0);
});

test('RC115 explicitly reports legacy packages as not architecturally certified',()=>{
  withFixture(root=>{
    put(root,'packages/features/fable_auth/lib/src/legacy_widgets.dart',
      "import 'package:dio/dio.dart';");
    const result=auditFeatureArchitectures(root);
    assert.ok(result.legacy.includes('auth'));
    assert.equal(result.adopted.includes('auth'),false);
  });
});

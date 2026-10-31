import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';

const read=file=>readFileSync(resolve(file),'utf8');
test('The runtime selects Fable only when explicitly configured',()=>{
  const backend=read('packages/fable_core/lib/src/backend_selection.dart');
  assert.match(backend,/canUseFableContract => isFable && contractImported && status=='ready'/);
  assert.match(backend,/canUseExternalCatalog => kind=='other' && contractImported && status=='ready'/);
  assert.match(backend,/kind=='fable' && adapter=='fable-contract'/);
  assert.match(backend,/kind=='other' && \(adapter=='openapi'\|\|adapter=='custom'\)/);
});
test('External backend never uses Fable contract pages or inferred operations',()=>{
  const app=read('lib/src/app.dart');
  assert.match(app,/if \(!backend.canUseFableContract\) return _Bootstrap\(backend,null,null,null,null\)/);
  assert.match(app,/if\(external==null\)return false/);
  assert.match(app,/if\(feature.id=='auth'\)return connection.externalAuthBinding!=null/);
  assert.match(app,/final authBinding=await ExternalAuthBinding.loadOptional\(rootBundle,catalog\)/);
  assert.match(app,/if\(feature.externalScreen\(external,bindings\)!=null\)return true/);
  assert.match(app,/if\(!kDebugMode\)return false/);
  assert.match(app,/if\(readOperation==null\|\|!external.supports\(readOperation\)\)return false/);
  assert.match(app,/if\(feature.id=='auth'&&snapshot.externalAuthBinding==null\)return false/);
  assert.doesNotMatch(app,/connection\.fableContract\?\.isFeatureAvailable\(feature\.id\) \?\? true/);
});
test('The external backend wizard never invents Fable auth or session policies',()=>{
  const wizard=read('tools/flutter-setup-wizard.mjs');
  assert.match(wizard,/هل الباك المستخدم لهذا المشروع هو Fable/);
  assert.match(wizard,/هل تريد استيراد قرارات Fable Backend المصدّرة/);
  assert.match(wizard,/backend:\{kind:'other',adapter:snapshot.backendAdapter,status:'pending'\}/);
  assert.match(wizard,/contractImported:false/);
  assert.match(wizard,/authentication:\{status:'unverified-external-contract'/);
  assert.match(wizard,/managedEntities:null/);
  assert.match(wizard,/Cannot prune based on Fable capabilities for a non-Fable Backend/);
});

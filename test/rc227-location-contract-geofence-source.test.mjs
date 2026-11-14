import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const read=path=>readFileSync(new URL('../'+path,import.meta.url),'utf8');
const src=read('packages/features/fable_location/lib/src/location_repository.dart');
const dart=read('packages/features/fable_location/test/location_repository_test.dart');
const runner=read('tools/fable-one-command.mjs');

test('RC227 location operation roles require enforced auth and no provider key',()=>{
  assert.ok(src.includes('!op.requiresAuth || !op.enforceAuth'));
  assert.ok(src.includes('op.credentialHeader != null'));
});
test('RC227 location contracts reject untrusted fragments/dynamic routes',()=>{
  assert.ok(src.includes("op.path.contains('?') || op.path.contains('#')"));
  assert.ok(src.includes("op.path.contains('{')"));
  assert.ok(src.includes("op.path.contains('}')"));
});
test('RC227 geofence decision fails closed for invalid numeric distance',()=>{
  assert.ok(src.includes('!distance.toDouble().isFinite || distance < 0'));
  assert.ok(src.includes("throw const FormatException('Invalid geofence decision')"));
});
test('RC227 known location role methods remain GET and POST as the contract declares',()=>{
  assert.ok(src.includes("(_getRoles.contains(entry.key) ? 'GET' : 'POST')"));
  assert.ok(src.includes('FableLocationOperations._(Map.unmodifiable(accepted))'));
});
test('RC227 Dart cases cover missing enforcement, fragments and invalid distances',()=>{
  assert.ok(dart.includes('declared auth alone cannot bind location'));
  assert.ok(dart.includes('geofence refuses negative or nonfinite'));
  assert.ok(dart.includes('operation fragments are not valid client bindings'));
  assert.ok(dart.includes('double.nan') && dart.includes('double.infinity'));
  assert.equal((dart.match(/test\('/g)||[]).length,8);
});
test('RC227 existing pnpm fable:all runs actual location Dart tests',()=>{
  assert.ok(runner.includes('packages/features/fable_location/test/location_repository_test.dart'));
});

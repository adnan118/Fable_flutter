import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

const read = path => readFileSync(new URL('../'+path,import.meta.url),'utf8');
const transport = read('packages/fable_core/lib/src/fable_api.dart');
const adapter = read('packages/fable_core/lib/src/backend_transport_adapter.dart');
const regressions = read('packages/fable_core/test/rc360_installation_header_boundary_test.dart');

test('RC360 installation ID validates canonical 128-bit hex at Fable adapter ingress',()=>{
  assert.match(adapter,/final installationId = await session\.installationId\(\);/);
  assert.match(adapter,/RegExp\(r'\^\[a-f0-9\]\{32\}\$'\)\.hasMatch\(installationId\)/);
  assert.match(adapter,/headers\['X-Installation-Id'\] = installationId;/);
  assert.match(adapter,/throw const FormatException\('Invalid Fable installation identifier'\);/);
});

test('RC360 UnifiedApiClient refuses Fable ID exposure in Other Backend adapters',()=>{
  const start=transport.indexOf('final installationHeaders=headers.entries.where(');
  const end=transport.indexOf('// These headers may only be installed below',start);
  assert.ok(start>0&&end>start,'missing transport provenance check');
  const guard=transport.slice(start,end);
  for(const expected of [
    "entry.key.toLowerCase()=='x-installation-id'",
    "if(contract is FableContract)",
    "adapter is! FableTransportAdapter",
    'installationHeaders.length!=1',
    "throw StateError('Fable installation header is missing or invalid')",
    "throw StateError('External adapter attempted to expose a Fable installation identifier')",
  ]) assert.ok(guard.includes(expected),expected);
  assert.equal((transport.match(/class UnifiedApiClient/g)||[]).length,1);
  assert.equal((transport.match(/class FableApiException implements Exception/g)||[]).length,1);
});

test('RC360 Dart regressions include valid and malformed IDs plus external header injection',()=>{
  for(const fragment of [
    'refuses malformed installation ID before dispatch',
    'Fable request sends one source-validated installation identifier',
    'Other Backend injected adapter cannot leak Fable installation ID',
    'throwsFormatException',
    'throwsStateError',
    'expect(sends,0)',
  ]) assert.ok(regressions.includes(fragment),fragment);
});

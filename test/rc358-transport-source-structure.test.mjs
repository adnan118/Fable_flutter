import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

const source=readFileSync(new URL(
  '../packages/fable_core/lib/src/fable_api.dart',import.meta.url),'utf8');
test('RC358 transport source has one intact copy, not a duplicated Dart declaration',()=>{
  assert.equal((source.match(/class UnifiedApiClient/g)||[]).length,1);
  assert.equal((source.match(/class FableApiException implements Exception/g)||[]).length,1);
  assert.ok(source.trimEnd().endsWith('}'));
  assert.ok(!source.includes('\n).hasMatch(ifMatch)))'));
});
test('RC358 retains signed conditional writes and managed tenant security provenance',()=>{
  for(const term of [
    'Signed conditional mutation requires If-Match',
    'Managed entity requires a live selection/revision guard',
    'Signed managed operation requires a verified entity context',
    "op.recordAccess?.startsWith('managed-entity:')",
    "op.recordAccess==null ||",
    'Backend adapter attempted to inject operation-scoped headers',
    'session_changed_discard_response',
  ])assert.ok(source.includes(term),term);
});

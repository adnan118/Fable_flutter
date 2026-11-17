import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

const transport = readFileSync(new URL(
  '../packages/fable_core/lib/src/fable_api.dart', import.meta.url), 'utf8');

test('RC359 signed idempotency cannot be injected into a read or weak-auth operation', () => {
  const begin = transport.indexOf('if(idempotencyKey!=null &&');
  const end = transport.indexOf('if(op.requiresIdempotency &&', begin);
  assert.ok(begin > 0 && end > begin, 'Expected complete idempotency validation');
  const guard = transport.slice(begin, end);
  for (const check of [
    '!op.requiresIdempotency', '!op.requiresAuth', '!op.enforceAuth',
    'op.credentialHeader != null',
    "const <String>{'POST','PUT','PATCH','DELETE'}.contains(op.method.toUpperCase())",
    "RegExp(r'^[a-f0-9]{64}$').hasMatch(idempotencyKey)",
  ]) assert.ok(guard.includes(check), check);
});

test('RC359 If-Match remains bound to signed bearer conditional PATCH/DELETE', () => {
  const begin = transport.indexOf('if (ifMatch != null &&');
  const end = transport.indexOf('if (op.requiresIfMatch &&', begin);
  assert.ok(begin > 0 && end > begin, 'Expected complete If-Match validation');
  const guard = transport.slice(begin, end);
  for (const check of [
    '!op.requiresIfMatch', '!op.requiresAuth', '!op.enforceAuth',
    'op.credentialHeader != null',
    "const <String>{'PATCH','DELETE'}.contains(op.method.toUpperCase())",
  ]) assert.ok(guard.includes(check), check);
  assert.equal((transport.match(/class UnifiedApiClient/g) || []).length, 1);
  assert.ok(transport.trimEnd().endsWith('}'));
});

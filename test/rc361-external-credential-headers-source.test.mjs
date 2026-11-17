import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

const read=path=>readFileSync(new URL('../'+path,import.meta.url),'utf8');
const policy=read('packages/fable_core/lib/src/backend_credential_provider.dart');
const importer=read('packages/fable_core/lib/src/external_operation_catalog.dart');
const transport=read('packages/fable_core/lib/src/fable_api.dart');
const dart=read('packages/fable_core/test/rc361_external_credential_header_policy_test.dart');

test('RC361 one shared reserved-credential policy protects imported external routes',()=>{
  assert.ok(policy.includes('bool isAllowedExternalCredentialHeader(Object? value)'));
  for(const reserved of [
    'x-installation-id','dpop','idempotency-key','if-match','range',
    'x-security-challenge-id','x-csrf-token',
    'content-type','accept-language',
  ])assert.ok(policy.includes("'"+reserved+"'"),reserved);
  assert.ok(policy.includes("header.startsWith('x-fable-')"));
  assert.ok(importer.includes("import 'backend_credential_provider.dart' show isAllowedExternalCredentialHeader;"));
  assert.ok(importer.includes('isAllowedExternalCredentialHeader(value)'));
});

test('RC361 runtime rejects a synthetic catalog before resolving provider credentials',()=>{
  const first=transport.indexOf('final op=contract.require(operationId);');
  const boundary=transport.indexOf('// A source-signed managed route cannot execute',first);
  assert.ok(first>0 && boundary>first);
  const guard=transport.slice(first,boundary);
  assert.ok(guard.includes('op.credentialHeader!=null'));
  assert.ok(guard.includes('contract is FableContract'));
  assert.ok(guard.includes('!isAllowedExternalCredentialHeader(op.credentialHeader)'));
  assert.ok(guard.includes("throw StateError('External credential header is reserved or not verified')"));
  assert.ok(transport.indexOf('final headers=await adapter.headersFor(op,session);')>boundary);
});

test('RC361 behavior coverage includes rejection and supported Basic/API-key headers',()=>{
  for(const fragment of [
    "'DPoP'","'If-Match'","'Idempotency-Key'",
    "'Authorization'","'X-API-Key'",
    'forged external operation cannot dispatch',
    'synthetic Fable contract cannot enable custom credential headers',
    'expect(sends,0)','expect(credentials.calls,0)',
  ])assert.ok(dart.includes(fragment),fragment);
});

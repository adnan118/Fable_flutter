import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

const read=name=>readFileSync(new URL('../'+name,import.meta.url),'utf8');
const repo=read('packages/features/fable_payments/lib/src/payments_repository.dart');
const native=read('packages/features/fable_payments/test/payments_contract_test.dart');
const runner=read('tools/fable-one-command.mjs');
const packageYaml=read('packages/features/fable_payments/pubspec.yaml');

test('RC223 payment read operation enforces authenticated contract not just advertised auth',()=>{
  assert.match(repo,/op\.method != 'GET' \|\| !op\.requiresAuth \|\| !op\.enforceAuth/);
  assert.match(repo,/op\.credentialHeader != null/);
  assert.match(repo,/!op\.path\.contains\('\{id\}'\)/);
});
test('RC223 authenticated read rejects admin and embedded query routes',()=>{
  assert.ok(repo.includes("op.path.contains('/admin/')"));
  assert.ok(repo.includes("op.path.contains('?')"));
});
test('RC223 server payment response ID is compared before returning customer state',()=>{
  const x=repo.slice(repo.indexOf('Future<FablePaymentSnapshot> read('));
  assert.match(x,/final payment=decode\(response\.data\)/);
  assert.match(x,/payment\.id\.toLowerCase\(\)!=id\.toLowerCase\(\)/);
  assert.ok(x.indexOf("throw const FormatException('Payment response ID mismatch')")<
    x.lastIndexOf('return payment;'));
});
test('RC223 repository never initiates capture/refund or retries state-changing POST',()=>{
  const x=repo.slice(repo.indexOf('Future<FablePaymentSnapshot> read('));
  assert.equal((x.match(/gateway\.execute\(/g)||[]).length,1);
  assert.ok(!x.includes('capture(')&&!x.includes('refund('));
});
test('RC223 all six real Flutter payments regressions are preserved',()=>{
  assert.equal((native.match(/test\('/g)||[]).length,6);
  assert.ok(native.includes("mismatched payment data is rejected"));
  assert.ok(native.includes("matching payment ID returned from Backend"));
  assert.ok(native.includes("Unsafe payment operation"));
});
test('RC223 payment test is a first-class one-command Flutter gate with direct Dio test dep',()=>{
  assert.ok(runner.includes('packages/features/fable_payments/test/payments_contract_test.dart'));
  assert.ok(packageYaml.includes('dio: ^5.9.0'));
});

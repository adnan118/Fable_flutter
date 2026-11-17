// RC379 deferred source regression: run with the existing Node test suite only when authorized.
import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const renderer=readFileSync(new URL('../tools/render-typed-feature-rc116.mjs',import.meta.url),'utf8');
test('signed PATCH and DELETE adapters bind exact reviewed HTTP status',()=>{
  const checks=renderer.match(/response\.statusCode!='\+\(op\.expectedSuccessStatus\?\?200\)\+'/g)??[];
  assert.equal(checks.length,2,'both conditional mutation adapters must use the reviewed status');
  assert.doesNotMatch(renderer,/response\.statusCode!=200\|\|envelope is! Map/);
});

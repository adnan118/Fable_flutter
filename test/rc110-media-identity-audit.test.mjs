import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

const file=readFileSync('packages/features/fable_media/lib/src/media_upload_repository.dart','utf8');
const tests=readFileSync('packages/features/fable_media/test/media_identity_transfer_rc110_test.dart','utf8');

test('RC110 all media HTTP operations route through the scoped execution guard',()=>{
  assert.equal((file.match(/gateway\.execute\(/g)||[]).length,1);
  for(const id of ['prepare','status','abort','chunk','partUrl','partAck','complete']){
    assert.match(file,new RegExp('_execute\\(scope,bindings\\.'+id+'\\b'),
      'Ungarded media operation: '+id);
  }
  assert.match(file,/scope\.check\(\);\s*\/\/ Never ACK a part completed after account replacement/);
  assert.match(file,/scope\.check\(\);\s*\/\/ Never send A's DELETE under a later B login/);
  assert.match(file,/Media upload cancelled/);
  assert.match(file,/Media session changed/);
});

test('RC110 identity context is sourced from Fable session or explicit Other Backend mapping',()=>{
  assert.match(file,/gateway is FableAuthGateway/);
  assert.match(file,/session\.identityRevision/);
  assert.match(file,/Other Backend media requires verified session epoch/);
  assert.match(file,/final scope=_fence\(cancelToken\)/);
  assert.match(file,/scope\.check\(\);\s*\/\/ The file may take minutes to hash/);
});

test('RC110 simulation test matrix covers stale data and stable account completion',()=>{
  for(const scenario of ['delayed prepare','delayed status','late local chunk',
    'cancellation after initial status','durable checkpoint','old session cannot send DELETE',
    'R2 part completed','stable account still completes']){
    assert.ok(tests.includes(scenario),scenario);
  }
});

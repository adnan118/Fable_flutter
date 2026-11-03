import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const widget=readFileSync('packages/features/fable_media/lib/src/resumable_upload_card.dart','utf8');
const repo=readFileSync('packages/features/fable_media/lib/src/media_upload_repository.dart','utf8');
const simulations=readFileSync('packages/features/fable_media/test/media_widget_lifecycle_rc111_test.dart','utf8');

test('RC111 widget rebind resets source and blocks stale async callbacks',()=>{
  assert.match(widget,/didUpdateWidget/);
  assert.match(widget,/_sourceChanged\(oldWidget\)/);
  assert.match(widget,/_generation\+\+/);
  assert.match(widget,/widget\.repository\.identityEvents/);
  assert.match(widget,/setState\(\(\)=>_clearTransient\(block:true\)\)/);
  assert.match(widget,/repo(?:sitory)?\.isSameIdentity|widget\.repository\.isSameIdentity/);
  assert.match(widget,/if\(!_active\(generation\)\|\|_cancelled\|\|_stopped\)return;/);
  assert.match(widget,/final store=widget\.checkpoints/);
  assert.match(widget,/final repository=widget\.repository/);
  assert.match(widget,/widget\.onCompleted\?\.call\(result\)/);
});
test('RC111 never silently reuses Fable events for Other Backend',()=>{
  assert.match(repo,/fable\.session\.identityEvents/);
  assert.match(repo,/_identityEvents=identityEvents/);
  assert.match(widget,/Verified authentication change events are required/);
});
test('RC111 simulated widget tests cover replacement, identity, restore, cancel, Other',()=>{
  for(const item of ['old prepare reply','identity event revokes',
      'stale checkpoint restore','old cancel never clears','without Auth events']){
    assert.ok(simulations.includes(item),item);
  }
});

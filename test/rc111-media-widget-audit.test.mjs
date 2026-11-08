import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

const read=(p)=>readFileSync(p,'utf8');
const widget=read('packages/features/fable_media/lib/src/resumable_upload_card.dart');
const flow=read('packages/features/fable_media/lib/src/application/resumable_upload_workflow.dart');
const adapter=read('packages/features/fable_media/lib/src/data/media_upload_workflow_adapter.dart');
const repo=read('packages/features/fable_media/lib/src/media_upload_repository.dart');
const simulations=read('packages/features/fable_media/test/media_widget_lifecycle_rc111_test.dart');

test('RC111 lifecycle guarantees preserved after RC125 upload UI extraction',()=>{
  assert.match(widget,/didUpdateWidget/);
  assert.match(widget,/_sourceChanged\(oldWidget\)/);
  assert.match(widget,/_unbind\(\)/);
  assert.match(widget,/identical\(_workflow,flow\)/);
  assert.match(widget,/onCompleted\?\.call\(/);
  assert.match(flow,/_generation\+\+/);
  assert.match(flow,/if \(!canApply\(\)\) return;/);
  assert.match(flow,/_port\.isSameIdentity\(_identityRevision!\)/);
  assert.match(adapter,/await checkpoints\.save\(next\)/);
  assert.match(adapter,/await checkpoints\.clear\(\);/);
});

test('RC111 Other Backend never inherits Fable session events implicitly',()=>{
  assert.match(repo,/fable\.session\.identityEvents/);
  assert.match(repo,/_identityEvents=identityEvents/);
  assert.match(adapter,/repository\.identityEvents\?\.map/);
  assert.match(flow,/UploadFlowProblem\.missingIdentityEvents/);
  assert.match(widget,/Verified authentication change events are required/);
});

test('RC111 simulated UI regressions cover replacement, identity, restore, cancel, Other',()=>{
  for(const item of ['old prepare reply','identity event revokes',
      'stale checkpoint restore','old cancel never clears','without Auth events']){
    assert.ok(simulations.includes(item),item);
  }
});

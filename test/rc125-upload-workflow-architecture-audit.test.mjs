import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {auditMediaArchitecture} from '../tools/enforce-media-architecture-rc114.mjs';
import {checkLayerSource} from '../tools/enforce-feature-architecture-rc115.mjs';

const root='packages/features/fable_media/lib/src/';
const read=(p)=>readFileSync(p,'utf8');
const ui=read(root+'resumable_upload_card.dart');
const composition=read(root+'media_upload_widget_composition.dart');
const port=read(root+'domain/upload_workflow_port.dart');
const app=read(root+'application/resumable_upload_workflow.dart');
const adapter=read(root+'data/media_upload_workflow_adapter.dart');
const unit=read('packages/features/fable_media/test/media_upload_workflow_rc125_test.dart');
const widgets=read('packages/features/fable_media/test/media_widget_lifecycle_rc111_test.dart');
const barrel=read('packages/features/fable_media/lib/fable_media.dart');

test('RC125 upload moves UI async orchestration into typed clean layers',()=>{
  assert.deepEqual(auditMediaArchitecture(process.cwd()),[]);
  for(const [layer,source,path] of [
    ['domain',port,root+'domain/upload_workflow_port.dart'],
    ['application',app,root+'application/resumable_upload_workflow.dart'],
    ['data',adapter,root+'data/media_upload_workflow_adapter.dart']]){
    assert.deepEqual(checkLayerSource({featureId:'media',layer,source,file:path}),[]);
  }
  // Comments may legitimately describe the types that are prohibited by
  // this gate; reject real imports/signatures rather than explanatory text.
  const active=(source)=>source.replace(/\/\*[\s\S]*?\*\//g,'')
    .replace(/^\s*\/\/.*$/gm,'');
  for(const original of [port,app]){
    const source=active(original);
    for(const forbidden of ['package:dio','package:fable_core','package:flutter',
      'dart:io','dynamic','CancelToken','BuildContext','BackendApiGateway']){
      assert.ok(!source.includes(forbidden),forbidden);
    }
  }
  for(const forbidden of ['package:dio','package:fable_core','CancelToken',
    'repository.start(', 'repository.resume(', 'repository.cancel(',
    'checkpoints.save(', 'checkpoints.clear(', '.read()', '.verify(']){
    assert.ok(!ui.includes(forbidden),'Widget still handles '+forbidden);
  }
  assert.ok(composition.includes('MediaUploadWorkflowAdapter('));
  assert.ok(composition.includes('ResumableUploadWorkflow('));
  assert.ok(barrel.includes('domain/upload_workflow_port.dart'));
  assert.ok(barrel.includes('application/resumable_upload_workflow.dart'));
});

test('RC125 cancellation is persisted before remote DELETE and rejects stale writes',()=>{
  const local=adapter.indexOf('await checkpoints.clear();');
  const backend=adapter.indexOf('await repository.cancel(');
  assert.ok(local>=0 && backend>local);
  assert.ok(adapter.includes('repository.isSameIdentity(identityRevision)'));
  assert.ok(adapter.includes('if (!mayPersist()) throw StateError'));
  assert.ok(adapter.includes('await checkpoints.save(next);'));
  assert.ok(app.includes('_generation++'));
  assert.ok(app.includes('_cancellation?.cancel()'));
  assert.ok(app.includes('if (!canApply()) return;'));
  assert.ok(app.includes('if (!_port.isSameIdentity(_identityRevision!))'),
    'Initial identity must be independently checked when binding events');
  assert.ok(app.includes('_port.isSameIdentity(_identityRevision!)'));
  assert.ok(app.includes('_identitySubscription = events.listen('));
  assert.ok(app.includes('UploadFlowProblem.missingIdentityEvents'));
});

test('RC125 preserves public legacy widget while preventing stale callbacks',()=>{
  for(const token of ['_sourceChanged(oldWidget)','_unbind();','identical(_workflow,flow)',
    'widget.onCompleted?.call(', 'Map<String,dynamic>.from(receipt.legacyResult)',
    'UploadFlowProblem.identityChanged']){
    assert.ok(ui.includes(token),token);
  }
  for(const token of ['identity event revokes','old prepare reply',
    'stale checkpoint restore','old cancel never clears','without Auth events']){
    assert.ok(widgets.includes(token),token);
  }
  for(const token of ['pause stops transport','late clear is fenced',
    'checkpoint restore supports resume','cancel starts durable local intent',
    'revocation cancels in-flight work']){
    assert.ok(unit.includes(token),token);
  }
  // Legacy onCompleted(Map) is explicitly transitional, not a claimed
  // fully typed repository/DTO modernization.
  assert.ok(port.includes('Compatibility-only payload'));
});

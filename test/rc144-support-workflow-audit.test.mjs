import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const read=p=>readFileSync(new URL('../'+p,import.meta.url),'utf8');

test('RC144 support workflow requires typed repository, no guessed backend route',()=>{
  const source=read('packages/features/fable_support/lib/src/support_workflow_page.dart');
  const repository=read('packages/features/fable_support/lib/src/support_repository.dart');
  const index=read('packages/features/fable_support/lib/fable_support.dart');
  assert.ok(source.includes('required this.repository'));
  assert.ok(source.includes('required this.identityRevision'));
  assert.ok(source.includes('required this.identityInvalidations'));
  assert.ok(source.includes('required this.isAuthenticated'));
  assert.ok(repository.includes('abstract interface class FableSupportWorkflowPort'));
  assert.ok(repository.includes('FableSupportRepository implements FableSupportWorkflowPort'));
  assert.ok(index.includes("export 'src/support_workflow_page.dart'"));
  assert.equal(source.includes("'/support/"),false);
  assert.equal(source.includes("'/tickets'"),false);
  assert.equal(source.includes('FableAuthGateway('),false);
  assert.equal(source.includes('ExternalApiGateway('),false);
});
test('RC144 no stale account ticket response or repeated unsafe mutation',()=>{
  const source=read('packages/features/fable_support/lib/src/support_workflow_page.dart');
  for(const x of ['_generation++','widget.identityRevision() == identity',
    'widget.isAuthenticated()','if (_current(generation, identity))',
    'unawaited(_identitySub?.cancel())',
    'visibleTickets = enabled && _ticketsIdentity == widget.identityRevision()',
    'Submission is unconfirmed. Review tickets before trying again.']){
    assert.ok(source.includes(x),x);
  }
  assert.equal(source.includes('Timer.periodic'),false);
  assert.equal(source.includes('retry('),false);
});
test('RC144 Support is still not auto-enabled on unverified Fable/Other backend',()=>{
  const feature=read('packages/features/fable_support/lib/fable_support.dart');
  assert.equal(feature.includes('externalScreen('),false);
  assert.equal(feature.includes('bool canLaunchFable('),false);
  const base=read('packages/fable_feature_contract/lib/fable_feature_contract.dart');
  assert.ok(base.includes('bool canLaunchFable(FableContract contract) => false;'));
});

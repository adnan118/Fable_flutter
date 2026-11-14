import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

const read=name=>readFileSync(new URL('../'+name,import.meta.url),'utf8');
const code=read('packages/features/fable_support/lib/src/support_widgets.dart');
const source=read('packages/features/fable_support/test/support_list_identity_rc225_test.dart');
const runner=read('tools/fable-one-command.mjs');

test('RC225 standalone ticket list requires explicit identity and auth bindings before loading',()=>{
  assert.match(code,/revision==null\|\|authenticated==null\|\|/);
  assert.match(code,/widget\.identityInvalidations==null\|\|!authenticated\(\)\)return/);
  assert.ok(code.includes('this.identityRevision,this.isAuthenticated,this.identityInvalidations'));
});
test('RC225 private ticket list never exposes cached tickets when auth disappears',()=>{
  assert.match(code,/if\(!authenticated\(\)\)\{/);
  assert.ok(code.includes("Sign in to view your support tickets."));
});
test('RC225 silent account revision changes fail closed even without event',()=>{
  assert.ok(code.includes('if(_loadIdentity!=revision())'));
  assert.ok(code.includes('Session changed. Reopen support tickets to verify.'));
});
test('RC225 explicit session invalidation disposes stale FutureBuilder snapshot',()=>{
  assert.ok(code.includes("key:ValueKey<int>(_generation)"));
  assert.ok(code.includes("setState(_restart)"));
  assert.ok(code.includes("_load=null;"));
  assert.ok(code.includes("_loadIdentity=null;"));
});
test('RC225 repository or identity callback replacement rebonds the ticket listener',()=>{
  assert.ok(code.includes('!identical(old.repository,widget.repository)'));
  assert.ok(code.includes('old.identityRevision!=widget.identityRevision'));
  assert.ok(code.includes('old.isAuthenticated!=widget.isAuthenticated'));
  assert.ok(code.includes('unawaited(_identityChanges?.cancel())'));
});
test('RC225 workflow page remains separate and support creates are not retried by a list',()=>{
  assert.ok(!code.includes('create('));
  assert.ok(!code.includes('retry'));
});
test('RC225 all six real Flutter Widget cases remain authored',()=>{
  assert.equal((source.match(/testWidgets\('/g)||[]).length,6);
  assert.ok(source.includes('old async ticket response never overwrites'));
  assert.ok(source.includes('silent account switch hides old ticket'));
});
test('RC225 one pnpm command runs the authenticated ticket-list UI regressions',()=>{
  assert.ok(runner.includes('packages/features/fable_support/test/support_list_identity_rc225_test.dart'));
});

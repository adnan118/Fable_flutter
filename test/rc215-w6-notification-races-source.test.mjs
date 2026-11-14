import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const read=name=>readFileSync(new URL('../'+name,import.meta.url),'utf8');
const inbox=read('packages/features/fable_notifications/lib/src/inbox_page.dart');
const nav=read('packages/features/fable_notifications/lib/src/notification_navigation.dart');
const tests=read('packages/features/fable_notifications/test/notification_identity_navigation_rc108_test.dart');

test('RC215 W6 inbox mark-read always drains an identity-change refresh request',()=>{
  const start=inbox.indexOf('Future<void> _read(FableInboxItem item) async');
  const end=inbox.indexOf('@override void dispose()',start);
  assert.ok(start>0&&end>start);
  const body=inbox.slice(start,end);
  assert.match(body,/queuedRefresh=_refreshQueued/);
  assert.match(body,/_refreshQueued=false/);
  assert.match(body,/if\(mounted\)_requestRefresh\(\)/);
});
test('RC215 W6 queued mutation refresh and ordinary success reload are mutually exclusive',()=>{
  const body=inbox.slice(inbox.indexOf('Future<void> _read(FableInboxItem item) async'),
    inbox.indexOf('@override void dispose()'));
  assert.match(body,/if\(!queuedRefresh&&mounted&&generation==_generation/);
  assert.match(body,/epoch==session\.identityRevision/);
});
test('RC215 W6 delayed password route cannot be accepted after identity changes',()=>{
  const body=nav.slice(nav.indexOf('Future<bool> openVerifiedInternalRoute('),
    nav.indexOf('void reset()',nav.indexOf('Future<bool> openVerifiedInternalRoute(')));
  assert.match(body,/final requestRevision=\+\+_revision/);
  assert.match(body,/identityAtTap=identityRevision\?\.call\(\)/);
  assert.match(body,/return sameContext\(\) && opened/);
  assert.ok(!body.includes('return await handler(route)'));
});
test('RC215 W6 password route preserves read-only recovery while logged out',()=>{
  const body=nav.slice(nav.indexOf('Future<bool> openVerifiedInternalRoute('));
  assert.ok(!body.includes('await isAuthenticated!()'));
  assert.ok(body.includes("!route.contains('password')"));
});
test('RC215 W6 Dart regressions cover identity swap, pending clear and same session',()=>{
  assert.ok(tests.includes('RC215 delayed security password-route'));
  assert.ok(tests.includes('RC215 clearing notification navigation'));
  assert.ok(tests.includes('RC215 verified same-session password recovery'));
});

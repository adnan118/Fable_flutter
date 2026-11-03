import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

const navigation=readFileSync(
  'packages/features/fable_notifications/lib/src/notification_navigation.dart','utf8');
const app=readFileSync('lib/src/app.dart','utf8');
const regression=readFileSync(
  'packages/features/fable_notifications/test/notification_identity_navigation_rc108_test.dart','utf8');

test('RC108 app wires its real session epoch into notification navigation',()=>{
  assert.match(app,/identityRevision=\(\)=>\s*safeSession\.identityRevision/);
  assert.match(app,/FableNotificationNavigation\.instance\.invalidateInFlight\(\)/);
  assert.match(app,/session\.identityRevision!=identityAtDispatch/);
  assert.match(app,/if\(!event\.authenticated\)FableNotificationNavigation\.instance\.clearPending\(\)/);
  assert.match(app,/resumeAfterLogin\(\)/);
});

test('RC108 navigation checks the epoch after await and before Fable or Other routes',()=>{
  assert.match(navigation,/final identityAtTap = identityRevision\?\.call\(\)/);
  assert.match(navigation,/!sameContext\(\)/);
  assert.match(navigation,/final fallback = await/);
  assert.match(navigation,/return sameContext\(\) && fallback/);
  assert.match(navigation,/identityRevision=null;/);
});

test('RC108 source tests simulate identity switch, deferred login and async callback',()=>{
  for(const phrase of [
    'login changes during awaited Auth check',
    'same-session verified navigation remains functional',
    'event revokes old tap without dropping deferred anonymous tap',
    'identity switch during verified URL callback',
    'logout cancels pending authenticated navigation',
  ]) assert.ok(regression.includes(phrase),phrase);
});

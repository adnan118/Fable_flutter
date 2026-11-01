import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const read=(p)=>readFileSync(new URL('../'+p,import.meta.url),'utf8');
const shell=read('lib/src/app.dart');
const core=read('packages/fable_core/lib/src/fable_managed_entity_scope.dart');
const account=read('packages/features/fable_profile/lib/src/fable_account_page.dart');
const page=read('packages/features/fable_profile/lib/src/managed_accounts_page.dart');
test('an active entity is visible only with verified Fable contract, never Other Backend',()=>{
  assert.match(shell,/connection\?\.fableContract==null\?surface:/);
  assert.match(shell,/FableManagedEntityScope\(store:_managedEntities,child:surface\)/);
  assert.match(shell,/_managedEntities\.bindBackend/);
  assert.doesNotMatch(shell,/['"]X-Fable-Managed-Entity-Id['"]/);
  assert.doesNotMatch(core,/X-Fable-Managed-Entity-Id/);
});
test('account activation propagates only verified choice and invalidates after lifecycle',()=>{
  assert.match(account,/onActivated:\(verified\)=>managed\?\.activate\(verified\)/);
  assert.match(account,/onCleared:\(\)=>managed\?\.clear\(\)/);
  assert.match(account,/Clear selected entity/);
  assert.match(page,/widget\.onActivated\?\.call\(selected\)/);
  assert.match(page,/widget\.onCleared\?\.call\(\)/);
  assert.match(core,/_session\.identityEvents\.listen\(\(_\)=>clear\(\)\)/);
  assert.match(core,/current\.identityRevision==_session\.identityRevision/);
  assert.doesNotMatch(core,/FlutterSecureStorage|SharedPreferences|Dio|http\.post/);
});
test('core stays installable after Profile is omitted by the project Wizard',()=>{
  assert.doesNotMatch(shell,/import 'package:fable_profile\//);
  assert.doesNotMatch(core,/import 'package:fable_profile\//);
  assert.match(read('packages/fable_core/lib/fable_core.dart'),
    /export 'src\/fable_managed_entity_scope\.dart';/);
});

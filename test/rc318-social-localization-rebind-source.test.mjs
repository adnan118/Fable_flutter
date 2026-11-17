import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const read=p=>readFileSync(new URL('../'+p,import.meta.url),'utf8');
const social=read('packages/features/fable_social/lib/src/social_account_settings_page.dart');
const locale=read('packages/features/fable_localization/lib/src/languages_page.dart');

test('RC318 social account settings invalidate session-bound challenge and OTP when gateway/repository identity changes',()=>{
  assert.match(social,/didUpdateWidget\(covariant FableSocialAccountSettingsPage old\)/);
  assert.ok(social.includes('!identical(old.gateway,widget.gateway)'));
  assert.ok(social.includes('!identical(old.repository,widget.repository)'));
  const block=social.slice(social.indexOf('didUpdateWidget('),social.indexOf('  @override void dispose()'));
  for(const s of ['_bindingEpoch++','unawaited(_identity?.cancel())','_otp.clear()','_verified=null',
                  '_challengeId=null','_provider=null','_busy=false','_watchIdentity()']){
    assert.ok(block.includes(s),'missing rebind reset '+s);
  }
});
test('RC318 pending social async callbacks cannot adopt same numeric revision in a replacement session',()=>{
  const start=social.slice(social.indexOf('Future<void> _start('),social.indexOf('Future<void> _verify('));
  const verify=social.slice(social.indexOf('Future<void> _verify('),social.indexOf('Future<void> _perform('));
  const perform=social.slice(social.indexOf('Future<void> _perform('),social.indexOf('@override Widget build('));
  for(const [name,block] of [['start',start],['verify',verify],['perform',perform]]){
    assert.ok(block.includes('final epoch=_bindingEpoch;'),name);
    assert.ok(block.includes('epoch!=_bindingEpoch'),name);
    assert.ok(block.includes('epoch==_bindingEpoch'),name);
  }
  assert.ok(social.includes('_bindingEpoch++;'));
});
test('RC318 localization invalidates both language and cached copy request results on contract, transport and origin replacement',()=>{
  const update=locale.slice(locale.indexOf('didUpdateWidget('),locale.indexOf('String get chosenOrigin'));
  for(const witness of ['old.contract,widget.contract','old.injectedGateway,widget.injectedGateway',
     'old.backendOrigin!=widget.backendOrigin','_sourceEpoch++','_client?.dispose()',
     '_languages=null;_copy=null','_lastCopyLocale=null']){
     assert.ok(update.includes(witness),witness);
  }
  const copy=locale.slice(locale.indexOf('Future<void> checkCopy('),locale.indexOf('Future<void> load('));
  assert.ok(copy.includes('epoch==_sourceEpoch'));
  assert.ok(copy.includes('namespace==chosenOrigin'));
  assert.ok(copy.includes('Localizations.localeOf(context)'));
  assert.ok(copy.includes('if(sameRequest())setState(()=>_copy=updated)'));
  const list=locale.slice(locale.indexOf('Future<void> load('),locale.indexOf('@override void didChangeDependencies'));
  assert.ok(list.includes('epoch==_sourceEpoch'));
  assert.ok(list.includes('if(sameRequest())setState(()=>_languages=entries)'));
});

import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const source=readFileSync(new URL(
 '../packages/features/fable_localization/lib/src/languages_page.dart',
 import.meta.url),'utf8');

test('RC322 external verified BackendApiGateway can read languages without hardcoded Fable endpoint',()=>{
 assert.ok(source.includes("widget.injectedGateway!=null||chosenOrigin.isNotEmpty"));
 assert.ok(source.includes("widget.contract.supports('languages.list')"));
 assert.ok(source.includes("bool get copySupported=>chosenOrigin.isNotEmpty"));
});
test('RC322 switching only the app locale cannot strand an in-flight client copy update',()=>{
 const copy=source.slice(source.indexOf('Future<void> checkCopy('),
   source.indexOf('Future<void> load('));
 const updates=source.slice(source.indexOf('@override void didChangeDependencies()'),
   source.indexOf('@override void dispose()'));
 assert.ok(copy.includes('final copyEpoch=_copyEpoch;'));
 assert.ok(copy.includes('copyEpoch==_copyEpoch'));
 for(const required of [
  '_copyEpoch++','_checkingCopy=false','_copy=null','_copyError=null',
  'WidgetsBinding.instance.addPostFrameCallback',
 ]){
  assert.ok(updates.includes(required),'locale change needs '+required);
 }
 assert.ok(!updates.includes('_languages=null'),'public language list must remain usable');
});
test('RC322 contract/transport/origin rebind refreshes copy after frame and discards stale callbacks',()=>{
 const update=source.slice(source.indexOf('@override void didUpdateWidget('),
   source.indexOf('String get chosenOrigin'));
 for(const required of [
  '_sourceEpoch++','_copyEpoch++','_client?.dispose()',
  '_languages=null;_copy=null','_lastCopyLocale=locale',
  'WidgetsBinding.instance.addPostFrameCallback',
 ]){
  assert.ok(update.includes(required),'source change needs '+required);
 }
});

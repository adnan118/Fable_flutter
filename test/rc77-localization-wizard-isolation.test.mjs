import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

const app=readFileSync(new URL('../lib/src/app.dart',import.meta.url),'utf8');
const policy=readFileSync(new URL('../lib/src/generated/language_policy.dart',import.meta.url),'utf8');
const core=readFileSync(new URL('../packages/fable_core/lib/fable_core.dart',import.meta.url),'utf8');
const localeScope=readFileSync(new URL('../packages/fable_core/lib/src/fable_app_locale_scope.dart',import.meta.url),'utf8');
test('app-level language selection survives removing optional Notifications',()=>{
 const permanent=app.split('// FABLE_PUSH_IMPORT_BEGIN')[0];
 assert.match(permanent,/import 'dart:async';/);
 assert.equal(app.match(/import 'dart:async';/g)?.length,1);
 assert.match(app,/_restoreSavedLocale\(\)/);
 assert.match(app,/_localeWriteQueue\.then/);
 assert.match(app,/_localeStore\.save\(/);
 assert.match(app,/onSelect:\(tag\)=>unawaited\(_selectLocale/);
});
test('selected UI locale is grounded in generated UI policy, not Fable route',()=>{
 assert.match(policy,/static const List<String> localeTags/);
 assert.match(app,/FableLanguagePolicy\.localeTags/);
 assert.match(core,/export 'src\/fable_locale_preference\.dart';/);
 assert.match(core,/export 'src\/fable_app_locale_scope\.dart';/);
 assert.match(localeScope,/bool supports\(String tag\)=>allowedTags\.contains\(tag\)/);
 assert.doesNotMatch(localeScope,/\/languages|fable\/api|\/auth/);
});

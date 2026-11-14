import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const read=name=>readFileSync(new URL('../'+name,import.meta.url),'utf8');
const code=read('packages/features/fable_media/lib/src/media_upload_repository.dart');
const dart=read('packages/features/fable_media/test/media_identity_transfer_rc110_test.dart');
const runner=read('tools/fable-one-command.mjs');
const from=code.indexOf('static MediaUploadProgress _progress(');
const to=code.indexOf('static void _fileMatches(',from);
const body=code.slice(from,to);

test('RC229 backend media progress must be a finite number',()=>{
  assert.ok(from>=0&&to>from);
  assert.match(body,/pct is! num \|\| !pct\.toDouble\(\)\.isFinite/);
});
test('RC229 refuses percentages outside zero to one hundred',()=>{
  assert.match(body,/pct<0 \|\| pct>100/);
  assert.match(body,/bytes<0 \|\| bytes>total/);
});
test('RC229 mismatch in media upload total size remains denied',()=>{
  assert.match(body,/total!=expectedSize/);
  assert.match(body,/throw const FormatException\('Inconsistent backend progress'\)/);
});
test('RC229 upload prepare validates progress before exposing state',()=>{
  const start=code.indexOf('Future<Map<String,dynamic>> _prepare(');
  const end=code.indexOf('Future<Map<String,dynamic>> status(',start);
  const content=code.slice(start,end);
  assert.ok(content.indexOf('_progress(state,size)')<content.lastIndexOf('return state;'));
});
test('RC229 Dart regressions reject nonfinite data before starting a chunk',()=>{
  assert.ok(dart.includes('double.nan'));
  assert.ok(dart.includes('double.infinity'));
  assert.ok(dart.includes('double.negativeInfinity'));
  assert.ok(dart.includes('invalid server progress never starts a media chunk'));
  assert.ok(dart.includes("gateway.calls.where((id)=>id=='media.upload.chunk')"));
  assert.equal((dart.match(/test\('/g)||[]).length,11);
});
test('RC229 same single pnpm command runs actual upload regressions',()=>{
  assert.ok(runner.includes('packages/features/fable_media/test/media_identity_transfer_rc110_test.dart'));
});

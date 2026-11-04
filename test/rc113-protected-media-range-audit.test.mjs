import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

const core=readFileSync('packages/fable_core/lib/src/fable_api.dart','utf8');
const gateway=readFileSync('packages/fable_core/lib/src/fable_auth_gateway.dart','utf8');
const repository=readFileSync('packages/features/fable_media/lib/src/protected_media_playback_repository.dart','utf8');
const simulations=readFileSync('packages/features/fable_media/test/protected_media_range_rc113_test.dart','utf8');

test('RC113 protected ranges reuse verified Fable Auth with no arbitrary headers or URLs',()=>{
  assert.ok(core.includes("op.path.replaceAll('{id}',':id')!='/media/:id/content'"));
  assert.match(core,/op\.requiresAuth/);
  assert.match(core,/adapter is! FableTransportAdapter/);
  assert.match(core,/mediaRange\.endInclusive-mediaRange\.start>=524288/);
  assert.match(core,/headers\['X-Fable-Media-Token'\]/);
  assert.match(core,/headers\['Range'\]/);
  assert.match(core,/responseType:mediaRange==null\?ResponseType\.json:ResponseType\.stream/);
  assert.match(core,/followRedirects: false/);
  assert.match(gateway,/requestProtectedContentRange/);
  assert.ok(!core.includes('playbackToken='));
});
test('RC113 byte range is verified before playback consumer sees bytes',()=>{
  for(const clause of ['response.statusCode!=206','content-range','content-length',
    "cacheControl.contains('no-store')","sink.length+part.length>expected",
    '_cancelReads();','_stillCurrent(epoch,generation)',
    'cancel.isCancelled','_contentOperationId']){
    assert.ok(repository.includes(clause),clause);
  }
  assert.ok(!repository.includes('SharedPreferences'));
  assert.ok(!repository.includes('writeAsBytes'));
});
test('RC113 HTTP mocks exercise identity, refresh/end, URLs and overrun',()=>{
  for(const scenario of ['missing or public content','private media header',
    'oversized request','larger response payload','identity change while bytes',
    'end invalidates pending read','refresh blocks old view',
    'playback POST operation']){
    assert.ok(simulations.includes(scenario),scenario);
  }
});

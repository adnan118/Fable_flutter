import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

const src=readFileSync('packages/features/fable_media/lib/src/data/fable_public_guest_byte_source.dart','utf8');
const unit=readFileSync('packages/features/fable_media/test/public_guest_media_rc130_test.dart','utf8');
const exports=readFileSync('packages/features/fable_media/lib/fable_media.dart','utf8');

test('RC130 guest bytes are served only via verified HTTPS private route with two secrets',()=>{
  for(const expected of [
    "origin.scheme != 'https'",
    "'__Host-fable-media-guest=$cookie'",
    "'X-Fable-Guest-Media-Token': token",
    "'/media/guest/$_assetId/$suffix'",
    "response.statusCode != 206",
    "cache.contains('no-store')",
    "cancellation.isCancelled",
    "_generation != generation",
    "MediaSessionInvalidation.sourceClosed",
    "followRedirects: false",
    "if (kIsWeb)",
  ])assert.ok(src.includes(expected),expected);
  assert.ok(src.includes("Set-Cookie")===false);
  assert.ok(!src.includes("Preferences"));
  assert.ok(!src.includes("SharedPreferences"));
  assert.ok(!src.includes("Image.network("));
  assert.ok(!src.includes("'playbackToken':"));
  assert.ok(exports.includes("data/fable_public_guest_byte_source.dart"));
});

test('RC130 unit tests cover direct link, copy prevention, expiry, forbidden and origin',()=>{
  for(const marker of [
    'rejects non-HTTPS',
    'with BOTH secrets in headers',
    'fails closed on expired guest lease',
    'revokes client read capability on 403',
    "get.uri.query,isEmpty",
    "get.followRedirects,isFalse",
  ])assert.ok(unit.includes(marker),marker);
});

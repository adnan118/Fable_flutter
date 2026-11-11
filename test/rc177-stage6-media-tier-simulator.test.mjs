import test from 'node:test';
import assert from 'node:assert/strict';
import {randomBytes} from 'node:crypto';
import {CHUNK_BYTES,MAX_RANGE_BYTES,SimulatedMediaTierServer} from '../tools/rc177-stage6-media-tier-simulator.mjs';

const fixture=(tier='LOCAL',size=CHUNK_BYTES*5+37)=>{
 const s=new SimulatedMediaTierServer();s.allow('user-A');
 const bytes=randomBytes(size);s.upload({id:'asset-A',owner:'user-A',bytes,tier});
 const {id,credential}=s.open({assetId:'asset-A',user:'user-A'});
 const read=(start,end,pause)=>s.range({sessionId:id,credential,start,end,pause});
 return {s,bytes,id,credential,read};
};
const pause=()=>{let release;const promise=new Promise(r=>release=r);return {promise,release};};

test('01 NONE still requires private playback grants and returns exact bounded ranges',async()=>{
 const {s,bytes,read}=fixture('NONE');
 assert.deepEqual(await read(0,123),bytes.subarray(0,124));
 s.allow('user-A',false);await assert.rejects(read(0,3),/MEDIA_FORBIDDEN/);
});
test('02 LOCAL AES-GCM stores ciphertext only, and delivers exact full file via 512KiB ranges',async()=>{
 const {s,bytes,read}=fixture();const asset=s.assets.get('asset-A');
 assert.equal(asset.raw,null);assert.equal(asset.tier,'LOCAL');
 assert.notDeepEqual(asset.chunks[0].ciphertext,bytes.subarray(0,CHUNK_BYTES));
 const segments=[];
 for(let start=0;start<bytes.length;start+=MAX_RANGE_BYTES)
  segments.push(await read(start,Math.min(start+MAX_RANGE_BYTES,bytes.length)-1));
 assert.deepEqual(Buffer.concat(segments),bytes);
});
test('03 authenticated Range crossing chunk boundary returns precisely requested bytes',async()=>{
 const {bytes,read}=fixture();
 assert.deepEqual(await read(CHUNK_BYTES-27,CHUNK_BYTES+73),bytes.subarray(CHUNK_BYTES-27,CHUNK_BYTES+74));
});
test('04 oversized, malformed and out-of-file ranges fail closed',async()=>{
 const {read,bytes}=fixture();
 for(const [a,b] of [[0,MAX_RANGE_BYTES],[2,1],[-1,4],[0,bytes.length],[0,Infinity],[1.5,9]])
  await assert.rejects(read(a,b),/INVALID_RANGE|RANGE_NOT_SATISFIABLE/);
});
test('05 corrupt ciphertext or GCM tag cannot yield plaintext',async()=>{
 const {s,read}=fixture();const c=s.assets.get('asset-A').chunks[0];
 c.ciphertext[2]^=1;await assert.rejects(read(0,100),/MEDIA_AUTH_FAILED/);
 c.ciphertext[2]^=1;c.tag[0]^=1;await assert.rejects(read(0,100),/MEDIA_AUTH_FAILED/);
});
test('06 tampering nonce or authenticated context rejects without bytes',async()=>{
 const {s,read}=fixture();const asset=s.assets.get('asset-A');
 asset.chunks[0].nonce[0]^=1;await assert.rejects(read(0,10),/MEDIA_AUTH_FAILED/);
 asset.chunks[0].nonce[0]^=1;asset.generation++;
 await assert.rejects(read(0,10),/MEDIA_RESOURCE_CHANGED/);
});
test('07 cross-index ciphertext swap is detected via AAD',async()=>{
 const {s,read}=fixture();const a=s.assets.get('asset-A');
 [a.chunks[0],a.chunks[1]]=[a.chunks[1],a.chunks[0]];
 await assert.rejects(read(0,CHUNK_BYTES+8),/MEDIA_AUTH_FAILED/);
});
test('08 missing key blocks access, exact synthetic key restoration reopens it',async()=>{
 const {s,read,bytes}=fixture();const backup=Buffer.from(s.serverKeys.get('asset-A'));
 s.loseKey('asset-A');await assert.rejects(read(0,99),/MEDIA_KEY_UNAVAILABLE/);
 s.restoreTestKey('asset-A',randomBytes(32));await assert.rejects(read(0,99),/MEDIA_AUTH_FAILED/);
 s.restoreTestKey('asset-A',backup);assert.deepEqual(await read(0,99),bytes.subarray(0,100));
});
test('09 NONE cannot be treated as encrypted LOCAL by UI',()=>{
 const {s}=fixture('NONE');assert.deepEqual(s.metadata('asset-A','user-A'),{
 id:'asset-A',tier:'NONE',bytes:CHUNK_BYTES*5+37,access:'PROTECTED',clientReceivesKey:false});
});
test('10 DRM selected without real licensed packager does not downgrade to NONE or LOCAL',()=>{
 const s=new SimulatedMediaTierServer();
 assert.throws(()=>s.upload({id:'drm',owner:'user-A',bytes:Buffer.from('x'),tier:'DRM'}),
 /DRM_LICENSED_PACKAGER_REQUIRED/);
 assert.equal(s.assets.has('drm'),false);
});
test('11 unknown tiers and malformed metadata are rejected',()=>{
 const s=new SimulatedMediaTierServer();
 for(const tier of ['clear','local','AES','DRM-FAKE'])
 assert.throws(()=>s.upload({id:'a',owner:'A',bytes:Buffer.from('hi'),tier}),/UNKNOWN_TIER/);
});
test('12 user B cannot open user A protected media, regardless of B permissions',()=>{
 const {s}=fixture();s.allow('user-B');
 assert.throws(()=>s.open({assetId:'asset-A',user:'user-B'}),/MEDIA_NOT_FOUND/);
});
test('13 expired playback sessions cannot read encrypted media',async()=>{
 let now=100000;
 const s=new SimulatedMediaTierServer({now:()=>now});s.allow('A');
 s.upload({id:'a',owner:'A',bytes:Buffer.from('classified'),tier:'LOCAL'});
 const {id,credential}=s.open({assetId:'a',user:'A',ttlMs:2000});now+=2000;
 await assert.rejects(s.range({sessionId:id,credential,start:0,end:3}),/SESSION_EXPIRED/);
});
test('14 revoked session while mock network pauses is rejected before decryption',async()=>{
 const {s,id,read}=fixture(),p=pause();const pending=read(0,4,p.promise);
 s.end(id);p.release();await assert.rejects(pending,/SESSION_UNAUTHORIZED/);
});
test('15 permission revocation during paused Range blocks access',async()=>{
 const {s,read}=fixture(),p=pause();const pending=read(0,4,p.promise);
 s.allow('user-A',false);p.release();await assert.rejects(pending,/MEDIA_FORBIDDEN/);
});
test('16 replaced asset generation invalidates prior session without old bytes',async()=>{
 const {s,read}=fixture();s.upload({id:'asset-A',owner:'user-A',bytes:Buffer.from('next'),tier:'LOCAL',generation:2});
 await assert.rejects(read(0,3),/MEDIA_RESOURCE_CHANGED/);
});
test('17 wrong session credential is refused; no token or encryption key in public metadata',async()=>{
 const {s,id}=fixture();
 await assert.rejects(s.range({sessionId:id,credential:'stolen',start:0,end:3}),/SESSION_UNAUTHORIZED/);
 const view=JSON.stringify(s.metadata('asset-A','user-A'));
 for(const secret of ['credential','nonce','ciphertext','key','url','storageKey'])
 assert.equal(Object.hasOwn(JSON.parse(view),secret),false);
});
test('18 truncated or missing chunks reject range',async()=>{
 const {s,read}=fixture(),asset=s.assets.get('asset-A');asset.chunks.pop();
 await assert.rejects(read(0,7),/MEDIA_AUTH_FAILED/);
});

test('19 metadata requires matching identity and current access policy',()=>{
 const {s}=fixture();s.allow('user-B');
 assert.throws(()=>s.metadata('asset-A','user-B'),/MEDIA_NOT_FOUND/);
 s.allow('user-A',false);
 assert.throws(()=>s.metadata('asset-A','user-A'),/MEDIA_FORBIDDEN/);
});

test('20 replacing an asset without advancing the generation is blocked',async()=>{
 const {s,read,bytes}=fixture();
 assert.throws(()=>s.upload({id:'asset-A',owner:'user-A',bytes:Buffer.from('changed'),tier:'LOCAL',generation:1}),
   /STALE_ASSET_GENERATION/);
 assert.deepEqual(await read(0,29),bytes.subarray(0,30));
});

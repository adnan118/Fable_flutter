import test from 'node:test';import assert from 'node:assert/strict';
import {SimulatedOfflineSync} from '../tools/rc178-stage6-offline-sync-simulator.mjs';
const hash='c'.repeat(64);
const scope={origin:'https://demo.sim.invalid',projectId:'test-sim-not-real',accountId:'alice',entityId:'entity-1',contractHash:hash};
const grant={id:'content.note.update',method:'PATCH',contractHash:hash,idempotencyVerified:true,conflictProtocolVerified:true};
const create=(overrides={})=>new SimulatedOfflineSync({scope,grants:[grant],approvedReads:['content.note.list'],...overrides});
const add=s=>s.enqueue({operationId:grant.id,resourceId:'note-1',body:{text:'draft'},baseVersion:'v1'});
const other={...scope,accountId:'bob'};
test('01 opt-in simulation disallows unidentified or non-HTTPS project scope',()=>{
 assert.throws(()=>create({scope:{...scope,origin:'http://unsafe.invalid'}}),/UNVERIFIED_SCOPE/);
 assert.throws(()=>create({scope:{...scope,contractHash:null}}),/UNVERIFIED_SCOPE/);
});
test('02 no mutation without exact preapproved per-operation Backend contract grant',()=>{
 assert.throws(()=>create({grants:[{...grant,idempotencyVerified:false}]}),/UNVERIFIED_WRITE_GRANT/);
 assert.throws(()=>create({grants:[{...grant,contractHash:'d'.repeat(64)}]}),/UNVERIFIED_WRITE_GRANT/);
 assert.throws(()=>create({grants:[]}).enqueue({operationId:grant.id,resourceId:'x',body:{x:1},baseVersion:'v1'}),/UNAPPROVED_WRITE/);
});
test('03 payment, booking, account and token cannot be silently cached or queued',()=>{
 for(const id of ['payments.capture','booking.confirm','auth.change-password'])
  assert.throws(()=>create({grants:[{...grant,id}]}),/UNVERIFIED_WRITE_GRANT/);
 assert.throws(()=>create({approvedReads:['account.me']}),/UNSAFE_CACHE_GRANT/);
 assert.throws(()=>add(create({grants:[]})),/UNAPPROVED_WRITE/);
 assert.throws(()=>create().enqueue({operationId:grant.id,resourceId:'n',body:{refreshToken:'secret'},baseVersion:'v1'}),/UNAPPROVED_WRITE/);
});
test('04 missing ETag/base version prevents offline mutation',()=>{
 const s=create();assert.throws(()=>s.enqueue({operationId:grant.id,resourceId:'n',body:{text:'x'}}),/UNAPPROVED_WRITE/);
});
test('05 cached GET data becomes stale and never becomes a confirmed server ACK',()=>{
 let now=10000;const s=create({now:()=>now});
 s.putCache({operationId:'content.note.list',key:'home',data:{items:['a']},ttlMs:1000});
 assert.deepEqual(s.readCache({operationId:'content.note.list',key:'home'}).data,{items:['a']});
 assert.equal(s.readCache({operationId:'content.note.list',key:'home'}).confirmed,false);
 now+=1000;assert.equal(s.readCache({operationId:'content.note.list',key:'home'}),null);
 assert.equal(s.readCache({operationId:'content.note.list',key:'home',allowStale:true}).stale,true);
});
test('06 offline queue persists without executing external mutation',async()=>{
 const s=create();s.setOnline(false);const id=add(s);let calls=0;
 assert.equal(await s.flush(async()=>{calls++;return {status:'ack',serverVersion:'v2'}}),0);
 assert.equal(calls,0);assert.equal(s.pending()[0].id,id);
});
test('07 valid ack with server version clears row and grants success',async()=>{
 const s=create();add(s);s.setOnline(true);
 assert.equal(await s.flush(async()=>({status:'ack',serverVersion:'v2'})),1);
 assert.equal(s.pending().length,0);
});
test('08 ack without verified version is quarantined for review',async()=>{
 const s=create();add(s);s.setOnline(true);
 assert.equal(await s.flush(async()=>({status:'ack'})),0);
 assert.equal(s.reviews()[0].reason,'ACK_NO_VERSION');
});
test('09 unknown network timeout retries with original idempotency key only',async()=>{
 let now=20000;const s=create({now:()=>now});const id=add(s);s.setOnline(true);const keys=[];
 await s.flush(async(_,ctx)=>{keys.push(ctx.idempotencyKey);throw Error('timeout')});
 assert.equal(s.pending()[0].id,id);assert.equal(s.pending()[0].attempts,1);
 assert.equal(await s.flush(async()=>{throw Error('must not replay before backoff')}),0);
 now+=30000;
 await s.flush(async(_,ctx)=>{keys.push(ctx.idempotencyKey);return {status:'ack',serverVersion:'v3'}});
 assert.deepEqual(keys,[id,id]);assert.equal(s.pending().length,0);
});
test('10 server 409 conflict goes to manual review, never last-write-wins',async()=>{
 const s=create();add(s);s.setOnline(true);
 await s.flush(async()=>({status:'conflict'}));
 assert.equal(s.reviews()[0].reason,'CONFLICT');
});
test('11 401/403 keeps pending but pauses sync until authorization recovered',async()=>{
 const s=create();add(s);s.setOnline(true);
 await s.flush(async()=>({status:'unauthorized'}));
 assert.equal(s.pending().length,1);assert.equal(s.reviews().length,0);
});
test('12 permission revoked before flush quarantines queued item',async()=>{
 const s=create();add(s);s.setOnline(true);s.revokeGrant(grant.id);
 await s.flush(async()=>{throw Error('must not submit')});
 assert.equal(s.reviews()[0].reason,'GRANT_REVOKED');
});
test('13 A to B switch cannot dispatch A queue or read cached data',async()=>{
 const s=create();add(s);s.setOnline(true);s.scopeChanged(other);let calls=0;
 await assert.rejects(s.flush(async()=>{calls++}),/STALE_IDENTITY/);
 assert.equal(calls,0);assert.throws(()=>s.readCache({operationId:'content.note.list',key:'home'}),/STALE_IDENTITY/);
});
test('14 A to B during await cannot ACK A against B',async()=>{
 const s=create();add(s);s.setOnline(true);let release;
 const barrier=new Promise(r=>release=r);
 const future=s.flush(async()=>{await barrier;return {status:'ack',serverVersion:'v2'}});
 s.scopeChanged(other);release();await future;
 assert.equal(s.pending().length,1);
});
test('15 duplicate foreground triggers use a single-flight promise',async()=>{
 const s=create();add(s);s.setOnline(true);let calls=0;
 const [a,b]=await Promise.all([s.flush(async()=>{calls++;return {status:'ack',serverVersion:'v2'}}),s.flush(async()=>{calls++;return {status:'ack',serverVersion:'v2'}})]);
 assert.equal(a,1);assert.equal(b,1);assert.equal(calls,1);
});
test('16 OS background scheduler is best-effort: scheduling alone does not send',async()=>{
 const s=create();add(s);s.setOnline(true);let calls=0;
 const job=s.scheduleBackground();assert.equal(job.guaranteed,false);
 assert.equal(await s.runScheduled(async()=>{calls++}, {systemGranted:false}),0);
 assert.equal(calls,0);
 assert.equal(await s.runScheduled(async()=>{calls++;return {status:'ack',serverVersion:'v3'}},{systemGranted:true}),1);
 assert.equal(calls,1);
});
test('17 scope cleanup on confirmed logout purges cache and outbox',()=>{
 const s=create();add(s);s.putCache({operationId:'content.note.list',key:'a',data:{x:1},ttlMs:1000});
 s.clearOnLogout();assert.equal(s.pending().length,0);
 assert.throws(()=>s.readCache({operationId:'content.note.list',key:'a'}),/STALE_IDENTITY/);
});
test('18 queue capacity prevents unbounded pending writes',()=>{
 const s=create({maxPending:1});add(s);assert.throws(()=>add(s),/QUEUE_LIMIT/);
});
test('19 irreversible failure results in review rather than fake success',async()=>{
 const s=create();add(s);s.setOnline(true);await s.flush(async()=>({status:'refused'}));
 assert.equal(s.reviews()[0].reason,'REFUSED');
});
test('20 secret field nested inside cache data is rejected',()=>{
 const s=create();assert.throws(()=>s.putCache({operationId:'content.note.list',key:'a',data:{nested:{otp:'123456'}},ttlMs:1000}),/UNAPPROVED_CACHE/);
});
test('21 repeated unknown outcomes exhaust bounded retry budget',async()=>{
 let now=100000;const s=create({now:()=>now});add(s);s.setOnline(true);
 for(let i=0;i<7;i++){
  await s.flush(async()=>({status:'timeout'}));now+=3600000;
 }
 assert.equal(s.pending().length,0);
 assert.equal(s.reviews()[0].reason,'RETRY_EXHAUSTED');
});
test('22 offline cached data are defensive copies, not mutable shared server state',()=>{
 const s=create();const input={items:[{label:'stable'}]};
 s.putCache({operationId:'content.note.list',key:'home',data:input,ttlMs:1000});
 input.items[0].label='tampered';
 const cached=s.readCache({operationId:'content.note.list',key:'home'});
 assert.equal(cached.data.items[0].label,'stable');
 cached.data.items[0].label='client-edited';
 assert.equal(s.readCache({operationId:'content.note.list',key:'home'}).data.items[0].label,'stable');
});
test('23 wrong account cannot enqueue under previous trusted scope',()=>{
 const s=create();s.scopeChanged(other);
 assert.throws(()=>add(s),/STALE_IDENTITY/);
});

import test from 'node:test';
import assert from 'node:assert/strict';
import {SimulatedFableServer,SimulatedFlutterClient,syntheticDevice,signSimulatedDpop}
 from '../tools/rc175-stage6-dpop-auth-simulator.mjs';

const setup=()=>{
 const server=new SimulatedFableServer();
 const client=new SimulatedFlutterClient(server);
 client.login('user-A');return {server,client};
};
const proof=(server,client,overrides={})=>signSimulatedDpop({
 device:client.device,method:'GET',htu:server.origin+'/permissions/me',
 accessToken:client.session.accessToken,...overrides});
const verify=(server,client,signed,overrides={})=>server.verifyRequest({
 sessionId:client.session.sessionId,method:'GET',path:'/permissions/me',
 accessToken:client.session.accessToken,proof:signed,...overrides});

test('RC175 01 synthetic P-256 ES256 P1363 proof authenticates scope',()=>{
 const {server,client}=setup();
 assert.equal(verify(server,client,proof(server,client)).userId,'user-A');
});
test('RC175 02 stolen access token and installation label without private key fail',()=>{
 const {server,client}=setup();
 assert.throws(()=>verify(server,client,proof(server,client,{
   device:syntheticDevice()})),/SENDER_KEY_MISMATCH/);
});
test('RC175 03 duplicated proof jti is rejected',()=>{
 const {server,client}=setup(),signed=proof(server,client);
 verify(server,client,signed);
 assert.throws(()=>verify(server,client,signed),/PROOF_REPLAY/);
});
test('RC175 04 wrong method, HTU and access token digest fail',()=>{
 const {server,client}=setup();
 assert.throws(()=>verify(server,client,proof(server,client,{method:'POST'})),
   /PROOF_SCOPE_MISMATCH/);
 assert.throws(()=>verify(server,client,proof(server,client,{
   htu:'https://other.sim.invalid/permissions/me'})),/PROOF_SCOPE_MISMATCH/);
 assert.throws(()=>verify(server,client,proof(server,client,{
   accessToken:'z'.repeat(43)})),/PROOF_SCOPE_MISMATCH/);
});
test('RC175 05 expired signed proof is rejected',()=>{
 const {server,client}=setup();
 assert.throws(()=>verify(server,client,proof(server,client,{
   iat:Math.floor(Date.now()/1000)-301})),/PROOF_EXPIRED/);
});
test('RC175 06 malformed/forged proof rejected',()=>{
 const {server,client}=setup();
 assert.throws(()=>verify(server,client,'a.b.c'),/INVALID_PROOF/);
 const parts=proof(server,client).split('.');
 parts[2]='A'.repeat(parts[2].length);
 assert.throws(()=>verify(server,client,parts.join('.')),/BAD_SIGNATURE/);
});
test('RC175 07 concurrent refresh uses one rotation and valid next access',async()=>{
 const {client}=setup(),prior=client.session;
 const [a,b]=await Promise.all([client.refresh(),client.refresh()]);
 assert.strictEqual(a,b);assert.notEqual(a.refreshToken,prior.refreshToken);
 assert.equal(client.request('GET','/permissions/me').userId,'user-A');
});
test('RC175 08 refresh replay revokes affected session',async()=>{
 const {server,client}=setup(),prior={...client.session};
 await client.refresh();
 assert.throws(()=>server.refresh({sessionId:prior.sessionId,
   refreshToken:prior.refreshToken,device:client.device}),/REFRESH_REPLAY_REVOKED/);
 assert.throws(()=>client.request('GET','/permissions/me'),/SESSION_UNAUTHORIZED/);
});
test('RC175 09 logout revokes server token, not just UI',()=>{
 const {server,client}=setup(),prior={...client.session};
 const signed=proof(server,client);client.logout();
 assert.throws(()=>server.verifyRequest({sessionId:prior.sessionId,
   method:'GET',path:'/permissions/me',accessToken:prior.accessToken,
   proof:signed}),/SESSION_UNAUTHORIZED/);
});
test('RC175 10 media grants can be withdrawn immediately in model',async()=>{
 const {server,client}=setup();
 server.putMedia('asset-1','user-A','synthetic-media');
 await assert.rejects(client.readMedia('asset-1'),/MEDIA_FORBIDDEN/);
 server.setGrants('user-A',['media.access','media.read']);
 assert.equal((await client.readMedia('asset-1')).toString(),'synthetic-media');
 server.setGrants('user-A',[]);
 await assert.rejects(client.readMedia('asset-1'),/MEDIA_FORBIDDEN/);
});
test('RC175 11 user B never reads private bytes belonging to A',async()=>{
 const {server,client}=setup();
 server.putMedia('asset-1','user-A','secret');
 server.setGrants('user-A',['media.access','media.read']);
 client.login('user-B');
 server.setGrants('user-B',['media.access','media.read']);
 await assert.rejects(client.readMedia('asset-1'),/MEDIA_NOT_FOUND/);
});
test('RC175 12 delayed media read for A discarded after identity A to B',async()=>{
 const {server,client}=setup();
 server.putMedia('asset-1','user-A','private');
 server.setGrants('user-A',['media.access','media.read']);
 let release;const pause=new Promise(resolve=>release=resolve);
 const pending=client.readMedia('asset-1',pause);
 client.login('user-B');release();
 await assert.rejects(pending,/STALE_IDENTITY/);
});
test('RC175 13 JWT header exposes public JWK only, never private key',()=>{
 const {server,client}=setup();
 const header=JSON.parse(Buffer.from(proof(server,client).split('.')[0],'base64url'));
 assert.equal(header.jwk.d,undefined);
 assert.equal(header.alg,'ES256');assert.equal(header.typ,'dpop+jwt');
});
test('RC175 14 HTTP HTU or query-bearing HTU cannot be signed',()=>{
 const {client}=setup();
 for(const htu of ['http://fable.sim.invalid/a','https://fable.sim.invalid/a?q=1'])
   assert.throws(()=>signSimulatedDpop({device:client.device,method:'GET',htu,
     accessToken:client.session.accessToken}),/INVALID_PROOF_URL/);
});


test('RC175 15 account A session is denied immediately after A to B switch',()=>{
 const {server,client}=setup(),prior={...client.session};
 const signed=proof(server,client);
 client.login('user-B');
 assert.throws(()=>server.verifyRequest({sessionId:prior.sessionId,method:'GET',
   path:'/permissions/me',accessToken:prior.accessToken,proof:signed}),
   /SESSION_UNAUTHORIZED/);
});
test('RC175 16 an A refresh scheduled before switch cannot resurrect A after B login',async()=>{
 const {client}=setup(),pending=client.refresh();
 client.login('user-B');
 await assert.rejects(pending,/STALE_IDENTITY/);
 assert.equal(client.session.userId,'user-B');
});

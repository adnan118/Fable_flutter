import test from 'node:test';
import assert from 'node:assert/strict';
import { FableWebAuth } from '../interop/web-admin/fable-web-admin-auth.mjs';

const origin='https://fable.example';
const future=()=>new Date(Date.now()+600000).toISOString().replace(/\.\d{3}Z$/,'Z');
const UUID='550e8400-e29b-41d4-a716-446655440001';
const cookie=()=>({csrfToken:'s'.repeat(32),transport:'cookie',
  expiresAt:future(),mustChangePassword:false});
const challenge=(provider)=>({provider,state:'a'.repeat(32),nonce:'b'.repeat(32),expiresInMs:300000});
const factor=()=>({requiresTwoFactor:true,twoFactorToken:'c'.repeat(64),
  methods:['EMAIL_OTP'],expiresAt:future()});

function env(routes,opts={}){
  const seen=[];
  const fetchImpl=async(url,options)=>{
    seen.push({path:new URL(url).pathname,options,body: options.body?JSON.parse(options.body):null});
    const handler=routes[new URL(url).pathname];
    assert.ok(handler, 'unexpected route '+url);
    const reply=await handler(seen.at(-1));
    if(reply?.status)return new Response(JSON.stringify({success:false,code:reply.code}),{
      status:reply.status,headers:{'Content-Type':'application/json'}});
    return new Response(JSON.stringify({success:true,data:reply}),{
      status:200,headers:{'Content-Type':'application/json'}});
  };
  return {seen, client:new FableWebAuth({baseUrl:origin,fetchImpl,
    browserOrigin:origin,...opts})};
}

test('web/login uses same-origin cookies, not bearer tokens or client-supplied origin',async()=>{
 const {seen,client}=env({'/auth/web/login':()=>cookie()});
 const result=await client.login({identifier:'alice',password:'secret'});
 assert.equal(result.authenticated,true);
 assert.equal(result.transport,'cookie');
 assert.equal(seen[0].options.credentials,'include');
 assert.equal(seen[0].options.mode,'same-origin');
 assert.equal(seen[0].options.headers.Authorization,undefined);
 assert.equal(seen[0].options.headers.Origin,undefined);
 assert.equal(seen[0].body.clientType,undefined);
 assert.equal(seen[0].body.password,'secret');
});

test('web/refresh sends CSRF token from safe cookie envelope and cannot expose access secret',async()=>{
 const {seen,client}=env({'/auth/web/login':()=>cookie(),'/auth/web/refresh':()=>cookie()});
 await client.login({identifier:'alice',password:'secret'});
 await client.refresh();
 assert.equal(seen[1].path,'/auth/web/refresh');
 assert.equal(seen[1].options.headers['X-CSRF-Token'],'s'.repeat(32));
 assert.equal(seen[1].options.body,undefined);
});

test('web/refresh fails closed without CSRF even when refresh cookie might exist',async()=>{
 const {seen,client}=env({'/auth/web/refresh':()=>cookie()});
 await assert.rejects(client.refresh(),/CSRF/);
 assert.equal(seen.length,0);
});

test('web/social/google challenges and authenticates only matching SDK nonce',async()=>{
 const {client,seen}=env({
   '/auth/social/challenge':()=>challenge('google'),
   '/auth/web/social/google':()=>cookie(),
 });
 const pending=await client.startSocial('google');
 await assert.rejects(client.completeSocial(pending,{nonce:'WRONG',idToken:'x'.repeat(40)}),/nonce/);
 const second=await client.startSocial('google');
 const res=await client.completeSocial(second,{nonce:'b'.repeat(32),idToken:'x'.repeat(40)});
 assert.equal(res.authenticated,true);
 assert.equal(seen.filter(x=>x.path==='/auth/web/social/google').length,1);
 assert.equal(seen.at(-1).body.clientType,undefined);
});

test('web/social/apple carries authorization code and does not store provider token',async()=>{
 const {client,seen}=env({
   '/auth/social/challenge':()=>challenge('apple'),
   '/auth/web/social/apple':()=>cookie(),
 });
 const pending=await client.startSocial('apple');
 const result=await client.completeSocial(pending,{nonce:'b'.repeat(32),
   identityToken:'x'.repeat(60),authorizationCode:'a'.repeat(32)});
 assert.equal(result.authenticated,true);
 assert.equal(seen.at(-1).body.authorizationCode.length,32);
 assert.equal('accessToken' in result,false);
});

test('web 2FA requires the separate OTP and never creates cookies at first factor',async()=>{
 const {client,seen}=env({
   '/auth/web/login':()=>factor(),
   '/auth/web/2fa/login/request':()=>({challengeId:UUID}),
   '/auth/web/2fa/login/complete':()=>cookie(),
 });
 const pending=await client.login({identifier:'alice',password:'secret'});
 assert.equal(pending.requiresTwoFactor,true);
 assert.equal('authenticated' in pending,false);
 const req=await client.requestSecondFactor(pending.challenge,{preferredChannel:'EMAIL'});
 assert.equal(seen[1].body.twoFactorToken,'c'.repeat(64));
 const done=await client.completeSecondFactor(req,'123456');
 assert.equal(done.authenticated,true);
 await assert.rejects(client.completeSecondFactor(req,'123456'),/Unknown|replayed/);
});

test('web OTP LOGIN is purpose-bound and reject RESET proof before web/otp/login/complete',async()=>{
 const {client,seen}=env({
   '/auth/otp/public/request':()=>({accepted:true,deliveryStatus:'QUEUED',challengeId:UUID,expiresAt:future()}),
   '/auth/otp/public/verify':()=>({verified:true,challengeId:UUID,purpose:'PASSWORD_RESET'}),
   '/auth/web/otp/login/complete':()=>cookie(),
 });
 const requested=await client.requestLoginOtp({identifier:'alice'});
 await assert.rejects(client.verifyLoginOtp(requested,'123456'),/wrong purpose/);
 assert.equal(seen.some(x=>x.path==='/auth/web/otp/login/complete'),false);
 assert.equal(seen[0].body.purpose,'LOGIN');
});

test('web OTP LOGIN successful path and one-shot completion',async()=>{
 const {client,seen}=env({
   '/auth/otp/public/request':()=>({accepted:true,deliveryStatus:'QUEUED',challengeId:UUID,expiresAt:future()}),
   '/auth/otp/public/verify':()=>({verified:true,challengeId:UUID,purpose:'LOGIN'}),
   '/auth/web/otp/login/complete':()=>cookie(),
 });
 const pending=await client.requestLoginOtp({identifier:'alice',preferredChannel:'EMAIL'});
 const proof=await client.verifyLoginOtp(pending,'123456');
 const res=await client.completeLoginOtp(proof);
 assert.equal(res.authenticated,true);
 assert.equal(seen.at(-1).body.challengeId,UUID);
 await assert.rejects(client.completeLoginOtp(proof),/Foreign|replayed|stale/);
});

test('admin GET checks policy structure and PUT requires server version and CSRF',async()=>{
 const {client,seen}=env({
   '/auth/web/login':()=>cookie(),
   '/admin/auth/password-policy':(req)=>req.options.method==='GET'
     ? {schemaVersion:1,sourceOfTruth:'database',policy:{version:7},constraints:{},
        fields:[]} : {version:8},
 });
 await client.login({identifier:'administrator',password:'very-long-password'});
 const policy=await client.readAdminPasswordPolicy();
 assert.equal(policy.policy.version,7);
 await client.updateAdminPasswordPolicy({version:7,changes:{minLength:18,forbidCommonPasswords:true}});
 assert.equal(seen.at(-1).options.headers['If-Match'],'7');
 assert.equal(seen.at(-1).options.headers['X-CSRF-Token'],'s'.repeat(32));
 assert.equal(seen.at(-1).options.method,'PUT');
});

test('admin client cannot bypass safety floor, version or server denial',async()=>{
 const {client,seen}=env({
   '/auth/web/login':()=>cookie(),
   '/admin/auth/password-policy':()=>({status:403,code:'AUTH_RECENT_AUTH_REQUIRED'})
 });
 await client.login({identifier:'administrator',password:'long-password'});
 await assert.rejects(client.updateAdminPasswordPolicy({version:0,
   changes:{forbidCommonPasswords:false}}),/Cannot disable/);
 await assert.rejects(client.updateAdminPasswordPolicy({version:-1,
   changes:{minLength:15}}),/version/);
 await assert.rejects(client.updateAdminPasswordPolicy({version:0,
   changes:{unknownFlag:true}}),/Unsupported/);
 await assert.rejects(client.updateAdminPasswordPolicy({version:0,
   changes:{minLength:18}}),error=>error.status===403);
 assert.equal(seen.filter(x=>x.path==='/admin/auth/password-policy').length,1);
});

test('Cross-origin browser requests rejected before transport',()=>{
 assert.throws(()=>new FableWebAuth({baseUrl:'https://evil.invalid',
   browserOrigin:origin,fetchImpl:async()=>{}}),/Cross-origin/);
});

test('Backend time-policy offset ISO expiry is accepted, but an unconfirmed session is not',async()=>{
 const expiresAt=new Date(Date.now()+120000).toISOString().replace('Z','+00:00');
 const {client}=env({'/auth/web/login':()=>({...cookie(),expiresAt})});
 assert.equal((await client.login({identifier:'alice',password:'secret'})).authenticated,true);
 const {client:invalid}=env({'/auth/web/login':()=>({
   csrfToken:'x'.repeat(32),transport:'cookie',expiresAt})});
 await assert.rejects(invalid.login({identifier:'alice',password:'secret'}),/cookie session/);
});

test('admin optimistic concurrency error is surfaced rather than retried',async()=>{
 const {client,seen}=env({
  '/auth/web/login':()=>cookie(),
  '/admin/auth/password-policy':()=>({status:409,code:'SETTING_VERSION_CONFLICT'}),
 });
 await client.login({identifier:'administrator',password:'example-password'});
 await assert.rejects(client.updateAdminPasswordPolicy({version:7,changes:{minLength:20}}),
   e=>e.status===409 && e.code==='SETTING_VERSION_CONFLICT');
 assert.equal(seen.length,2);
});

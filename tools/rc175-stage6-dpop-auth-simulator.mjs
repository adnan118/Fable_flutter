/** RC175 Stage6: disposable protocol MODEL, not Flutter/Backend/native implementation. */
import {createHash,createPublicKey,generateKeyPairSync,randomBytes,sign,verify} from 'node:crypto';

const sha=value=>createHash('sha256').update(value).digest('base64url');
const token=()=>randomBytes(32).toString('base64url');
function reject(code){throw Error(code);}
function urlOk(text){
 const url=new URL(text);
 if(url.protocol!=='https:'||url.username||url.password||url.search||url.hash||
    (url.toString()!==text&&url.origin!==text))reject('INVALID_PROOF_URL');
 return url;
}
function decode(text){
 if(typeof text!=='string'||!/^[A-Za-z0-9_-]+$/.test(text))reject('INVALID_PROOF');
 const buf=Buffer.from(text,'base64url');
 if(buf.toString('base64url')!==text)reject('INVALID_PROOF');
 return JSON.parse(buf.toString('utf8'));
}
function keyId(jwk){
 if(!jwk||jwk.kty!=='EC'||jwk.crv!=='P-256'||
    typeof jwk.x!=='string'||typeof jwk.y!=='string'||Object.hasOwn(jwk,'d'))
   reject('INVALID_JWK');
 return sha(JSON.stringify({crv:jwk.crv,kty:jwk.kty,x:jwk.x,y:jwk.y}));
}
export function syntheticDevice(){
 const {privateKey,publicKey}=generateKeyPairSync('ec',{namedCurve:'prime256v1'});
 return {privateKey,jwk:publicKey.export({format:'jwk'})};
}
export function signSimulatedDpop({device,method,htu,accessToken=null,
 iat=Math.floor(Date.now()/1000),jti=token()}){
 urlOk(htu);
 const header={typ:'dpop+jwt',alg:'ES256',jwk:device.jwk};
 const payload={htu,htm:method,iat,jti,...(accessToken?{ath:sha(accessToken)}:{})};
 const encoded=obj=>Buffer.from(JSON.stringify(obj)).toString('base64url');
 const signed=encoded(header)+'.'+encoded(payload);
 return signed+'.'+sign('sha256',Buffer.from(signed),
   {key:device.privateKey,dsaEncoding:'ieee-p1363'}).toString('base64url');
}
export class SimulatedFableServer {
 constructor({origin='https://fable.sim.invalid',time=()=>Date.now()}={}){
   this.origin=urlOk(origin).origin;this.time=time;
   this.sessions=new Map();this.replay=new Set();this.grants=new Map();this.assets=new Map();
 }
 issue({userId,device}){
   const id=token(),accessToken=token(),refreshToken=token();
   const session={id,userId,publicKey:keyId(device.jwk),accessToken,refreshToken,revoked:false};
   this.sessions.set(id,session);
   return {sessionId:id,accessToken,refreshToken,userId};
 }
 verifyRequest({sessionId,method,path,accessToken,proof}){
   if(!path.startsWith('/')||path.includes('?')||path.includes('#'))reject('UNVERIFIED_ROUTE');
   const s=this.sessions.get(sessionId);
   if(!s||s.revoked||s.accessToken!==accessToken)reject('SESSION_UNAUTHORIZED');
   const parts=typeof proof==='string'?proof.split('.'):[];
   if(parts.length!==3||parts.some(p=>!p||p.length>5000))reject('INVALID_PROOF');
   let header,payload,signature,publicKey;
   try{
     header=decode(parts[0]);payload=decode(parts[1]);
     signature=Buffer.from(parts[2],'base64url');
     if(signature.length!==64||signature.toString('base64url')!==parts[2])reject('INVALID_PROOF');
     if(header.typ!=='dpop+jwt'||header.alg!=='ES256'||
        keyId(header.jwk)!==s.publicKey)reject('SENDER_KEY_MISMATCH');
     publicKey=createPublicKey({key:header.jwk,format:'jwk'});
     if(!verify('sha256',Buffer.from(parts[0]+'.'+parts[1]),
        {key:publicKey,dsaEncoding:'ieee-p1363'},signature))reject('BAD_SIGNATURE');
   }catch(error){
     reject(['INVALID_JWK','SENDER_KEY_MISMATCH','BAD_SIGNATURE'].includes(error.message)
       ?error.message:'INVALID_PROOF');
   }
   if(payload.htu!==this.origin+path||payload.htm!==method||
      payload.ath!==sha(accessToken))reject('PROOF_SCOPE_MISMATCH');
   if(!Number.isSafeInteger(payload.iat)||
      Math.abs(this.time()/1000-payload.iat)>300)reject('PROOF_EXPIRED');
   if(typeof payload.jti!=='string'||payload.jti.length<20||
      payload.jti.length>128)reject('INVALID_JTI');
   const nonce=s.id+':'+payload.jti;
   if(this.replay.has(nonce))reject('PROOF_REPLAY');
   this.replay.add(nonce);return s;
 }
 refresh({sessionId,refreshToken,device}){
   const s=this.sessions.get(sessionId);
   if(!s||s.revoked||s.publicKey!==keyId(device.jwk))reject('SENDER_KEY_MISMATCH');
   if(s.refreshToken!==refreshToken){s.revoked=true;reject('REFRESH_REPLAY_REVOKED');}
   s.accessToken=token();s.refreshToken=token();
   return {sessionId:s.id,userId:s.userId,accessToken:s.accessToken,refreshToken:s.refreshToken};
 }
 revoke(sessionId){const s=this.sessions.get(sessionId);if(s)s.revoked=true;}
 setGrants(userId,grants){this.grants.set(userId,new Set(grants));}
 putMedia(assetId,userId,bytes){this.assets.set(assetId,{userId,bytes:Buffer.from(bytes)});}
 mediaRead(session,assetId){
   const grants=this.grants.get(session.userId)??new Set();
   if(!grants.has('media.access')||!grants.has('media.read'))reject('MEDIA_FORBIDDEN');
   const asset=this.assets.get(assetId);
   if(!asset||asset.userId!==session.userId)reject('MEDIA_NOT_FOUND');
   return Buffer.from(asset.bytes);
 }
}
export class SimulatedFlutterClient {
 constructor(server,device=syntheticDevice()){
   this.server=server;this.device=device;this.identityRevision=0;
   this.session=null;this.refreshFlight=null;
 }
 login(userId){
   this.identityRevision++;
   this.session=this.server.issue({userId,device:this.device});return this.session;
 }
 logout(){
   if(this.session)this.server.revoke(this.session.sessionId);
   this.identityRevision++;this.session=null;
 }
 request(method,path){
   if(!this.session)reject('NO_SESSION');
   const proof=signSimulatedDpop({device:this.device,method,
     htu:this.server.origin+path,accessToken:this.session.accessToken,
     iat:Math.floor(this.server.time()/1000)});
   return this.server.verifyRequest({sessionId:this.session.sessionId,
     method,path,accessToken:this.session.accessToken,proof});
 }
 async refresh(){
   if(this.refreshFlight)return this.refreshFlight;
   const before=this.identityRevision,prior=this.session;
   if(!prior)reject('NO_SESSION');
   const work=Promise.resolve().then(()=>{
     if(this.identityRevision!==before)reject('STALE_IDENTITY');
     const next=this.server.refresh({sessionId:prior.sessionId,
       refreshToken:prior.refreshToken,device:this.device});
     if(this.identityRevision!==before||this.session!==prior)reject('STALE_IDENTITY');
     this.session=next;return next;
   });
   this.refreshFlight=work;
   try{return await work;}finally{if(this.refreshFlight===work)this.refreshFlight=null;}
 }
 async readMedia(assetId,networkPause=Promise.resolve()){
   const epoch=this.identityRevision;
   const s=this.request('GET','/media/'+assetId+'/content');
   const bytes=this.server.mediaRead(s,assetId);
   await networkPause;
   if(epoch!==this.identityRevision||this.session?.sessionId!==s.id){
     bytes.fill(0);reject('STALE_IDENTITY');
   }
   return bytes;
 }
}

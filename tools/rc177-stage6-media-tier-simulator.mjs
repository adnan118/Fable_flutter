/**
 * RC177 — isolated cryptographic DEVELOPMENT SIMULATION ONLY.
 * Not used by Flutter or NestJS. No actual DRM/CDM, native player or S3.
 */
import {createCipheriv,createDecipheriv,createHash,randomBytes,timingSafeEqual} from 'node:crypto';

export const TIERS=Object.freeze(['NONE','LOCAL','DRM']);
export const CHUNK_BYTES=128*1024;
export const MAX_RANGE_BYTES=512*1024;
const hash=b=>createHash('sha256').update(b).digest('hex');
const fail=code=>{throw new Error(code)};
const safe=(n)=>Number.isSafeInteger(n)&&n>=0;
const aad=({id,owner,generation,plainLength,chunkIndex,chunkCount})=>
  Buffer.from(JSON.stringify({version:1,id,owner,generation,plainLength,chunkIndex,chunkCount}));
const copy=b=>Buffer.from(b);

function encryptedChunks({id,owner,generation,bytes,key}){
  const chunkCount=Math.ceil(bytes.length/CHUNK_BYTES),chunks=[];
  for(let index=0;index<chunkCount;index++){
    const part=bytes.subarray(index*CHUNK_BYTES,(index+1)*CHUNK_BYTES);
    const nonce=randomBytes(12),cipher=createCipheriv('aes-256-gcm',key,nonce);
    cipher.setAAD(aad({id,owner,generation,plainLength:bytes.length,
      chunkIndex:index,chunkCount}));
    const ciphertext=Buffer.concat([cipher.update(part),cipher.final()]);
    chunks.push({nonce,ciphertext,tag:cipher.getAuthTag()});
  }
  return chunks;
}
function unseal(asset,key,index){
  const chunk=asset.chunks[index];
  if(!chunk||!Buffer.isBuffer(chunk.nonce)||chunk.nonce.length!==12||
     !Buffer.isBuffer(chunk.tag)||chunk.tag.length!==16)fail('MEDIA_AUTH_FAILED');
  try{
    const cipher=createDecipheriv('aes-256-gcm',key,chunk.nonce);
    cipher.setAAD(aad({id:asset.id,owner:asset.owner,generation:asset.generation,
      plainLength:asset.size,chunkIndex:index,chunkCount:asset.chunks.length}));
    cipher.setAuthTag(chunk.tag);
    return Buffer.concat([cipher.update(chunk.ciphertext),cipher.final()]);
  }catch{fail('MEDIA_AUTH_FAILED')}
}

export class SimulatedMediaTierServer {
  constructor({now=()=>Date.now(),licensedDrmAdapter=null}={}){
    this.now=now;this.licensedDrmAdapter=licensedDrmAdapter;
    this.assets=new Map();this.serverKeys=new Map();this.sessions=new Map();
    this.rights=new Map();
  }
  allow(user,allowed=true){this.rights.set(user,Boolean(allowed));}
  upload({id,owner,bytes,tier,generation=1}){
    if(!TIERS.includes(tier))fail('UNKNOWN_TIER');
    if(typeof id!=='string'||!id||typeof owner!=='string'||!owner||
      !Buffer.isBuffer(bytes)||bytes.length===0||!safe(generation)||generation===0)
      fail('INVALID_ASSET');
    if(tier==='DRM')fail('DRM_LICENSED_PACKAGER_REQUIRED');
    // No automatic fallback from DRM to LOCAL or NONE.
    const key=tier==='LOCAL'?randomBytes(32):null;
    const asset={id,owner,tier,generation,size:bytes.length,digest:hash(bytes),
      chunks:tier==='LOCAL'?encryptedChunks({id,owner,generation,bytes,key}):[],
      raw:tier==='NONE'?copy(bytes):null};
    this.assets.set(id,asset);
    if(key)this.serverKeys.set(id,key);
    else this.serverKeys.delete(id);
    return this.metadata(id,owner);
  }
  metadata(id,viewer){
    const a=this.assets.get(id);
    if(!a||a.owner!==viewer)fail('MEDIA_NOT_FOUND');
    if(this.rights.get(viewer)!==true)fail('MEDIA_FORBIDDEN');
    // Deliberately no keys, storage URLs, presigned links or bearer grants.
    return Object.freeze({id:a.id,tier:a.tier,bytes:a.size,
      access:'PROTECTED',clientReceivesKey:false});
  }
  open({assetId,user,ttlMs=10_000,licensed=false}){
    const asset=this.assets.get(assetId);
    if(!asset||asset.owner!==user)fail('MEDIA_NOT_FOUND');
    if(this.rights.get(user)!==true)fail('MEDIA_FORBIDDEN');
    if(!safe(ttlMs)||ttlMs<1||ttlMs>60_000)fail('INVALID_TTL');
    if(asset.tier==='DRM'&&(!licensed||!this.licensedDrmAdapter))
      fail('DRM_LICENSE_NOT_VERIFIED');
    const id=randomBytes(16).toString('hex'),credential=randomBytes(32).toString('base64url');
    const expiry=this.now()+ttlMs;
    this.sessions.set(id,{id,assetId,user,credential,
      generation:asset.generation,expiry,revoked:false});
    return {id,credential,expiry};
  }
  end(id){const s=this.sessions.get(id);if(s)s.revoked=true;}
  assertCurrent(id,credential){
    const s=this.sessions.get(id);
    if(!s||s.revoked||typeof credential!=='string'||
      !timingSafeEqual(createHash('sha256').update(s.credential).digest(),
        createHash('sha256').update(credential).digest()))fail('SESSION_UNAUTHORIZED');
    if(this.now()>=s.expiry)fail('SESSION_EXPIRED');
    if(this.rights.get(s.user)!==true)fail('MEDIA_FORBIDDEN');
    const asset=this.assets.get(s.assetId);
    if(!asset||asset.owner!==s.user||asset.generation!==s.generation)
      fail('MEDIA_RESOURCE_CHANGED');
    return {s,asset};
  }
  async range({sessionId,credential,start,end,pause=Promise.resolve()}){
    if(!safe(start)||!safe(end)||end<start||end-start+1>MAX_RANGE_BYTES)
      fail('INVALID_RANGE');
    let {asset}=this.assertCurrent(sessionId,credential);
    if(end>=asset.size)fail('RANGE_NOT_SATISFIABLE');
    // A paused mock stream must be reauthorized on resume. Never expose bytes first.
    await pause;
    ({asset}=this.assertCurrent(sessionId,credential));
    if(asset.tier==='DRM')fail('DRM_NATIVE_PLAYER_REQUIRED');
    if(asset.tier==='NONE')return copy(asset.raw.subarray(start,end+1));
    if(asset.tier!=='LOCAL')fail('UNKNOWN_TIER');
    const key=this.serverKeys.get(asset.id);
    if(!key||key.length!==32)fail('MEDIA_KEY_UNAVAILABLE');
    if(asset.chunks.length!==Math.ceil(asset.size/CHUNK_BYTES))fail('MEDIA_AUTH_FAILED');
    // Decrypt and authenticate EVERY required chunk before releasing any bytes.
    const first=Math.floor(start/CHUNK_BYTES),last=Math.floor(end/CHUNK_BYTES),parts=[];
    for(let i=first;i<=last;i++){
      const plain=unseal(asset,key,i);
      const size=Math.min(CHUNK_BYTES,asset.size-i*CHUNK_BYTES);
      if(plain.length!==size)fail('MEDIA_AUTH_FAILED');
      parts.push(plain);
    }
    const whole=Buffer.concat(parts);
    const result=copy(whole.subarray(start-first*CHUNK_BYTES,end-first*CHUNK_BYTES+1));
    whole.fill(0);for(const p of parts)p.fill(0);
    if(result.length!==end-start+1)fail('MEDIA_AUTH_FAILED');
    // Recheck rights and session before exposing authenticated bytes.
    this.assertCurrent(sessionId,credential);
    return result;
  }
  loseKey(id){this.serverKeys.delete(id);}
  restoreTestKey(id,secret){
    if(!Buffer.isBuffer(secret)||secret.length!==32)fail('INVALID_KEY');
    // Only a synthetic fixture key can be restored here, not a production vault.
    this.serverKeys.set(id,copy(secret));
  }
}

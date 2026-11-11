/** RC178 Stage6.5 — isolated in-memory Offline/Sync policy MODEL only.
 * Not Drift/SQLite/WorkManager/BGTaskScheduler or a real Backend executor.
 */
import {randomUUID,createHash} from 'node:crypto';
const fail=c=>{throw new Error(c)};
const unsafeOp=/(payment|purchase|billing|balance|wallet|ledger|financial|price|refund|order|booking|reservation|stock|inventory|transfer|message|admin|auth|permission|password|user|account|security|delete-account)/i;
const unsafeField=/(password|secret|access.?token|refresh.?token|authorization|otp|passkey|credit.?card|iban|cvv|private.?key|health|medical)/i;
const hash=x=>createHash('sha256').update(x).digest('hex');
const clone=o=>JSON.parse(JSON.stringify(o));
const containsSecret=o=>o&&typeof o==='object'&&(Array.isArray(o)?o.some(containsSecret):Object.entries(o).some(([k,v])=>unsafeField.test(k)||containsSecret(v)));
const hex=s=>typeof s==='string'&&/^[0-9a-f]{64}$/.test(s);
const scopeOf=(scope)=>{
 if(!scope||typeof scope.origin!=='string'||!/^https:\/\/[a-z0-9.-]+(?::\d+)?$/i.test(scope.origin)||
  ['projectId','accountId','entityId'].some(k=>typeof scope[k]!=='string'||!scope[k].trim()||scope[k].length>128)||
  !hex(scope.contractHash))fail('UNVERIFIED_SCOPE');
 return hash(JSON.stringify([scope.origin,scope.projectId,scope.accountId,scope.entityId,scope.contractHash]));
};
export class SimulatedOfflineSync {
 constructor({now=()=>Date.now(),scope,grants=[],approvedReads=[],maxPending=100}={}){
  this.now=now;this.scope=scopeOf(scope);this.currentScope=this.scope;
  this.grants=new Map();this.reads=new Set(approvedReads);
  this.rows=new Map();this.cache=new Map();this.online=false;this.pendingFlight=null;
  this.workScheduled=false;this.maxPending=maxPending;
  if(!Number.isInteger(maxPending)||maxPending<1||maxPending>1000)fail('INVALID_QUEUE_CAPACITY');
  for(const g of grants){
   if(!g||typeof g.id!=='string'||!g.id||unsafeOp.test(g.id)||
     !['POST','PUT','PATCH','DELETE'].includes(g.method)||
     !g.idempotencyVerified||!g.conflictProtocolVerified||
     g.contractHash!==scope.contractHash||this.grants.has(g.id))fail('UNVERIFIED_WRITE_GRANT');
   this.grants.set(g.id,g);
  }
  for(const id of this.reads)if(unsafeOp.test(id)||typeof id!=='string')fail('UNSAFE_CACHE_GRANT');
 }
 scopeChanged(scope){this.currentScope=scopeOf(scope);}
 setOnline(value){this.online=value===true;}
 checkScope(){if(this.currentScope!==this.scope)fail('STALE_IDENTITY');}
 putCache({operationId,key,data,ttlMs,version='v1'}){
  this.checkScope();if(!this.reads.has(operationId)||containsSecret(data)||
    !Number.isSafeInteger(ttlMs)||ttlMs<=0||ttlMs>30*86400000||
    typeof key!=='string'||!key)fail('UNAPPROVED_CACHE');
  this.cache.set(this.scope+':'+operationId+':'+key,{data:clone(data),expiresAt:this.now()+ttlMs,version});
 }
 readCache({operationId,key,allowStale=false}){
  this.checkScope();if(!this.reads.has(operationId))fail('UNAPPROVED_CACHE');
  const value=this.cache.get(this.scope+':'+operationId+':'+key);
  if(!value)return null;
  if(value.expiresAt<=this.now()&&!allowStale)return null;
  return {data:clone(value.data),stale:value.expiresAt<=this.now(),confirmed:false,version:value.version};
 }
 enqueue({operationId,resourceId,body,baseVersion}){
  this.checkScope();if(!this.grants.has(operationId)||containsSecret(body)||
   typeof resourceId!=='string'||!resourceId||typeof baseVersion!=='string'||!baseVersion||
   !body||typeof body!=='object'||Array.isArray(body))fail('UNAPPROVED_WRITE');
  if([...this.rows.values()].filter(r=>r.scope===this.scope).length>=this.maxPending)
   fail('QUEUE_LIMIT');
  const id=randomUUID();this.rows.set(id,{id,scope:this.scope,operationId,resourceId,
    body:clone(body),baseVersion,attempts:0,nextAt:this.now(),status:'pending',reason:null});
  return id;
 }
 pending(){return [...this.rows.values()].filter(r=>r.scope===this.scope&&r.status==='pending').map(clone);}
 reviews(){return [...this.rows.values()].filter(r=>r.scope===this.scope&&r.status==='review').map(clone);}
 scheduleBackground(){this.workScheduled=true;return {guaranteed:false,scheduledOnly:true};}
 async runScheduled(executor,{systemGranted=false}={}){
  if(!this.workScheduled||!systemGranted)return 0;
  this.workScheduled=false;return this.flush(executor);
 }
 async flush(executor){
  if(this.pendingFlight)return this.pendingFlight;
  const run=this._flush(executor);
  this.pendingFlight=run;
  try{return await run;}finally{if(this.pendingFlight===run)this.pendingFlight=null;}
 }
 async _flush(executor){
  if(!this.online)return 0;
  this.checkScope();let count=0;
  const jobs=[...this.rows.values()].filter(r=>r.scope===this.scope&&r.status==='pending'&&r.nextAt<=this.now());
  for(const row of jobs){
   if(!this.online||this.currentScope!==this.scope)return count;
   if(!this.grants.has(row.operationId)){
    row.status='review';row.reason='GRANT_REVOKED';return count;
   }
   let outcome;
   try{outcome=await executor(clone(row),{idempotencyKey:row.id});}
   catch{outcome={status:'timeout'};}
   if(this.currentScope!==this.scope)return count;
   if(!this.online)return count;
   if(!this.grants.has(row.operationId)){
    row.status='review';row.reason='GRANT_REVOKED';return count;
   }
   if(outcome?.status==='ack'&&typeof outcome.serverVersion==='string'&&outcome.serverVersion.trim()){
    this.rows.delete(row.id);count++;continue;
   }
   if(outcome?.status==='conflict'||outcome?.status==='refused'||outcome?.status==='ack'){
    row.status='review';row.reason=outcome.status==='ack'?'ACK_NO_VERSION':outcome.status.toUpperCase();
    return count;
   }
   if(outcome?.status==='unauthorized')return count;
   // Timeout, 5xx, 429 and unknown outcome all retain the same key.
   row.attempts++;
   if(row.attempts>6){row.status='review';row.reason='RETRY_EXHAUSTED';}
   else row.nextAt=this.now()+Math.min(3600000,15000*(2**row.attempts));
   return count;
  }
  return count;
 }
 revokeGrant(id){this.grants.delete(id);}
 clearOnLogout(){this.checkScope();for(const [key,row] of this.rows)if(row.scope===this.scope)this.rows.delete(key);
  for(const k of this.cache.keys())if(k.startsWith(this.scope+':'))this.cache.delete(k);
  this.currentScope=null;
 }
}

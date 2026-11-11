/** Stage6 gate 6.6: synthetic provider protocol model, never a live SDK or Backend. */
import {randomBytes, createHash} from 'node:crypto';
const deny=(code)=>{throw new Error(code)};
const secret=()=>randomBytes(24).toString('base64url');
const digest=(value)=>createHash('sha256').update(value).digest('hex');
const freeze=(data)=>Object.freeze({...data});
export class SimulatedProviderGateway {
  constructor({now=()=>Date.now(), backendKind='fable', verifiedContract=false}={}) {
    this.now=now;this.backendKind=backendKind;this.verifiedContract=verifiedContract;
    this.identity=null;this.epoch=0;this.consentEpoch=null;this.apnsReady=false;
    this.push=new Map();this.challenges=new Map();this.tickets=new Map();this.payments=new Map();
    this.pending=new Set();this.notifications=new Map();
  }
  bind({userId,sessionId,backendKind=this.backendKind,contractVerified=this.verifiedContract}={}) {
    if(!userId||!sessionId||!['fable','other'].includes(backendKind)||!contractVerified)deny('CONTRACT_NOT_VERIFIED');
    this.epoch++;this.identity={userId,sessionId,backendKind};this.backendKind=backendKind;
    this.verifiedContract=contractVerified;this.consentEpoch=null;return this.epoch;
  }
  logout(){const old=this.identity;this.epoch++;this.identity=null;this.consentEpoch=null;
    if(old)for(const [key,value] of this.push)if(value.sessionId===old.sessionId)this.push.delete(key);
  }
  requireSession(epoch=this.epoch){if(!this.identity||epoch!==this.epoch||!this.verifiedContract)deny('STALE_IDENTITY');return this.identity;}
  pushConsent(granted){this.requireSession();this.consentEpoch=granted===true?this.epoch:null;}
  registerPush({token,platform,operationVerified=true,apnsReady=this.apnsReady,epoch=this.epoch}={}){
    const s=this.requireSession(epoch);
    if(this.consentEpoch!==epoch||!operationVerified||typeof token!=='string'||token.length<20||
      !['android','ios'].includes(platform)||(platform==='ios'&&!apnsReady))deny('PUSH_NOT_AUTHORIZED');
    const key=digest(token);this.push.set(key,{...s,tokenHash:key,epoch});return key;
  }
  revokePush(token){const s=this.requireSession();const key=digest(token),row=this.push.get(key);
    if(row&&row.sessionId===s.sessionId)this.push.delete(key);
  }
  notify({userId,notificationId,content}){this.notifications.set(notificationId,{userId,content});}
  openNotification(notificationId){const s=this.requireSession();const n=this.notifications.get(notificationId);
    if(!n||n.userId!==s.userId)deny('NOTIFICATION_FORBIDDEN');return n.content;
  }
  beginPasskey({rpId,origin,operationVerified=true,ttlMs=60000}={}){
    if(!operationVerified||!this.verifiedContract||!this.identity||!rpId||origin!==`https://${rpId}`||
      !Number.isSafeInteger(ttlMs)||ttlMs<1000||ttlMs>300000)deny('PASSKEY_UNVERIFIED');
    const state=secret(),challenge=secret();this.challenges.set(state,{kind:'passkey',challenge,origin,rpId,
      epoch:this.epoch,expiry:this.now()+ttlMs,used:false});return freeze({state,challenge,rpId,origin});
  }
  finishPasskey({state,challenge,rpId,origin,assertionVerified=false}={}){
    const c=this.challenges.get(state);this.requireSession(c?.epoch);
    if(!c||c.kind!=='passkey'||c.used||this.now()>=c.expiry||c.challenge!==challenge||
      c.rpId!==rpId||c.origin!==origin||!assertionVerified)deny('PASSKEY_ASSERTION_REJECTED');
    c.used=true;return freeze({accepted:true,serverVerified:true});
  }
  beginSocial({provider,ttlMs=60000}={}){
    this.requireSession();if(!['google','apple'].includes(provider))deny('SOCIAL_PROVIDER_UNSUPPORTED');
    const state=secret(),nonce=secret();this.challenges.set(state,{kind:'social',nonce,provider,
      epoch:this.epoch,expiry:this.now()+ttlMs,used:false});return freeze({state,nonce,provider});
  }
  finishSocial({state,nonce,provider,credentialVerified=false,linkExisting=false,existingAccountProof=false}={}){
    const c=this.challenges.get(state);this.requireSession(c?.epoch);
    if(!c||c.kind!=='social'||c.used||this.now()>=c.expiry||c.provider!==provider||
      c.nonce!==nonce||!credentialVerified)deny('SOCIAL_CREDENTIAL_REJECTED');
    if(linkExisting&&!existingAccountProof)deny('ACCOUNT_LINK_PROOF_REQUIRED');
    c.used=true;return freeze({authenticated:true,linked:linkExisting});
  }
  recordPayment({id,owner,serverVerified=false,status='PENDING'}={}){
    if(!id||!owner||!['PENDING','SETTLED','FAILED'].includes(status))deny('PAYMENT_INVALID');
    this.payments.set(id,{owner,serverVerified,status});
  }
  readPayment({id,uiSuccess=false}={}){
    const s=this.requireSession(),p=this.payments.get(id);
    if(!p||p.owner!==s.userId)deny('PAYMENT_FORBIDDEN');
    return freeze({id,status:p.serverVerified?p.status:'UNVERIFIED',valueGranted:p.serverVerified&&p.status==='SETTLED'});
  }
  async createSupport({subject,description,send,requestId=secret()}={}){
    const s=this.requireSession(),epoch=this.epoch;
    if(typeof subject!=='string'||subject.trim().length<2||subject.length>200||
      typeof description!=='string'||description.trim().length<2||description.length>5000||
      typeof send!=='function')deny('SUPPORT_INVALID');
    const key=`${s.sessionId}:${requestId}`;
    if(this.pending.has(key))deny('SUPPORT_ALREADY_SENT_OR_UNCERTAIN');
    this.pending.add(key); // never replay automatically on timeout
    let outcome;
    try{outcome=await send({subject,description,requestId});}
    catch{return freeze({state:'UNKNOWN_CHECK_SERVER',retryAutomatically:false});}
    if(this.epoch!==epoch||this.identity?.sessionId!==s.sessionId)deny('STALE_IDENTITY');
    if(outcome?.serverAcknowledged!==true)return freeze({state:'UNKNOWN_CHECK_SERVER',retryAutomatically:false});
    this.tickets.set(key,{userId:s.userId,id:outcome.ticketId});
    return freeze({state:'SERVER_ACK',ticketId:outcome.ticketId});
  }
  verifyProviderOperation({operation,method,authenticated,verified=false,backend=this.backendKind}={}){
    const policy={pushRegister:['POST',true],pushUnregister:['DELETE',true],
      paymentRead:['GET',true],supportList:['GET',true],supportCreate:['POST',true],
      passkeyOptions:['POST',false],passkeyVerify:['POST',false]};
    const expect=policy[operation];if(!expect||!verified||!this.verifiedContract||
      !['fable','other'].includes(backend)||backend!==this.backendKind||
      expect[0]!==method||expect[1]!==authenticated)deny('PROVIDER_OPERATION_UNVERIFIED');
    return true;
  }
}

import test from 'node:test';
import assert from 'node:assert/strict';
/** RC180: fake MethodChannel/OS scheduler only, never Flutter/Android/iOS runtime. */
class SimulatedNativeBoundary {
  constructor({platform='android',hasHardware=true,projectPinned=true,origin='https://fable.sim.invalid'}={}) {
    this.platform=platform;this.hasHardware=hasHardware;this.projectPinned=projectPinned;
    this.origin=origin;this.epoch=0;this.session=null;this.workerRegistered=false;
  }
  login(user){this.epoch++;this.session=user;}
  logout(){this.epoch++;this.session=null;}
  async dpop({operation='GET',url=this.origin+'/auth/me',channel,accessToken='a'.repeat(40)}={}){
    const revision=this.epoch,account=this.session;
    if(!account)throw Error('NO_SESSION');
    if(!this.projectPinned||!['android','ios'].includes(this.platform)||!this.hasHardware)
      throw Error('NATIVE_HARDWARE_REQUIRED');
    if(typeof url!=='string'||!url.startsWith(this.origin+'/')||url.includes('?')||url.includes('#')||
      !['GET','POST','PATCH','DELETE','HEAD','PUT'].includes(operation)||accessToken.length<32)
      throw Error('DPoP_SCOPE_REJECTED');
    if(typeof channel!=='function')throw Error('NATIVE_CHANNEL_MISSING');
    let proof;
    try{proof=await channel({operation,url,accessToken});}catch{throw Error('NATIVE_CHANNEL_FAILED');}
    if(this.epoch!==revision||this.session!==account)throw Error('STALE_NATIVE_RESULT');
    if(typeof proof!=='string'||proof.split('.').length!==3||
      proof.length<100||proof.length>4096)throw Error('INVALID_NATIVE_PROOF');
    return proof;
  }
  registerBackground({verifiedDispatcher=false,taskId='com.example.fable.sync'}={}) {
    if(!verifiedDispatcher||!this.projectPinned||!['android','ios'].includes(this.platform)||
      !/^[A-Za-z0-9_-]+(\.[A-Za-z0-9_-]+)+$/.test(taskId))throw Error('WORKER_UNVERIFIED');
    this.workerRegistered=true;return {bestEffort:true,guaranteed:false};
  }
  async runBackground({systemOpportunity=false,verifiedSession=false,execute}={}){
    if(!this.workerRegistered||!systemOpportunity||!verifiedSession||!this.session)return false;
    if(typeof execute!=='function')return false;
    await execute();return true;
  }
}
const validProof=['e'.repeat(60),'p'.repeat(80),'s'.repeat(80)].join('.');
const create=(opts={})=>{const b=new SimulatedNativeBoundary(opts);b.login('A');return b;};
test('01 verified Android hardware bridge can return synthetic shaped proof',async()=>{const b=create();assert.equal(await b.dpop({channel:async()=>validProof}),validProof)});
test('02 no hardware or platform unsupported fails closed without fallback',async()=>{for(const opt of [{hasHardware:false},{platform:'web'},{platform:'desktop'}])await assert.rejects(create(opt).dpop({channel:async()=>validProof}),/NATIVE_HARDWARE_REQUIRED/)});
test('03 missing project pin rejects signing',async()=>{await assert.rejects(create({projectPinned:false}).dpop({channel:async()=>validProof}),/NATIVE_HARDWARE_REQUIRED/)});
test('04 missing MethodChannel blocks signing',async()=>{await assert.rejects(create().dpop(),/NATIVE_CHANNEL_MISSING/)});
test('05 native channel exceptions do not trigger software signing fallback',async()=>{await assert.rejects(create().dpop({channel:async()=>{throw Error('not installed')}}),/NATIVE_CHANNEL_FAILED/)});
test('06 native proof missing, malformed or oversize rejects',async()=>{for(const x of [null,'a.b.c','x'.repeat(5000)])await assert.rejects(create().dpop({channel:async()=>x}),/INVALID_NATIVE_PROOF/)});
test('07 signing request refuses non-origin or query parameter',async()=>{const b=create();for(const url of ['https://other.invalid/auth/me','http://fable.sim.invalid/auth/me','https://fable.sim.invalid/auth/me?q=1'])await assert.rejects(b.dpop({url,channel:async()=>validProof}),/DPoP_SCOPE_REJECTED/)});
test('08 access token must be valid-shaped before native handoff',async()=>{await assert.rejects(create().dpop({accessToken:'short',channel:async()=>validProof}),/DPoP_SCOPE_REJECTED/)});
test('09 only verified HTTP verbs can enter simulated bridge',async()=>{await assert.rejects(create().dpop({operation:'TRACE',channel:async()=>validProof}),/DPoP_SCOPE_REJECTED/)});
test('10 account switch while native signer awaits rejects old proof',async()=>{const b=create();let resume;const hold=new Promise(r=>resume=r);const p=b.dpop({channel:async()=>{await hold;return validProof}});b.login('B');resume();await assert.rejects(p,/STALE_NATIVE_RESULT/)});
test('11 logout while signer awaits rejects pending proof',async()=>{const b=create();let resume;const hold=new Promise(r=>resume=r);const p=b.dpop({channel:async()=>{await hold;return validProof}});b.logout();resume();await assert.rejects(p,/STALE_NATIVE_RESULT/)});
test('12 background scheduler is an opportunity, never a timer SLA',async()=>{const b=create();assert.deepEqual(b.registerBackground({verifiedDispatcher:true}),{bestEffort:true,guaranteed:false});let calls=0;assert.equal(await b.runBackground({systemOpportunity:false,verifiedSession:true,execute:async()=>calls++}),false);assert.equal(calls,0)});
test('13 worker without verified session or dispatcher does not submit',async()=>{const b=create();assert.throws(()=>b.registerBackground({verifiedDispatcher:false}),/WORKER_UNVERIFIED/);b.registerBackground({verifiedDispatcher:true});assert.equal(await b.runBackground({systemOpportunity:true,verifiedSession:false,execute:async()=>{throw Error('must not run')}}),false)});
test('14 only OS opportunity with verified session executes the synthetic worker',async()=>{const b=create();b.registerBackground({verifiedDispatcher:true});let called=0;assert.equal(await b.runBackground({systemOpportunity:true,verifiedSession:true,execute:async()=>called++}),true);assert.equal(called,1)});
test('15 iOS native failure is not treated as successful signing',async()=>{const b=create({platform:'ios'});await assert.rejects(b.dpop({channel:async()=>{throw Error('Secure Enclave missing')}}),/NATIVE_CHANNEL_FAILED/)});
test('16 expired identity prevents background processing after logout',async()=>{const b=create();b.registerBackground({verifiedDispatcher:true});b.logout();assert.equal(await b.runBackground({systemOpportunity:true,verifiedSession:true,execute:async()=>{throw Error('must not run')}}),false)});

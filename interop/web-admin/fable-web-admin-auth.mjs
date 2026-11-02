/**
 * Fable RC67: browser-only, same-origin Web cookie Auth and Admin policy clients.
 * The Backend owns HttpOnly access/refresh cookies, CSRF enforcement and AAL2.
 * Never persist bearer tokens, OTPs, social tokens or challenge state.
 */
const PROVIDERS = new Set(['google', 'apple']);
const CHANNELS = new Set(['EMAIL', 'PHONE']);
const UUID4 = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function assertString(value, name, min=1, max=191) {
  if (typeof value !== 'string' || value.length < min || value.length > max ||
    /[\x00-\x1f\x7f]/.test(value)) throw new TypeError('Invalid '+name);
  return value;
}
function csrfFromCookie(name) {
  if (typeof document === 'undefined') return null;
  const cookie = document.cookie.split('; ').find(x=>x.startsWith(encodeURIComponent(name)+'='));
  if (!cookie) return null;
  try { return decodeURIComponent(cookie.slice(cookie.indexOf('=')+1)); } catch { return null; }
}
function unbox(body) {
  if (!body || typeof body !== 'object' || body.success !== true || !('data' in body))
    throw new Error('Unconfirmed Fable server response');
  return body.data;
}
function validFutureInstant(value) {
  return typeof value === 'string' && /^\d{4}-\d{2}-\d{2}T.*(?:Z|[+-]\d{2}:\d{2})$/.test(value) && Date.parse(value)>Date.now();
}
function validateSecondFactor(data) {
  if (!data || data.requiresTwoFactor !== true) return false;
  assertString(data.twoFactorToken,'2FA first-factor token',32,512);
  if (!Array.isArray(data.methods) || !data.methods.length ||
      data.methods.some(m=>!['EMAIL_OTP','PHONE_OTP'].includes(m)))
    throw new Error('Unsupported Fable 2FA methods');
  if (!validFutureInstant(data.expiresAt))
    throw new Error('Expired Fable 2FA challenge');
  return true;
}
function validateSession(data) {
  if (!data || data.transport !== 'cookie' ||
      !validFutureInstant(data.expiresAt) ||
      typeof data.mustChangePassword !== 'boolean' ||
      typeof data.csrfToken !== 'string' || data.csrfToken.length < 24 ||
      'accessToken' in data || 'refreshToken' in data)
    throw new Error('Fable did not confirm a cookie session');
  return data;
}

export class FableWebAuth {
  #fetch;
  #origin;
  #csrfName;
  #csrf;
  #generation = 0;
  #pendingFactors = new WeakSet();
  #issuedFactors = new WeakSet();
  #pendingSocial = new WeakSet();
  #pendingOtp = new WeakSet();
  #verifiedOtp = new WeakSet();
  constructor({baseUrl, fetchImpl=globalThis.fetch, csrfCookieName='fable_csrf',
    csrfToken=null, browserOrigin=typeof location === 'undefined' ? null : location.origin}={}) {
    if (typeof fetchImpl !== 'function') throw new TypeError('fetch is required');
    const u = new URL(baseUrl || browserOrigin || 'https://invalid.test');
    if (u.username || u.password || u.search || u.hash || u.pathname !== '/')
      throw new Error('Fable Web Auth requires an origin-only base URL');
    if (browserOrigin && u.origin !== browserOrigin)
      throw new Error('Cross-origin Web cookie Auth is forbidden');
    this.#origin=u.origin;this.#fetch=fetchImpl;this.#csrfName=csrfCookieName;
    this.#csrf=csrfToken;
  }
  csrfToken() { return this.#csrf || csrfFromCookie(this.#csrfName); }

  async #request(path, body, {method='POST', needsCsrf=false, headers={}}={}) {
    const csrf=needsCsrf?this.csrfToken():null;
    if (needsCsrf && (!csrf || !/^[A-Za-z0-9_-]{24,128}$/.test(csrf)))
      throw new Error('Web CSRF proof is unavailable; cannot send mutation');
    const response=await this.#fetch(this.#origin+path,{
      method,credentials:'include',mode:'same-origin',redirect:'error',
      cache:'no-store',headers:{
        'Accept':'application/json',
        ...(body === undefined ? {} : {'Content-Type':'application/json'}),
        ...(needsCsrf ? {'X-CSRF-Token':csrf} : {}),
        ...headers,
      },
      ...(body === undefined ? {} : {body:JSON.stringify(body)}),
    });
    if (!response || typeof response.json !== 'function') throw new Error('Invalid HTTP response');
    const payload=await response.json();
    if (!response.ok || payload?.success !== true) {
      const e=new Error('Fable request rejected');
      e.status=response.status;
      e.code=payload?.code || payload?.error?.code || payload?.messageCode || 'HTTP_REJECTED';
      throw e;
    }
    return unbox(payload);
  }

  #newFactor(data) {
    validateSecondFactor(data);
    const challenge=Object.freeze({token:data.twoFactorToken,methods:Object.freeze([...data.methods]),
      expiresAt:data.expiresAt,generation:++this.#generation});
    this.#pendingFactors.add(challenge);
    return Object.freeze({requiresTwoFactor:true,challenge});
  }
  #newSession(data) {
    const validated=validateSession(data);
    this.#csrf=validated.csrfToken;
    ++this.#generation;
    return Object.freeze({authenticated:true,transport:'cookie',
      mustChangePassword:validated.mustChangePassword === true,
      expiresAt:validated.expiresAt});
  }
  #identityResponse(data) {
    if (data?.requiresTwoFactor === true) return this.#newFactor(data);
    return this.#newSession(data);
  }

  async login({identifier,password,deviceName,appVersion}) {
    const body={identifier:assertString(identifier,'identifier'),
      password:assertString(password,'password',1,128)};
    if(deviceName != null) body.deviceName=assertString(deviceName,'deviceName');
    if(appVersion != null) body.appVersion=assertString(appVersion,'appVersion',1,64);
    const data=await this.#request('/auth/web/login',body);
    return this.#identityResponse(data);
  }
  async refresh() {
    const data=await this.#request('/auth/web/refresh',undefined,{needsCsrf:true});
    return this.#newSession(data);
  }

  async startSocial(provider) {
    if(!PROVIDERS.has(provider)) throw new TypeError('Invalid social provider');
    const data=await this.#request('/auth/social/challenge',{provider});
    if(data?.provider!==provider) throw new Error('Challenge provider mismatch');
    assertString(data.state,'social state',20,512);
    assertString(data.nonce,'social nonce',20,512);
    if(!Number.isInteger(data.expiresInMs) || data.expiresInMs < 1000 || data.expiresInMs > 3600000)
      throw new Error('Invalid social challenge lifetime');
    const challenge=Object.freeze({provider,state:data.state,nonce:data.nonce,
      expiresAt:Date.now()+data.expiresInMs,generation:this.#generation});
    this.#pendingSocial.add(challenge);
    return challenge;
  }
  async completeSocial(challenge, credential) {
    if(!this.#pendingSocial.delete(challenge) || challenge.generation!==this.#generation ||
      Date.now()>=challenge.expiresAt) throw new Error('Stale or foreign social challenge');
    if(!credential || credential.nonce!==challenge.nonce)
      throw new Error('Provider nonce does not match server challenge');
    const body={state:challenge.state,nonce:challenge.nonce};
    if(challenge.provider==='google') {
      body.idToken=assertString(credential.idToken,'Google ID token',20,12000);
    } else {
      body.identityToken=assertString(credential.identityToken,'Apple identity token',20,12000);
      body.authorizationCode=assertString(credential.authorizationCode,'Apple authorization code',6,12000);
      if(credential.givenName)body.givenName=assertString(credential.givenName,'givenName',1,100);
      if(credential.familyName)body.familyName=assertString(credential.familyName,'familyName',1,100);
    }
    const data=await this.#request('/auth/web/social/'+challenge.provider,body);
    return this.#identityResponse(data);
  }

  #requireFactor(challenge) {
    if(!this.#pendingFactors.has(challenge) || challenge.generation!==this.#generation ||
      Date.now()>=Date.parse(challenge.expiresAt))
      throw new Error('Stale, expired or foreign first-factor challenge');
  }
  async requestSecondFactor(challenge,{preferredChannel}={}) {
    this.#requireFactor(challenge);
    if(preferredChannel!==undefined && (!CHANNELS.has(preferredChannel) ||
      !challenge.methods.includes(preferredChannel+'_OTP')))
      throw new TypeError('Unadvertised 2FA channel');
    const data=await this.#request('/auth/web/2fa/login/request',{
      twoFactorToken:challenge.token,...(preferredChannel?{preferredChannel}:{})});
    if(!UUID4.test(data?.challengeId)) throw new Error('Backend failed to confirm 2FA request');
    const issued=Object.freeze({challengeId:data.challengeId,firstFactor:challenge});
    this.#issuedFactors.add(issued);
    return issued;
  }
  async completeSecondFactor(issued,code) {
    if(!issued || !this.#issuedFactors.delete(issued) || !UUID4.test(issued.challengeId))
      throw new Error('Unknown or replayed 2FA request');
    this.#requireFactor(issued.firstFactor);
    if (!/^\d{4,10}$/.test(code)) throw new TypeError('2FA OTP must contain digits');
    this.#pendingFactors.delete(issued.firstFactor); // one-shot even after network failures
    const data=await this.#request('/auth/web/2fa/login/complete',{
      twoFactorToken:issued.firstFactor.token,challengeId:issued.challengeId,
      code:assertString(code,'2FA OTP',4,10)});
    return this.#newSession(data);
  }
  async requestLoginOtp({identifier,preferredChannel}={}) {
    if(preferredChannel!==undefined&&!CHANNELS.has(preferredChannel))
      throw new TypeError('Invalid OTP channel');
    const data=await this.#request('/auth/otp/public/request',{
      purpose:'LOGIN',identifier:assertString(identifier,'identifier'),
      ...(preferredChannel?{preferredChannel}:{})});
    if(data?.accepted!==true || data?.deliveryStatus!=='QUEUED' ||
       !UUID4.test(data.challengeId) || !validFutureInstant(data.expiresAt))
      throw new Error('Backend did not accept LOGIN OTP request');
    const item=Object.freeze({challengeId:data.challengeId,expiresAt:data.expiresAt,
      generation:this.#generation});
    this.#pendingOtp.add(item);
    return item;
  }
  async verifyLoginOtp(challenge,code) {
    if(!this.#pendingOtp.delete(challenge) || challenge.generation!==this.#generation ||
       Date.now()>=Date.parse(challenge.expiresAt))
      throw new Error('Expired or foreign LOGIN OTP');
    if (!/^\d{6,10}$/.test(code)) throw new TypeError('LOGIN OTP must contain digits');
    const data=await this.#request('/auth/otp/public/verify',{
      challengeId:challenge.challengeId,code:assertString(code,'LOGIN OTP',6,10)});
    if(data?.verified!==true || data?.purpose!=='LOGIN' ||
       data?.challengeId!==challenge.challengeId)
      throw new Error('OTP proof has the wrong purpose');
    const proof=Object.freeze({challengeId:challenge.challengeId,generation:this.#generation});
    this.#verifiedOtp.add(proof);
    return proof;
  }
  async completeLoginOtp(proof) {
    if(!this.#verifiedOtp.delete(proof) || proof.generation!==this.#generation)
      throw new Error('Foreign, replayed or stale LOGIN OTP proof');
    const data=await this.#request('/auth/web/otp/login/complete',{challengeId:proof.challengeId});
    return this.#newSession(data);
  }

  /** Web-only admin dashboard: Backend requires explicit permission and recent AAL2. */
  async readAdminPasswordPolicy(){
    const data=await this.#request('/admin/auth/password-policy',undefined,{method:'GET'});
    if(data?.schemaVersion!==1 || data?.sourceOfTruth!=='database' ||
      !Number.isSafeInteger(data?.policy?.version) || data.policy.version<0 ||
      !data?.constraints || !Array.isArray(data.fields))
      throw new Error('Invalid server-side password policy contract');
    return data;
  }
  async updateAdminPasswordPolicy({version,changes}) {
    if(!Number.isSafeInteger(version)||version<0)throw new TypeError('Invalid policy version');
    if(!changes||typeof changes!=='object'||Array.isArray(changes) ||
      !Object.keys(changes).length) throw new TypeError('Missing policy changes');
    const ints={minLength:[15,128],maxLength:[64,1024],historyLimit:[0,24],
      minUniqueChars:[1,16],maxRepeatedChars:[2,20],maxSequentialChars:[2,20],
      contextTokenMinLength:[4,32],phoneSuffixLength:[4,15]};
    const bools=new Set(['requireUppercase','requireLowercase','requireNumber',
      'requireSymbol','forbidCommonPasswords','forbidRepetitivePatterns',
      'forbidSequentialPatterns','forbidContextSpecific','checkEmail','checkPhone',
      'checkUsername','checkDisplayName','emailLocalPartCheck']);
    for(const [key,val] of Object.entries(changes)){
      if(key in ints){const [lo,hi]=ints[key];if(!Number.isInteger(val)||val<lo||val>hi)
        throw new TypeError('Invalid password policy number: '+key);
      } else if(bools.has(key)){if(typeof val!=='boolean')throw new TypeError('Invalid policy flag: '+key);
      }else throw new TypeError('Unsupported password policy field: '+key);
    }
    // Server enforces AAL2, permission and concurrency. No client privilege shortcut.
    if(changes.forbidCommonPasswords===false)throw new TypeError('Cannot disable baseline common-password check');
    const data=await this.#request('/admin/auth/password-policy',changes,{
      method:'PUT',needsCsrf:true,headers:{'If-Match':String(version)}});
    if(!data || typeof data !== 'object' ||
      !Number.isSafeInteger(data.version) || data.version !== version+1)
      throw new Error('Admin policy update version not confirmed by Backend');
    return data;
  }
}

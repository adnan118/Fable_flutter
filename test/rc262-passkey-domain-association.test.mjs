import test from 'node:test';
import assert from 'node:assert/strict';

import {createPasskeyAssociationBundle} from '../tools/generate-passkey-associations.mjs';

const fingerprint=Array(32).fill('AB').join(':');
const sample=()=>({
  kind:'fable.passkey-domain-association',schemaVersion:1,
  projectId:'independently-pinned-project',
  backendContractHash:'a'.repeat(64),
  rpId:'login.project-account.com',
  android:{packageName:'com.projectaccount.mobile',
    sha256CertFingerprints:[fingerprint]},
  ios:{teamId:'A1B2C3D4E5',bundleId:'com.projectaccount.mobile'},
});

test('RC262 export contains only Android credential relationship and iOS webcredentials',()=>{
  const out=createPasskeyAssociationBundle(sample());
  const paths=Object.keys(out);
  assert.deepEqual(paths.sort(),[
    'README.md','ios/FablePasskeys.entitlements',
    'backend/Passkeys-origin-review.env',
    'site/.well-known/apple-app-site-association',
    'site/.well-known/assetlinks.json',
  ].sort());
  const android=JSON.parse(out['site/.well-known/assetlinks.json']);
  assert.deepEqual(android[0].relation,['delegate_permission/common.get_login_creds']);
  assert.equal(android[0].target.package_name,'com.projectaccount.mobile');
  assert.deepEqual(android[0].target.sha256_cert_fingerprints,[fingerprint]);
  const ios=JSON.parse(out['site/.well-known/apple-app-site-association']);
  assert.deepEqual(ios.webcredentials.apps,['A1B2C3D4E5.com.projectaccount.mobile']);
  assert.match(out['ios/FablePasskeys.entitlements'],
    /webcredentials:login\.project-account\.com/);
  const origin='android:apk-key-hash:'+
    Buffer.from('AB'.repeat(32),'hex').toString('base64url');
  const env=out['backend/Passkeys-origin-review.env'];
  assert.ok(env.includes('AUTH_PASSKEY_RP_ID=login.project-account.com'));
  assert.ok(env.includes('AUTH_PASSKEY_ORIGINS=https://login.project-account.com,'+origin));
  assert.ok(!env.includes('AUTH_PASSKEY_ENABLED=true'));
});

test('RC262 refuses placeholder, web URL, local, empty or wildcard RP hosts',()=>{
  for(const rpId of ['','localhost','example.com','testing.invalid',
     'foo.test','*.project-account.com','https://login.project-account.com',
     'login.project-account.com/path','login..project-account.com',
     'login.project-account.com:443','192.168.0.1']){
    assert.throws(()=>createPasskeyAssociationBundle({...sample(),rpId}),
      /PASSKEY_ASSOCIATION/);
  }
});

test('RC262 requires a real signing package and nonduplicate SHA-256 certificate',()=>{
  for(const android of [
    {packageName:'com.example.helloWorld',sha256CertFingerprints:[fingerprint]},
    {packageName:'com.projectaccount.mobile',sha256CertFingerprints:['AA:BB']},
    {packageName:'com.projectaccount.mobile',sha256CertFingerprints:[fingerprint,fingerprint]},
    {packageName:'com.projectaccount.mobile',sha256CertFingerprints:[]},
  ]){
    assert.throws(()=>createPasskeyAssociationBundle({...sample(),android}),
      /PASSKEY_ASSOCIATION/);
  }
});

test('RC262 does not accept fake Apple identity or stale contract hash',()=>{
  assert.throws(()=>createPasskeyAssociationBundle({...sample(),
    ios:{teamId:'TEAM',bundleId:'com.projectaccount.mobile'}}),/PASSKEY_ASSOCIATION/);
  assert.throws(()=>createPasskeyAssociationBundle({...sample(),
    backendContractHash:'fixture'}),/PASSKEY_ASSOCIATION/);
});

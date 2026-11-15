#!/usr/bin/env node
/**
 * RC262 — generated-project-only WebAuthn trust association *export*.
 *
 * This writes REVIEW artifacts only. It never adds a fake signing
 * entitlement, changes an app ID, publishes a website file or claims that
 * Android Digital Asset Links / Apple's CDN have verified the relationship.
 */
import {existsSync,readFileSync,realpathSync,mkdirSync,mkdtempSync,writeFileSync,renameSync,rmSync} from 'node:fs';
import {resolve,dirname,join,sep,isAbsolute,relative} from 'node:path';
import {pathToFileURL} from 'node:url';
import {verifyFableContract} from './verify-fable-contract.mjs';

const hexByte='[0-9A-F]{2}';
const fingerprint=new RegExp('^'+hexByte+(':'+hexByte).repeat(31)+'$');
const appId=/^[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)+$/;
const teamId=/^[A-Z0-9]{10}$/;
const bundle=/^[A-Za-z][A-Za-z0-9_-]*(?:\.[A-Za-z0-9_-]+)+$/;
const hash=/^[a-f0-9]{64}$/;
const forbiddenDomain=/(\.test|\.invalid|\.localhost|\.local|\.example)$/;

function fail(message){throw new Error('PASSKEY_ASSOCIATION: '+message);}
function validDomain(rpId){
  if(typeof rpId!=='string'||rpId.length>253||
      rpId!==rpId.toLowerCase()||
      !rpId.includes('.')||rpId.startsWith('*.')||
      !/^[a-z0-9.-]+$/.test(rpId)||forbiddenDomain.test(rpId)||
      ['example.com','example.org','example.net','localhost'].includes(rpId))
    return false;
  return rpId.split('.').every(label=>label.length>0&&label.length<=63&&
    /^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$/.test(label));
}
function exactObject(value,keys){
  return value!==null&&typeof value==='object'&&!Array.isArray(value)&&
    Object.keys(value).sort().join(',')===keys.slice().sort().join(',');
}
export function createPasskeyAssociationBundle(config) {
  if(!exactObject(config,['kind','schemaVersion','projectId','backendContractHash','rpId','android','ios'])||
      config.kind!=='fable.passkey-domain-association'||
      config.schemaVersion!==1 ||
      typeof config.projectId!=='string'||!config.projectId.trim()||
      typeof config.backendContractHash!=='string'||!hash.test(config.backendContractHash) ||
      !validDomain(config.rpId))
    fail('Required real project ID, SHA-256 contract hash and HTTPS RP host');
  if(!exactObject(config.android,['packageName','sha256CertFingerprints'])||
      !appId.test(config.android.packageName)||
      config.android.packageName.startsWith('com.example.')||
      !Array.isArray(config.android.sha256CertFingerprints)||
      config.android.sha256CertFingerprints.length<1||
      config.android.sha256CertFingerprints.length>10)
    fail('Android package and release signing fingerprints are required');
  const certs=config.android.sha256CertFingerprints.map(value=>{
    if(typeof value!=='string'||!fingerprint.test(value.toUpperCase()))
      fail('Signing certificate fingerprint must contain exactly 32 SHA-256 bytes');
    return value.toUpperCase();
  });
  if(new Set(certs).size!==certs.length)fail('Repeated Android signing certificate');
  if(!exactObject(config.ios,['teamId','bundleId'])||
      !teamId.test(config.ios.teamId)||
      !bundle.test(config.ios.bundleId)||
      config.ios.bundleId.startsWith('com.example.'))
    fail('Real Apple Team ID and Bundle ID must be supplied');
  const origin='https://'+config.rpId;
  const assetlinks=[{
    relation:['delegate_permission/common.get_login_creds'],
    target:{namespace:'android_app',package_name:config.android.packageName,
      sha256_cert_fingerprints:certs},
  }];
  const apple={
    webcredentials:{apps:[config.ios.teamId+'.'+config.ios.bundleId]},
  };
  const entitlements=[
    '<?xml version="1.0" encoding="UTF-8"?>',
    '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">',
    '<plist version="1.0"><dict>',
    '<key>com.apple.developer.associated-domains</key>',
    '<array><string>webcredentials:'+config.rpId+'</string></array>',
    '</dict></plist>','',
  ].join('\n');
  const readme=[
    '# Fable Passkeys — review and deployment checklist',
    '',
    'Generated only for project '+config.projectId+'; Backend contract SHA-256 '+config.backendContractHash+'.',
    'Relying-party host: '+origin+' (must exactly match the REAL Backend PASSKEY_RP_ID).',
    '',
    '1. Independently compare Android applicationId and the ACTUAL distribution/release certificate fingerprint.',
    '2. Publish the bundled assetlinks.json at '+origin+'/.well-known/assetlinks.json over HTTPS, with application/json.',
    '3. Independently verify the Apple Team ID and production Bundle ID.',
    '4. Merge the associated-domains key from FablePasskeys.entitlements into the REAL signed iOS Runner entitlement.',
    '5. Publish apple-app-site-association WITHOUT a .json extension at '+origin+'/.well-known/apple-app-site-association, HTTPS application/json.',
    '6. Validate both links on actual signed Android/iOS applications and Apple CDN; source export is NOT live validation.',
    '7. Confirm matching Fable Backend PASSKEY_RP_ID, allowed origin and registered public WebAuthn methods.',
    '',
    'This tool NEVER edits signing profiles, Android application IDs, app entitlements, DNS or hosted website files.',
    'It does NOT imply W6 E2E passing or production GO.',
    '',
  ].join('\n');
  return Object.freeze({
    'site/.well-known/assetlinks.json':JSON.stringify(assetlinks,null,2)+'\n',
    'site/.well-known/apple-app-site-association':JSON.stringify(apple,null,2)+'\n',
    'ios/FablePasskeys.entitlements':entitlements,
    'README.md':readme,
  });
}

function argsOf(argv){
  const args={};
  for(let i=0;i<argv.length;i++){
    const key=argv[i];
    if(!['--root','--config','--out'].includes(key) || args[key] || !argv[i+1] ||
       argv[i+1].startsWith('--'))
      fail('Usage: node tools/generate-passkey-associations.mjs --root PROJECT --config RELATIVE_JSON --out RELATIVE_EMPTY_DIRECTORY');
    args[key]=argv[++i];
  }
  if(!args['--config']||!args['--out'])
    fail('Provide explicit project config and output directory; no guessed RP or app identities');
  return args;
}
function within(root,path){
  const rel=relative(root,path);
  return rel!==''&&!rel.startsWith('..'+sep)&&rel!=='..'&&!isAbsolute(rel);
}
export function exportPasskeyAssociations({root,configFile,outDir}){
  const project=realpathSync(root);
  const configPath=realpathSync(resolve(project,configFile));
  if(!within(project,configPath))fail('Association config must be within the selected project');
  const out=resolve(project,outDir);
  if(!within(project,out)||existsSync(out))fail('Output must be a new directory inside selected project');
  const parent=dirname(out);
  mkdirSync(parent,{recursive:true});
  if(!within(project,realpathSync(parent))&&realpathSync(parent)!==project)
    fail('Output may not follow a symlink outside the selected project');
  const imported=JSON.parse(readFileSync(join(project,'assets/contracts/contract.json'),'utf8'));
  const config=JSON.parse(readFileSync(configPath,'utf8'));
  if(imported?.contractHash!==config.backendContractHash||
      imported?.project?.id!==config.projectId)
    fail('Association config is stale or does not match the imported Fable Backend contract');
  const verification=verifyFableContract(project,{
    mode:'project',
    expectedProjectId:config.projectId,
    expectedContractHash:config.backendContractHash,
  });
  if(!verification.ok)
    fail('Generated-project Backend provenance invalid; reimport Fable handoff and verify project pins');
  const files=createPasskeyAssociationBundle(config);
  const temp=mkdtempSync(join(parent,'.fable-passkeys-'));
  try{
    for(const [name,body] of Object.entries(files)){
      const target=join(temp,name);
      mkdirSync(dirname(target),{recursive:true});
      writeFileSync(target,body,{encoding:'utf8',flag:'wx'});
    }
    if(existsSync(out))fail('Output directory appeared during association generation');
    renameSync(temp,out);
    return out;
  }finally{if(existsSync(temp))rmSync(temp,{force:true,recursive:true});}
}

if(process.argv[1]&&import.meta.url===pathToFileURL(resolve(process.argv[1])).href){
  try{
    const a=argsOf(process.argv.slice(2));
    const output=exportPasskeyAssociations({
      root:resolve(a['--root']??process.cwd()),
      configFile:a['--config'],outDir:a['--out'],
    });
    process.stdout.write('Passkey domain association review bundle: '+output+'\n');
    process.stdout.write('REQUIRES independent signing, domain publication, real device E2E; NO_GO until verified.\n');
  }catch(error){
    process.stderr.write((error instanceof Error?error.message:String(error))+'\n');
    process.exitCode=1;
  }
}

#!/usr/bin/env node
/**
 * Flutter Wizard integration point.
 * Reads a verified, backend-generated export. No default session mode is invented.
 * The deployed backend's GET /auth/session-policy wins at runtime.
 */
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import {verifyFableContract} from './verify-fable-contract.mjs';

export function validateSessionPolicyForWizard(policy) {
  if(!policy || typeof policy!=='object' || Array.isArray(policy) ||
     !['single','multi'].includes(policy.mode) ||
     !Number.isInteger(policy.maxActive) || policy.maxActive<0 || policy.maxActive>100 ||
     (policy.mode==='single' && policy.maxActive!==1) ||
     !['revoke-oldest','reject-new'].includes(policy.overflow) ||
     policy.runtimeEndpoint!=='/auth/session-policy' ||
     policy.runtimeAuthoritative!==true) {
    throw new Error('Invalid or missing backend session policy. Re-export from a supported Fable Backend.');
  }
  return Object.freeze({
    mode:policy.mode,
    maxActive:policy.maxActive,
    overflow:policy.overflow,
    runtimeEndpoint:policy.runtimeEndpoint,
    runtimeAuthoritative:true,
    allowsMultipleSessions:policy.mode==='multi' && (policy.maxActive===0 || policy.maxActive>1),
  });
}

export function readWizardSessionPolicy(root=process.cwd()) {
  const cwd=resolve(root);
  const gate=verifyFableContract(cwd,{mode:'source'});
  if(!gate.ok)throw new Error('Backend export integrity check failed: '+gate.failures.join(','));
  const contract=JSON.parse(readFileSync(resolve(cwd,'assets/contracts/contract.json'),'utf8'));
  const core=JSON.parse(readFileSync(resolve(cwd,'assets/contracts/mobile-core-operations.json'),'utf8'));
  const declared=[...(contract.operations??[]),...(core.operations??[])];
  if(!declared.some(o=>o.operationId==='auth.session-policy' &&
    o.method==='GET' && o.path==='/auth/session-policy' && o.public===true)) {
    throw new Error('Backend did not publish the live auth.session-policy operation');
  }
  return validateSessionPolicyForWizard(contract.core?.auth?.sessionPolicy);
}

if(process.argv[1] && import.meta.url===pathToFileURL(resolve(process.argv[1])).href) {
  try {
    const policy=readWizardSessionPolicy(process.argv[2]??process.cwd());
    process.stdout.write(JSON.stringify(policy,null,2)+'\n');
  } catch(error) {
    process.stderr.write(String(error.message??error)+'\n');
    process.exitCode=1;
  }
}

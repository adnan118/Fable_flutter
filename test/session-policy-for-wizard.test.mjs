import test from 'node:test';
import assert from 'node:assert/strict';
import {validateSessionPolicyForWizard,readWizardSessionPolicy} from '../tools/read-session-policy.mjs';

test('Wizard receives single, bounded multi and unlimited mode without invented defaults',()=>{
  for(const [mode,max,expected] of [
    ['single',1,false],
    ['multi',3,true],
    ['multi',0,true],
    ['multi',1,false],
  ]){
    const p=validateSessionPolicyForWizard({mode,maxActive:max,overflow:'revoke-oldest',runtimeEndpoint:'/auth/session-policy',runtimeAuthoritative:true});
    assert.equal(p.allowsMultipleSessions,expected);
  }
});

test('Absent or invalid backend session policy fails closed',()=>{
  const base={mode:'multi',maxActive:5,overflow:'reject-new',runtimeEndpoint:'/auth/session-policy',runtimeAuthoritative:true};
  for(const invalid of [null,{}, {...base,mode:'limited'},{...base,maxActive:-1},{...base,overflow:'silent'},{...base,runtimeEndpoint:'/auth/login'},{...base,runtimeAuthoritative:false}]){
    assert.throws(()=>validateSessionPolicyForWizard(invalid));
  }
});

test('Existing starter fixture does not pretend it has a backend-confirmed policy',()=>{
  assert.throws(()=>readWizardSessionPolicy(process.cwd()),/Invalid or missing backend session policy/);
});

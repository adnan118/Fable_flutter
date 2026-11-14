import test from 'node:test';
import assert from 'node:assert/strict';
import {
  existsSync,mkdtempSync,mkdirSync,writeFileSync,readFileSync,
  readdirSync,rmSync,symlinkSync,
} from 'node:fs';
import {tmpdir} from 'node:os';
import {join,dirname,resolve} from 'node:path';
import {
  planOtherBackendContractRetirement,applyOtherBackendWithArchivedFable,
} from '../tools/retire-fable-contracts-for-other-backend.mjs';

function fixture(t,{withFable=true}={}){
  const root=mkdtempSync(join(tmpdir(),'fable-rc211-w4-'));
  t.after(()=>rmSync(root,{force:true,recursive:true}));
  const write=(name,value)=>{
    const path=join(root,name);
    mkdirSync(dirname(path),{recursive:true});
    writeFileSync(path,typeof value==='string'?value:JSON.stringify(value));
  };
  write('assets/config/backend.json',{
    schemaVersion:1,backend:{kind:'fable',status:'ready'},contractImported:true,
  });
  write('assets/config/frontend-setup.json',{source:'original-fable'});
  if(withFable){
    write('assets/contracts/contract.json',{
      kind:'fable.client-contract',project:{id:'original-fable-project'},
      contractHash:'a'.repeat(64),
    });
    write('assets/contracts/flutter-handoff.json',{kind:'fable.flutter-handoff'});
    write('assets/contracts/features/old.json',{feature:'old'});
  }
  return {root,write};
}
const config=root=>JSON.parse(readFileSync(join(root,'assets/config/backend.json'),'utf8'));
test('RC211 W4 archives active Fable contracts before approved Other Backend apply',t=>{
  const f=fixture(t);
  const plan=planOtherBackendContractRetirement(f.root);
  assert.equal(plan.required,true);
  let invoked=false;
  const result=applyOtherBackendWithArchivedFable(f.root,()=>{
    invoked=true;
    f.write('assets/config/backend.json',{backend:{kind:'other',status:'pending'},contractImported:false});
    return {applied:true};
  });
  assert.equal(invoked,true);
  assert.equal(result.applied,true);
  assert.match(result.retiredFableContracts,/^\.fable\/retired-fable-contracts\//);
  assert.equal(config(f.root).backend.kind,'other');
  assert.equal(existsSync(join(f.root,'assets/contracts')),false);
  assert.equal(existsSync(join(f.root,result.retiredFableContracts,'contracts','contract.json')),true);
  assert.equal(existsSync(join(f.root,result.retiredFableContracts,'contracts','features','old.json')),true);
  assert.equal(existsSync(join(f.root,result.retiredFableContracts,'prior-setup','assets/config/backend.json')),true);
});
test('RC211 W4 does not invent an archive for a brand new Other Backend project',t=>{
  const f=fixture(t,{withFable:false});
  const result=applyOtherBackendWithArchivedFable(f.root,()=>{
    f.write('assets/config/backend.json',{backend:{kind:'other',status:'pending'}});
    return {applied:true};
  });
  assert.equal(result.retiredFableContracts,null);
  assert.equal(config(f.root).backend.kind,'other');
});
test('RC211 W4 rolls back prior Fable contract and setup on failed Other apply',t=>{
  const f=fixture(t);
  const original=readFileSync(join(f.root,'assets/config/backend.json'));
  const setup=readFileSync(join(f.root,'assets/config/frontend-setup.json'));
  assert.throws(()=>applyOtherBackendWithArchivedFable(f.root,()=>{
    f.write('assets/config/backend.json',{backend:{kind:'other'}});
    f.write('assets/config/frontend-setup.json',{source:'changed'});
    f.write('.fable/frontend-setup.json',{status:'partial'});
    throw Error('test-induced write failure');
  }),/test-induced write failure/);
  assert.deepEqual(readFileSync(join(f.root,'assets/config/backend.json')),original);
  assert.deepEqual(readFileSync(join(f.root,'assets/config/frontend-setup.json')),setup);
  assert.equal(existsSync(join(f.root,'.fable/frontend-setup.json')),false);
  assert.equal(existsSync(join(f.root,'assets/contracts/contract.json')),true);
  assert.equal(readdirSync(join(f.root,'.fable/retired-fable-contracts')).length,0);
});
test('RC211 W4 refuses active contract tree containing an external file symlink',t=>{
  const f=fixture(t);
  symlinkSync(join(f.root,'assets/config/backend.json'),
    join(f.root,'assets/contracts/external-link.json'));
  let written=false;
  assert.throws(()=>applyOtherBackendWithArchivedFable(f.root,()=>{
    written=true;return {applied:true};
  }),/unsafe link/);
  assert.equal(written,false);
  assert.equal(config(f.root).backend.kind,'fable');
  assert.equal(existsSync(join(f.root,'assets/contracts/contract.json')),true);
});
test('RC211 W4 refuses other-provider contracts instead of archiving unknown data',t=>{
  const f=fixture(t);
  f.write('assets/contracts/contract.json',{kind:'external.contract',project:{id:'real'}});
  assert.throws(()=>planOtherBackendContractRetirement(f.root),/Existing external contract/);
  assert.equal(config(f.root).backend.kind,'fable');
});
test('RC211 W4 preflight rejects a symlinked state destination',t=>{
  const f=fixture(t);
  const path=join(f.root,'.fable');
  mkdirSync(path,{recursive:true});
  symlinkSync(join(f.root,'assets/config/backend.json'),join(path,'frontend-setup.json'));
  assert.throws(()=>planOtherBackendContractRetirement(f.root),/symlinked setup path/);
  assert.equal(existsSync(join(f.root,'assets/contracts/contract.json')),true);
});
test('RC211 W4 respects explicit non-approval: planning itself performs no file writes',t=>{
  const f=fixture(t);
  const source=readFileSync(join(f.root,'assets/contracts/contract.json'));
  const configBefore=readFileSync(join(f.root,'assets/config/backend.json'));
  const plan=planOtherBackendContractRetirement(f.root);
  assert.equal(plan.required,true);
  assert.deepEqual(readFileSync(join(f.root,'assets/contracts/contract.json')),source);
  assert.deepEqual(readFileSync(join(f.root,'assets/config/backend.json')),configBefore);
  assert.equal(existsSync(join(f.root,'.fable/retired-fable-contracts')),false);
});
test('RC211 W4 can archive a later independently re-imported Fable contract without overwriting earlier archive',t=>{
  const f=fixture(t);
  const action=()=>applyOtherBackendWithArchivedFable(f.root,()=>({applied:true}));
  const first=action();
  assert.equal(existsSync(join(f.root,first.retiredFableContracts,'contracts/contract.json')),true);
  f.write('assets/contracts/contract.json',{kind:'fable.client-contract',project:{id:'another'},contractHash:'b'.repeat(64)});
  const second=action();
  assert.notEqual(first.retiredFableContracts,second.retiredFableContracts);
  assert.equal(existsSync(join(f.root,first.retiredFableContracts,'contracts/contract.json')),true);
  assert.equal(existsSync(join(f.root,second.retiredFableContracts,'contracts/contract.json')),true);
});

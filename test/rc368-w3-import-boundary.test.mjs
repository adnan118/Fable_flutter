import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,mkdirSync,writeFileSync,symlinkSync,rmSync,readFileSync} from 'node:fs';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {inspectW3ImportedConfig} from '../tools/verify-current-w3-handoff.mjs';
import {verifyFableContract} from '../tools/verify-fable-contract.mjs';

const ready={
  kind:'fable.mobile-backend-configuration',schemaVersion:1,
  backend:{kind:'fable',adapter:'fable-contract',status:'ready'},
  contractImported:true,
};
function fixture(fn){
  const root=mkdtempSync(join(tmpdir(),'fable-rc368-'));
  try{
    mkdirSync(join(root,'assets/config'),{recursive:true});
    writeFileSync(join(root,'assets/config/backend.json'),
      JSON.stringify(ready));
    return fn(root);
  }finally{rmSync(root,{recursive:true,force:true});}
}
test('RC368 W3 accepts an ordinary source-pinned ready Fable config',()=>{
  fixture(root=>{
    const result=inspectW3ImportedConfig(root);
    assert.equal(result.backend,'fable');
    assert.equal(result.configurationVerified,true);
    assert.equal(result.sourceOnly,true);
  });
});
test('RC368 W3 refuses a syntactically valid but non-Fable import',()=>{
  fixture(root=>{
    writeFileSync(join(root,'assets/config/backend.json'),JSON.stringify({
      ...ready,backend:{kind:'external',adapter:'custom',status:'ready'},
    }));
    assert.throws(()=>inspectW3ImportedConfig(root),/not project-ready/);
  });
});
test('RC368 source verification rejects symlinked Backend config',{
  skip:process.platform==='win32',
},()=>{
  fixture(root=>{
    const original=join(root,'assets/config/backend.json');
    const actual=join(root,'outside.json');
    writeFileSync(actual,JSON.stringify(ready));
    rmSync(original);
    symlinkSync(actual,original);
    assert.throws(()=>inspectW3ImportedConfig(root),/symlink/i);
    const report=verifyFableContract(root,{mode:'source'});
    assert.equal(report.ok,false);
    assert.ok(report.failures.includes('cannot_read_or_parse:assets/config/backend.json'));
  });
});
test('RC368 W3 refuses a symlinked ancestor of the imported source',{
  skip:process.platform==='win32',
},()=>{
  fixture(root=>{
    const folder=join(root,'real-assets');
    mkdirSync(join(folder,'config'),{recursive:true});
    writeFileSync(join(folder,'config/backend.json'),JSON.stringify(ready));
    rmSync(join(root,'assets'),{recursive:true,force:true});
    symlinkSync(folder,join(root,'assets'),'dir');
    assert.throws(()=>inspectW3ImportedConfig(root),/symlink/i);
    const report=verifyFableContract(root,{mode:'source'});
    assert.equal(report.ok,false);
    assert.ok(report.failures.includes('cannot_read_or_parse:assets/config/backend.json'));
  });
});
test('RC368 W3 rejects oversized config without parsing large untrusted JSON',()=>{
  fixture(root=>{
    writeFileSync(join(root,'assets/config/backend.json'),
      JSON.stringify(ready)+' '.repeat(16*1024*1024));
    assert.throws(()=>inspectW3ImportedConfig(root),/Oversized/);
    const result=verifyFableContract(root,{mode:'source'});
    assert.ok(result.failures.includes('cannot_read_or_parse:assets/config/backend.json'));
  });
});
test('RC368 W3 imported configuration must be validated before accepting export comparison',()=>{
  const w3=readFileSync(new URL('../tools/verify-current-w3-handoff.mjs',import.meta.url),'utf8');
  const contract=readFileSync(new URL('../tools/verify-fable-contract.mjs',import.meta.url),'utf8');
  assert.ok(w3.indexOf('inspectW3ImportedConfig(options.flutterRoot)')<
    w3.indexOf('const backend=readBackendExport(options.backendExportRoot)'));
  assert.match(w3,/report\.frontendConfiguration=frontendConfiguration/);
  assert.match(contract,/assertRegularProjectPath\(root,join\(root,path\),'file'\)/);
  assert.match(contract,/lstatSync\(safe\)\.size>16\*1024\*1024/);
});

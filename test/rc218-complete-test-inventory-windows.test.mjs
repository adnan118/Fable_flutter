import test from 'node:test';
import assert from 'node:assert/strict';
import {
  mkdtempSync,mkdirSync,readFileSync,readdirSync,rmSync,
  symlinkSync,writeFileSync,
} from 'node:fs';
import {tmpdir} from 'node:os';
import {join,resolve} from 'node:path';
import {
  discoverTrackedNodeTests,buildOneCommandPlan,flutterChildSpec,
  localRunner,resolveBackendCheckoutRoot,saveOneCommandReport,
  evaluateOneCommandPlan,
} from '../tools/fable-one-command.mjs';

const root='/tmp/fable-rc218-fixture';
const fakeRead=()=>'',fakeDiscover=()=>({
  files:[],rejected:[],gitInventoryVerified:false,
});
const setup=(extra={})=>buildOneCommandPlan({
  root,backendRoot:join(root,'Fable-Backend-RC66'),
  packageScripts:{'test:one':'node --test test/scripted.test.mjs'},
  exists:()=>true,safeTestRead:fakeRead,gitTestDiscovery:fakeDiscover,
  flutterAvailable:false,...extra,
});

test('RC218 tracked historical Node tests parsed from NUL-delimited Git inventory',()=>{
  const git=(command,args,opts)=>{
    assert.equal(command,'git');
    assert.deepEqual(args,['ls-files','--cached','-z','--','test','tools']);
    assert.equal(opts.cwd,root);
    return 'test/a.test.mjs\0tools/b.test.mjs\0test/a.test.mjs\0';
  };
  const result=discoverTrackedNodeTests(root,{runGit:git,safeRead:fakeRead});
  assert.equal(result.gitInventoryVerified,true);
  assert.deepEqual(result.files,['test/a.test.mjs','tools/b.test.mjs']);
});
test('RC218 tracked inventory rejects dangerous traversal and untrusted paths',()=>{
  const result=discoverTrackedNodeTests(root,{
    runGit:()=>[
      'test/ok.test.mjs','tools/deep/source.test.mjs',
      '../untrusted.test.mjs','test/../../untrusted.test.mjs',
      'private/hidden.test.mjs','tools/evil;rm.test.mjs',
    ].join('\0')+'\0',
    safeRead:fakeRead,
  });
  assert.deepEqual(result.files,['test/ok.test.mjs','tools/deep/source.test.mjs']);
  assert.equal(result.rejected.length,4);
});
test('RC218 tracked Node audit refuses symlinked source files',()=>{
  const x=discoverTrackedNodeTests(root,{
    runGit:()=> 'test/safe.test.mjs\0test/unsafe.test.mjs\0',
    safeRead:(_base,p)=>{if(p.includes('unsafe'))throw Error('W5_EVIDENCE_SYMLINK');},
  });
  assert.deepEqual(x.files,['test/safe.test.mjs']);
  assert.deepEqual(x.rejected,['test/unsafe.test.mjs']);
});
test('RC218 failed Git inspection does not invent a complete test inventory',()=>{
  const x=discoverTrackedNodeTests(root,{runGit:()=>{throw Error('no Git');}});
  assert.equal(x.gitInventoryVerified,false);
  assert.deepEqual(x.files,[]);
});
test('RC218 unregistered legacy tests run with the same single pnpm command',()=>{
  const p=setup({gitTestDiscovery:()=>({
    files:['test/unregistered.test.mjs','test/scripted.test.mjs'],
    rejected:[],gitInventoryVerified:true,
  })});
  const first=p.plan.find(x=>x.id==='NODE_ALL_EXISTING_TEST_SCRIPTS');
  assert.deepEqual(first.args,[
    '--test','--test-concurrency=4',
    'test/scripted.test.mjs','test/unregistered.test.mjs',
  ]);
  assert.equal(p.unregisteredNodeTests,1);
  assert.equal(p.filesDiscovered,2);
  assert.equal(p.gitTestInventoryVerified,true);
});
test('RC218 safe test skip leaves a visible incomplete inventory',()=>{
  const p=setup({gitTestDiscovery:()=>({
    files:['test/extra.test.mjs','test/unsafe.test.mjs'],
    rejected:[],gitInventoryVerified:true,
  }),safeTestRead:(_root,p)=>{if(p.includes('unsafe'))throw Error('link');}});
  assert.equal(p.filesDiscovered,2);
  assert.ok(p.unsupportedTestCommands.some(x=>x.includes('UNSAFE_NODE_TEST_FILE')));
  const step=p.plan[0];
  const r=evaluateOneCommandPlan(p,[{id:step.id,exitCode:0,
    signal:null,error:null}]);
  assert.equal(r.checks[0].state,'PARTIAL');
});
test('RC218 clean tracked suite may pass locally but never authorizes production',()=>{
  const p=setup({gitTestDiscovery:()=>({
    files:['test/scripted.test.mjs'],rejected:[],gitInventoryVerified:true,
  })});
  const r=evaluateOneCommandPlan(p,[{id:p.plan[0].id,
    exitCode:0,signal:null,error:null}]);
  assert.equal(r.checks[0].state,'LOCAL_CHECK_PASS');
  assert.equal(r.productionReady,false);
  assert.equal(r.releaseDecision,'NO_GO');
});
test('RC218 missing verified Git inventory remains partial even if script tests exit zero',()=>{
  const p=setup();
  const r=evaluateOneCommandPlan(p,[{id:p.plan[0].id,exitCode:0,
    signal:null,error:null}]);
  assert.equal(r.checks[0].state,'PARTIAL');
  assert.equal(r.completeGitTestInventoryVerified,false);
});
test('RC218 Flutter Windows launcher uses cmd.exe only for fixed allowlisted args',()=>{
  const spec=flutterChildSpec({program:'flutter',args:['test',
    'packages/features/fable_auth/test/login_test.dart']},{platform:'win32'});
  assert.equal(spec.command,'cmd.exe');
  assert.deepEqual(spec.args,['/d','/s','/c',
    'flutter test packages/features/fable_auth/test/login_test.dart']);
});
test('RC218 rejects shell injection before Windows native runner',()=>{
  for(const invalid of ['& whoami','x|del','test%PATH%','/tmp/path with spaces',
    'foo^bar','foo>out']){
    assert.throws(()=>flutterChildSpec({program:'flutter',args:[invalid]},
      {platform:'win32'}),/UNSAFE_WINDOWS_FLUTTER_COMMAND/);
  }
});
test('RC218 Flutter POSIX launcher stays no-shell',()=>{
  const spec=flutterChildSpec({program:'flutter',args:['analyze']},{platform:'linux'});
  assert.deepEqual(spec,{command:'flutter',args:['analyze']});
});
test('RC218 native subprocess preserves raw exit code while redacting logs',()=>{
  const calls=[];
  const r=localRunner({program:'flutter',root:'/tmp/app',args:['analyze'],
    timeoutMs:10000},{
    platform:'win32',now:()=>100,
    spawn:(command,args,opts)=>{
      calls.push({command,args,opts});
      return {status:3,signal:null,error:null,stdout:'private token'};
    },
  });
  assert.equal(r.exitCode,3);
  assert.equal(calls[0].command,'cmd.exe');
  assert.equal(calls[0].opts.windowsHide,true);
  assert.equal(JSON.stringify(r).includes('private token'),false);
});
test('RC218 W3 uses actual private Git top-level instead of dirname guess',()=>{
  const top=resolveBackendCheckoutRoot('/workspace/alias/Fable-Backend-RC66',{
    git:(command,args,opts)=>{
      assert.deepEqual(args,['rev-parse','--show-toplevel']);
      assert.ok(opts.cwd.endsWith('Fable-Backend-RC66'));
      return '/workspace/private-Fable-repository\n';
    },
  });
  assert.equal(top,resolve('/workspace/private-Fable-repository'));
});
test('RC218 safe report writer creates a new owner-only JSON without overwriting',t=>{
  const folder=mkdtempSync(join(tmpdir(),'fable-rc218-report-'));
  t.after(()=>rmSync(folder,{recursive:true,force:true}));
  const report={batch:'RC218',productionReady:false};
  const options={stamp:()=> 'fixed-time',unique:()=> 'one'};
  const path=saveOneCommandReport(folder,report,options);
  assert.deepEqual(JSON.parse(readFileSync(path,'utf8')),report);
  assert.equal(readdirSync(join(folder,'.fable/reports')).length,1);
  assert.throws(()=>saveOneCommandReport(folder,report,options),/EEXIST/);
});
test('RC218 refuses a symlinked report folder rather than writing outside project',t=>{
  const folder=mkdtempSync(join(tmpdir(),'fable-rc218-safe-'));
  const outside=mkdtempSync(join(tmpdir(),'fable-rc218-outside-'));
  t.after(()=>{rmSync(folder,{recursive:true,force:true});
    rmSync(outside,{recursive:true,force:true});});
  try {symlinkSync(outside,join(folder,'.fable'),'dir');}
  catch(error){
    if(process.platform==='win32'&&['EPERM','EACCES'].includes(error.code)){
      t.skip('Windows without symlink privilege');return;
    }
    throw error;
  }
  assert.throws(()=>saveOneCommandReport(folder,{productionReady:false}),
    /UNSAFE_REPORT_DIRECTORY/);
  assert.deepEqual(readdirSync(outside),[]);
});

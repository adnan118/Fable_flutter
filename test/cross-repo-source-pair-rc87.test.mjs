import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {mkdtempSync,mkdirSync,copyFileSync,readFileSync,writeFileSync,rmSync} from 'node:fs';
import {join,dirname} from 'node:path';
import {tmpdir} from 'node:os';
import {verifySourcePair} from '../tools/verify-cross-repo-source-pair.mjs';

// A private Backend fixture is assembled locally without real customer code.
// Test the actual crossrepo path rather than only the public source-only mode.
const filenames=[
 'docs/integrations/FABLE-CROSS-REPO-SOURCE-PAIR-RC86.json',
 'docs/integrations/FABLE-AUTH-OPERATIONS-RC80.json',
 'docs/integrations/FABLE-FLUTTER-PARITY-MASTER.json',
];
const git=(cwd,...args)=>execFileSync('git',args,{cwd,encoding:'utf8',stdio:'pipe'}).trim();
const write=(path,data)=>{
 mkdirSync(dirname(path),{recursive:true});
 writeFileSync(path,typeof data==='string'?data:JSON.stringify(data,null,2)+'\n');
};
const json=(file)=>JSON.parse(readFileSync(file,'utf8'));
const sha=(data)=>{
 const buffer=Buffer.from(data);
 return createHash('sha1').update(Buffer.from('blob '+buffer.length+'\0')).update(buffer).digest('hex');
};
function fixture(){
 const base=mkdtempSync(join(tmpdir(),'fable-rc87-pair-'));
 const back=join(base,'backend');
 const front=join(base,'frontend');
 mkdirSync(back);mkdirSync(front);
 for(const name of filenames){
  const p=join(front,name);
  mkdirSync(dirname(p),{recursive:true});
  copyFileSync(name,p);
 }
 const auth=json(join(front,filenames[1]));
 const backendAuth={
  name:'auth',version:'4.6.0',
  routes:auth.operations.map(x=>({id:x.id,method:x.method,path:x.path})),
 };
 const authPath=join(back,'Fable-Backend-RC66/blueprints/capabilities/auth/manifest.json');
 const authText=JSON.stringify(backendAuth,null,2)+'\n';
 write(authPath,authText);
 for(let i=1;i<50;i++){
  const name='cap-'+String(i).padStart(2,'0');
  write(join(back,'Fable-Backend-RC66/blueprints/capabilities',name,'manifest.json'),
   {name,version:'1.0.0',routes:[]});
 }
 git(back,'init','-q');
 git(back,'config','user.name','Fable RC87 test');
 git(back,'config','user.email','fable-test@example.invalid');
 git(back,'add','.');
 git(back,'commit','-qm','audited baseline');
 const baseline=git(back,'rev-parse','HEAD');
 const pairPath=join(front,filenames[0]);
 const pair=json(pairPath);
 pair.backend.sourceCommitAtAudit=baseline;
 pair.backend.authBlueprintBlobSha=sha(authText);
 write(pairPath,pair);
 auth.backendShaAtAudit=baseline;
 write(join(front,filenames[1]),auth);
 const master=json(join(front,filenames[2]));
 master.backendMainAtAudit=baseline;
 write(join(front,filenames[2]),master);
 return{base,back,front,baseline,authPath};
}
test('RC87 allows packaging/docs updates but rejects unreviewed Backend source drift',()=>{
 const x=fixture();
 try{
  const r=verifySourcePair({frontendRoot:x.front,backendRoot:x.back});
  assert.equal(r.backendRouteCount,40);
  assert.equal(r.backendCapabilityCount,50);
  assert.equal(r.backendSourceUnchangedSinceAudit,true);
  write(join(x.back,'docs/packaging-note.md'),'allowed only outside audited backend source');
  git(x.back,'add','.');
  git(x.back,'commit','-qm','archive tooling docs');
  assert.equal(verifySourcePair({frontendRoot:x.front,backendRoot:x.back})
   .backendSourceUnchangedSinceAudit,true);
  const other=join(x.back,'Fable-Backend-RC66/blueprints/capabilities/cap-01/manifest.json');
  const changed=json(other);
  changed.version='2.0.0';
  write(other,changed);
  git(x.back,'add','.');
  git(x.back,'commit','-qm','unreviewed source change');
  assert.throws(()=>verifySourcePair({frontendRoot:x.front,backendRoot:x.back}),
   /Backend operational source drift/);
 }finally{rmSync(x.base,{recursive:true,force:true});}
});
test('RC87 rejects forged private Flutter pin and removed capability manifests',()=>{
 const x=fixture();
 try{
  write(join(x.back,'docs/RC86-SOURCE-PAIR.json'),{
   backend:{auditCommit:x.baseline},
   flutter:{verifiedMainCommit:'f'.repeat(40)},
  });
  assert.throws(()=>verifySourcePair({frontendRoot:x.front,backendRoot:x.back}),
   /private Backend manifest does not approve/);
  rmSync(join(x.back,'docs/RC86-SOURCE-PAIR.json'));
  // Uncommitted removal is rejected even before capability counting.
  rmSync(join(x.back,'Fable-Backend-RC66/blueprints/capabilities/cap-49'),
   {recursive:true,force:true});
  assert.throws(()=>verifySourcePair({frontendRoot:x.front,backendRoot:x.back}),
   /Backend tracked worktree differs/);
  // A forged inventory count is independently rejected on clean Git.
  git(x.back,'reset','--hard','HEAD');
  const p=join(x.front,filenames[0]);
  const current=json(p);
  current.counts.backendCapabilityBlueprints=49;
  write(p,current);
  assert.throws(()=>verifySourcePair({frontendRoot:x.front,backendRoot:x.back}),
   /Backend capability inventory changed/);
 }finally{rmSync(x.base,{recursive:true,force:true});}
});

test('RC87 refuses a modified tracked Backend file despite an unchanged Git commit',()=>{
 const x=fixture();
 try{
  write(join(x.back,'docs/packaging-note.md'),'committed note');
  git(x.back,'add','.');
  git(x.back,'commit','-qm','allowed packaging note');
  assert.equal(verifySourcePair({frontendRoot:x.front,backendRoot:x.back})
   .backendSourceUnchangedSinceAudit,true);
  write(join(x.back,'docs/packaging-note.md'),'uncommitted edited note');
  assert.throws(()=>verifySourcePair({frontendRoot:x.front,backendRoot:x.back}),
   /Backend tracked worktree differs/);
 }finally{rmSync(x.base,{recursive:true,force:true});}
});

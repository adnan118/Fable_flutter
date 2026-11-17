import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,mkdirSync,writeFileSync,symlinkSync,rmSync} from 'node:fs';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {readFileSync} from 'node:fs';
import {
  pathEntryExists,assertRegularProjectPath,generatedTreeExactlyMatches,
} from '../tools/rc366-safe-source-tree.mjs';

const prefix='packages/features/fable_test_ci/';
const manifest=new Map([
  [prefix+'lib/src/domain/entity.dart','class Entity {}\n'],
  [prefix+'pubspec.yaml','name: fable_test_ci\n'],
]);
function fixture(fn){
  const root=mkdtempSync(join(tmpdir(),'fable-rc366-'));
  const dest=join(root,'packages/features/fable_test_ci');
  try{
    mkdirSync(join(dest,'lib/src/domain'),{recursive:true});
    for(const [path,body] of manifest)
      writeFileSync(join(dest,path.slice(prefix.length)),body);
    return fn({root,dest});
  }finally{rmSync(root,{recursive:true,force:true});}
}
test('RC366 only a byte-exact generated tree is eligible for rollback',()=>{
  fixture(({dest,root})=>{
    assert.equal(generatedTreeExactlyMatches(dest,manifest,prefix),true);
    assert.equal(assertRegularProjectPath(root,join(dest,'pubspec.yaml'),'file'),
      join(dest,'pubspec.yaml'));
  });
});
test('RC366 preserves another writer\'s added file',()=>{
  fixture(({dest})=>{
    writeFileSync(join(dest,'new-user-file.dart'),'other author\n');
    assert.equal(generatedTreeExactlyMatches(dest,manifest,prefix),false);
  });
});
test('RC366 preserves a concurrent empty directory, not only changed files',()=>{
  fixture(({dest})=>{
    mkdirSync(join(dest,'independent-work'));
    assert.equal(generatedTreeExactlyMatches(dest,manifest,prefix),false);
  });
});
test('RC366 preserves a modified generated file',()=>{
  fixture(({dest})=>{
    writeFileSync(join(dest,'pubspec.yaml'),'someone changed it');
    assert.equal(generatedTreeExactlyMatches(dest,manifest,prefix),false);
  });
});
test('RC366 refuses an unsafe input ancestor and traversal',()=>{
  fixture(({root,dest})=>{
    assert.throws(()=>assertRegularProjectPath(root,join(root,'..','out.dart')),/escapes/);
    assert.throws(()=>assertRegularProjectPath(root,dest,'file'),/Non-regular/);
    assert.throws(()=>assertRegularProjectPath(root,join(dest,'missing'),'file'));
  });
});
test('RC366 detects dangling symlink destinations (POSIX only)',{
  skip:process.platform==='win32',
},()=>{
  fixture(({root,dest})=>{
    const dangling=join(root,'dangling-package');
    symlinkSync(join(root,'missing-destination'),dangling);
    assert.equal(pathEntryExists(dangling),true);
    assert.throws(()=>assertRegularProjectPath(root,dangling,'file'),/Symlink/);
    assert.equal(generatedTreeExactlyMatches(dangling,manifest,prefix),false);
    const linked=join(dest,'lib/src/external');
    symlinkSync(join(root,'missing-data'),linked);
    assert.equal(generatedTreeExactlyMatches(dest,manifest,prefix),false);
  });
});
test('RC366 neither generator recursively deletes packages with foreign files',()=>{
  const bulk=readFileSync(new URL('../tools/generate-selected-project-features-rc309.mjs',import.meta.url),'utf8');
  const single=readFileSync(new URL('../tools/generate-typed-feature-rc116.mjs',import.meta.url),'utf8');
  for(const src of [bulk,single]){
    assert.match(src,/generatedTreeExactlyMatches/);
    assert.match(src,/pathEntryExists\(destination\)/);
    assert.match(src,/assertRegularProjectPath/);
    assert.match(src,/\.\/rc366-safe-source-tree\.mjs/);
  }
  assert.doesNotMatch(single,/if\(created\)rmSync\(destination/);
  assert.doesNotMatch(bulk,/if\(safe\)rmSync\(item\.destination/);
});

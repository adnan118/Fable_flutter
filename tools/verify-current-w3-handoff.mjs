#!/usr/bin/env node
/** RC210 W3 — offline, read-only current private Backend export to Flutter import
 * verification. Requires an explicit independent Backend commit expectation.
 * Does NOT substitute for native Flutter, live providers or production E2E.
 */
import {lstatSync,readFileSync,realpathSync} from 'node:fs';
import {resolve,join} from 'node:path';
import {execFileSync} from 'node:child_process';
import {pathToFileURL} from 'node:url';
import {compareW3CurrentHandoff,W3_REQUIRED_DOCUMENTS} from './w3-handoff-integrity.mjs';
import {verifyFableContract} from './verify-fable-contract.mjs';

const REQUIRED_KEYS=new Set([
  '--backend-export','--flutter-root','--backend-repo','--expected-backend-sha','--json',
]);
const SHA=/^[0-9a-f]{40}$/;
export function parseW3Options(args) {
  const opts={};
  for(let i=0;i<args.length;i++) {
    const key=args[i];
    if(!REQUIRED_KEYS.has(key)||Object.hasOwn(opts,key))throw Error('Unknown or duplicate W3 option: '+key);
    if(key==='--json') {opts[key]=true;continue;}
    if(!args[i+1] || args[i+1].startsWith('--'))
      throw Error('Missing value for '+key);
    opts[key]=args[++i];
  }
  for(const key of ['--backend-export','--backend-repo','--expected-backend-sha'])
    if(!opts[key])throw Error('Required W3 option: '+key);
  if(!SHA.test(opts['--expected-backend-sha']))
    throw Error('Expected Backend source revision must be a full 40-char Git SHA');
  return {
    backendExportRoot:resolve(opts['--backend-export']),
    flutterRoot:resolve(opts['--flutter-root']??process.cwd()),
    backendRepoRoot:resolve(opts['--backend-repo']),
    expectedBackendSha:opts['--expected-backend-sha'],
    json:Boolean(opts['--json']),
  };
}

const MAX_DOC_BYTES=16*1024*1024;
function readSafeDocument(base,path) {
  const root=resolve(base);
  if(lstatSync(root).isSymbolicLink()||!lstatSync(root).isDirectory())
    throw Error('W3 input directory must not be a symbolic link: '+root);
  const segments=path.split('/');
  let file=root;
  for(let i=0;i<segments.length;i++){
    file=resolve(file,segments[i]);
    const st=lstatSync(file);
    if(st.isSymbolicLink() || (i===segments.length-1?!st.isFile():!st.isDirectory()))
      throw Error('Refusing W3 symlink or non-file: '+path);
    if(i===segments.length-1 && st.size>MAX_DOC_BYTES)
      throw Error('Oversized W3 contract document: '+path);
  }
  return JSON.parse(readFileSync(file,'utf8'));
}
function readBackendExport(root) {
  const out={};
  for(const name of ['manifest.json',...W3_REQUIRED_DOCUMENTS])
    out[name]=readSafeDocument(root,name);
  return out;
}
function readFlutterImport(root) {
  const out={};
  for(const name of W3_REQUIRED_DOCUMENTS)
    out[name]=readSafeDocument(root,'assets/contracts/'+name);
  return out;
}
function verifyBackendGitCheckpoint(root,expected) {
  // Git protects committed source identity; a dirty tracked tree refuses
  // acceptance, and an old historical commit is NOT substituted for main.
  const repo=realpathSync(root);
  const actual=execFileSync('git',['rev-parse','HEAD'],{
    cwd:repo,encoding:'utf8',timeout:5000}).trim();
  const dirty=execFileSync('git',['status','--porcelain','--untracked-files=no'],{
    cwd:repo,encoding:'utf8',timeout:5000}).trim();
  return {actual,verified:actual===expected && SHA.test(actual) && !dirty};
}
export function runW3CurrentHandoff(options) {
  const backend=readBackendExport(options.backendExportRoot);
  const imported=readFlutterImport(options.flutterRoot);
  const repo=verifyBackendGitCheckpoint(options.backendRepoRoot,options.expectedBackendSha);
  const verified=verifyFableContract(options.flutterRoot,{
    mode:'project',
    expectedProjectId:backend['contract.json']?.project?.id,
    expectedContractHash:backend['contract.json']?.contractHash,
  });
  const report=compareW3CurrentHandoff(backend,imported,{
    frontendVerification:verified,backendSourceCommit:repo.actual,
    sourcePinVerified:repo.verified,
  });
  if(!repo.verified)report.issues.push('backend_source_checkpoint_mismatch_or_dirty');
  report.passed=report.issues.length===0;
  // Checking a source commit does not cryptographically establish which
  // source commit produced an already exported contract. Remains unverified.
  report.backendExportProvenanceVerified=false;
  return report;
}
if(process.argv[1]&&import.meta.url===pathToFileURL(resolve(process.argv[1])).href){
  try {
    const opts=parseW3Options(process.argv.slice(2));
    const report=runW3CurrentHandoff(opts);
    process.stdout.write(JSON.stringify(report,null,2)+'\n');
    if(!report.passed)process.exitCode=2;
  }catch(error){
    process.stderr.write('RC210 W3 REFUSED: '+error.message+'\n');
    process.exitCode=2;
  }
}

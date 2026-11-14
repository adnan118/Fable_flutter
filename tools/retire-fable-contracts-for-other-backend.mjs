/**
 * RC211 W4 — switching to Other Backend must never leave an active Fable
 * contract bundle. Preserve the old bundle and decisions under .fable,
 * rather than silently deleting any project data.
 *
 * The caller must have an explicit approved/apply action. This helper owns
 * rollback of the affected setup files if any later write fails.
 */
import {
  existsSync,lstatSync,mkdirSync,readFileSync,readdirSync,renameSync,
  rmSync,writeFileSync,realpathSync,
} from 'node:fs';
import {createHash,randomUUID} from 'node:crypto';
import {dirname,join,relative,resolve,sep} from 'node:path';

const STATE_FILES=Object.freeze([
  'assets/config/backend.json',
  'assets/config/frontend-setup.json',
  '.fable/frontend-setup.json',
  'assets/config/frontend-owned-decisions.json',
  '.fable/frontend-owned-decisions.json',
]);
const MAX_TREE_FILES=5000;
const MAX_TREE_DEPTH=30;

function secureLocalPath(root,rel,{allowMissing=true}={}) {
  const base=resolve(root);
  if(lstatSync(base).isSymbolicLink()||!lstatSync(base).isDirectory())
    throw Error('Project root must be a real directory');
  const resolved=resolve(base,rel);
  const suffix=relative(base,resolved);
  if(suffix==='..'||suffix.startsWith('..'+sep)||suffix=== ''||
      !suffix||suffix.split(sep).includes('..'))
    throw Error('Unsafe project-relative path: '+rel);
  let cursor=base;
  for(const component of suffix.split(sep)){
    cursor=join(cursor,component);
    if(!existsSync(cursor)){
      if(allowMissing)continue;
      throw Error('Required project path is absent: '+rel);
    }
    const stat=lstatSync(cursor);
    if(stat.isSymbolicLink())throw Error('Refusing symlinked setup path: '+rel);
  }
  return resolved;
}
function assertSafeTree(root) {
  let count=0;
  const visit=(path,depth)=>{
    if(depth>MAX_TREE_DEPTH)throw Error('Fable contract archive tree too deep');
    const stat=lstatSync(path);
    if(stat.isSymbolicLink()||stat.nlink>1&&!stat.isDirectory())
      throw Error('Fable contract archive contains unsafe link');
    if(stat.isDirectory()){
      for(const name of readdirSync(path).sort())visit(join(path,name),depth+1);
    }else if(!stat.isFile())throw Error('Fable contract archive contains special file');
    else if(++count>MAX_TREE_FILES)throw Error('Fable contract archive too large');
  };
  visit(root,0);
  return count;
}
function readConfigSnapshot(root) {
  const saved=new Map();
  for(const rel of STATE_FILES){
    const file=secureLocalPath(root,rel);
    if(existsSync(file)){
      if(!lstatSync(file).isFile())throw Error('Setup destination is not a regular file: '+rel);
      saved.set(rel,readFileSync(file));
    }else saved.set(rel,null);
  }
  return saved;
}
function restoreSnapshot(root,originals) {
  for(const [rel,contents] of originals) {
    const path=secureLocalPath(root,rel);
    if(contents===null)rmSync(path,{force:true});
    else {mkdirSync(dirname(path),{recursive:true});writeFileSync(path,contents);}
  }
}
export function planOtherBackendContractRetirement(root){
  const active=secureLocalPath(root,'assets/contracts');
  const archiveParent=secureLocalPath(root,'.fable/retired-fable-contracts');
  // Always preflight the setup paths before touching any active contract.
  readConfigSnapshot(root);
  if(!existsSync(active))return {required:false,active,archiveParent};
  if(!lstatSync(active).isDirectory())throw Error('Active contract bundle is not a directory');
  assertSafeTree(active);
  const contractFile=join(active,'contract.json');
  if(!existsSync(contractFile))
    throw Error('Existing contract directory lacks Fable identity; refusing to overwrite Other Backend assets');
  let contract;
  try {contract=JSON.parse(readFileSync(contractFile,'utf8'))}
  catch{throw Error('Malformed active contract; cannot safely switch Backend kind')}
  if(contract?.kind!=='fable.client-contract')
    throw Error('Existing external contract cannot be retired as Fable');
  const projectId=contract?.project?.id;
  if(typeof projectId!=='string'||!projectId.trim())
    throw Error('Fable contract project identity missing');
  const hash=createHash('sha256').update(readFileSync(contractFile)).digest('hex').slice(0,16);
  return {required:true,active,archiveParent,
    projectId,contractHashPrefix:hash};
}
export function applyOtherBackendWithArchivedFable(root,writeOtherBackend){
  if(typeof writeOtherBackend!=='function')throw Error('Other Backend commit callback required');
  const plan=planOtherBackendContractRetirement(root);
  const originals=readConfigSnapshot(root);
  let archive=null,renamed=false;
  try {
    if(plan.required){
      // Unique archive name ensures repeated switches cannot overwrite backups.
      archive=secureLocalPath(root,'.fable/retired-fable-contracts/'+
        plan.contractHashPrefix+'-'+randomUUID());
      mkdirSync(archive,{recursive:true});
      renameSync(plan.active,join(archive,'contracts'));
      renamed=true;
      // Store previous configuration beside retired contracts for recovery.
      for(const [rel,contents] of originals){
        if(contents===null)continue;
        const path=join(archive,'prior-setup',rel);
        mkdirSync(dirname(path),{recursive:true});
        writeFileSync(path,contents);
      }
    }
    const result=writeOtherBackend();
    return {...result,retiredFableContracts:archive?
      relative(resolve(root),archive).replaceAll('\\','/'):null};
  }catch(error){
    // Restore only paths this operation owns. Never overwrite a user-supplied
    // active replacement: a concurrent replacement needs manual review.
    try {
      restoreSnapshot(root,originals);
      if(renamed){
        if(existsSync(plan.active))
          throw Error('Active contracts were replaced during rollback; retained archived Fable source for manual recovery: '+archive);
        renameSync(join(archive,'contracts'),plan.active);
      }
      if(archive && existsSync(archive))rmSync(archive,{recursive:true,force:true});
    }catch(rollbackError){
      throw new AggregateError([error,rollbackError],
        'Other Backend switch failed and rollback needs manual intervention');
    }
    throw error;
  }
}

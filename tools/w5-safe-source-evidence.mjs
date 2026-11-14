/**
 * RC213 — inspect source evidence without following file/directory links,
 * hard links or special files outside the project. Never use a file name
 * alone as proof of implemented feature binding.
 */
import {constants,closeSync,existsSync,fstatSync,lstatSync,openSync,readFileSync} from 'node:fs';
import {relative,resolve,sep} from 'node:path';

const DEFAULT_MAX_BYTES=8*1024*1024;
const SAFE_REL=/^[a-zA-Z0-9_.\/-]+$/;
function sourcePath(root,relativeName) {
  if(typeof relativeName!=='string'||relativeName.length>512||
      !relativeName||!SAFE_REL.test(relativeName)||
      relativeName.startsWith('/')||relativeName.includes('\\')||
      relativeName.split('/').some(s=>s==='.'||s==='..'||!s))
    throw Error('W5_INVALID_EVIDENCE_PATH');
  const base=resolve(root);
  if(lstatSync(base).isSymbolicLink()||!lstatSync(base).isDirectory())
    throw Error('W5_UNSAFE_PROJECT_ROOT');
  const resolved=resolve(base,relativeName);
  const rel=relative(base,resolved);
  if(!rel||rel==='..'||rel.startsWith('..'+sep))
    throw Error('W5_EVIDENCE_PATH_ESCAPE');
  let current=base;
  for(const part of relativeName.split('/')){
    current=resolve(current,part);
    const entry=lstatSync(current);
    if(entry.isSymbolicLink())
      throw Error('W5_EVIDENCE_SYMLINK');
    if(!entry.isFile()&&!entry.isDirectory())
      throw Error('W5_EVIDENCE_SPECIAL_FILE');
  }
  return resolved;
}
export function readSafeFeatureEvidence(root,path,{maxBytes=DEFAULT_MAX_BYTES}={}) {
  if(!Number.isSafeInteger(maxBytes)||maxBytes<1||maxBytes>DEFAULT_MAX_BYTES)
    throw Error('W5_INVALID_EVIDENCE_SIZE_LIMIT');
  const target=sourcePath(root,path);
  const stat=lstatSync(target);
  if(!stat.isFile())throw Error('W5_EVIDENCE_NOT_FILE');
  if(stat.nlink>1)throw Error('W5_EVIDENCE_HARDLINK');
  if(stat.size>maxBytes)throw Error('W5_EVIDENCE_TOO_LARGE');
  const flags=constants.O_RDONLY|
    (constants.O_NOFOLLOW??0)|(constants.O_NONBLOCK??0);
  const fd=openSync(target,flags);
  try{
    const opened=fstatSync(fd);
    if(!opened.isFile()||opened.nlink>1||opened.size>maxBytes)
      throw Error('W5_EVIDENCE_UNSAFE_OPENED_FILE');
    return readFileSync(fd,'utf8');
  }finally{closeSync(fd);}
}
export function hasSafeFeatureEvidence(root,path) {
  try {readSafeFeatureEvidence(root,path);return true;}
  catch{return false;}
}

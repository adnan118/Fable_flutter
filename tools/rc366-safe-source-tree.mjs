/**
 * RC366 — shared W4/W5 filesystem boundary for source-only feature generators.
 * A recovery operation may remove only a COMPLETE and UNMODIFIED package.
 * Missing/dangling symlinks are not treated as available destinations.
 */
import {lstatSync,readdirSync,readFileSync} from 'node:fs';
import {resolve,relative,join,sep} from 'node:path';

export function pathEntryExists(path){
  try{lstatSync(path);return true;}
  catch(error){if(error?.code==='ENOENT')return false;throw error;}
}

/** Validate every path component, never just the leaf. */
export function assertRegularProjectPath(root,target,kind='file'){
  if(kind!=='file'&&kind!=='dir')throw Error('Invalid project path kind');
  const base=resolve(root),absolute=resolve(target);
  const rel=relative(base,absolute);
  if(rel==='..'||rel.startsWith('..'+sep)||rel.startsWith(sep))
    throw Error('Source path escapes project root');
  const parts=rel?rel.split(sep):[];
  let current=base;
  for(let i=0;i<=parts.length;i++){
    if(i)current=join(current,parts[i-1]);
    const stat=lstatSync(current);
    if(stat.isSymbolicLink())
      throw Error('Symlink inside project source path: '+relative(base,current));
    if(i<parts.length||kind==='dir'){
      if(!stat.isDirectory())
        throw Error('Non-directory ancestor in project source path');
    }else if(!stat.isFile()){
      throw Error('Non-regular file in project source path');
    }
  }
  return absolute;
}

/** This comparison is intentionally strict and read-only.
 * A concurrent extra file, nested symlink, or changed byte preserves the
 * entire package for manual recovery rather than risking data loss. */
export function generatedTreeExactlyMatches(destination,files,prefix){
  if(typeof prefix!=='string'||!prefix.endsWith('/'))return false;
  const expected=new Map();
  for(const [name,content] of files){
    if(typeof name!=='string'||!name.startsWith(prefix)||
       typeof content!=='string')return false;
    const rest=name.slice(prefix.length);
    if(!rest||rest.split('/').some(x=>!x||x==='.'||x==='..'||x.includes('\\'))||
       expected.has(rest))return false;
    expected.set(rest,content);
  }
  if(expected.size===0)return false;
  let seen=0;
  function walk(directory,sub=''){
    const stat=lstatSync(directory);
    if(stat.isSymbolicLink()||!stat.isDirectory())return false;
    for(const entry of readdirSync(directory,{withFileTypes:true})){
      const name=sub?sub+'/'+entry.name:entry.name;
      const absolute=join(directory,entry.name);
      if(entry.isDirectory()){
        if(!walk(absolute,name))return false;
      }else if(entry.isFile()){
        if(!expected.has(name)||readFileSync(absolute,'utf8')!==expected.get(name))
          return false;
        seen++;
      }else return false;
    }
    return true;
  }
  try{return walk(destination)&&seen===expected.size;}
  catch{return false;}
}

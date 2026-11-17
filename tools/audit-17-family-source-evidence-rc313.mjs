#!/usr/bin/env node
/**
 * RC313 W6 — read-only, fail-closed source inventory of all 17 built-in Flutter
 * feature families. Exact on-disk evidence and app wiring, NOT functional E2E.
 */
import {readFileSync,existsSync,lstatSync} from 'node:fs';
import {resolve,join,relative,sep} from 'node:path';
import {createHash} from 'node:crypto';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {FEATURE_IDS,FEATURE_OWNERSHIP} from './frontend-feature-ownership.mjs';

const ROOT=resolve(fileURLToPath(new URL('../',import.meta.url)));
const LEDGER='docs/integrations/FABLE-FLUTTER-PARITY-MASTER.json';
const HASH=s=>createHash('sha256').update(s).digest('hex');
const FAIL=message=>{throw Error('RC313 W6 family source check refused: '+message);};
const NO_ACCEPTANCE='NOT_EXHAUSTIVELY_VERIFIED_FOR_REAL_PROJECT';
const SOURCE=new Set(['source_and_selected_ui','repository_and_selected_ui','repository_only','client_source']);
const EXTERNAL=new Set(['mapped_partial','not_proven','client_only']);

function safePath(root,name){
  if(typeof name!=='string'||name.length>256||!name||
     name.includes('\\')||name.includes('\0')||
     name.startsWith('/')||name.split('/').some(x=>x===''||x==='.'||x==='..'))
    FAIL('unsafe source path: '+String(name).slice(0,100));
  const target=resolve(root,...name.split('/'));
  if(target===root||!target.startsWith(root+sep))FAIL('source escaped root: '+name);
  let part=root;
  if(!existsSync(part)||lstatSync(part).isSymbolicLink()||!lstatSync(part).isDirectory())
    FAIL('root is missing or a symlink');
  const segments=name.split('/');
  for(let i=0;i<segments.length;i++){
    part=join(part,segments[i]);
    if(!existsSync(part))FAIL('source evidence missing: '+name);
    const st=lstatSync(part);
    if(st.isSymbolicLink())FAIL('symlinked source evidence: '+name);
    if(i<segments.length-1&&!st.isDirectory())FAIL('non-directory source ancestor: '+name);
    if(i===segments.length-1&&!st.isFile())FAIL('source evidence is not a regular file: '+name);
  }
  return target;
}
function sourceFile(root,name){
  return readFileSync(safePath(root,name));
}
function occurrences(text,exact){
  return text.split(exact).length-1;
}
function exactLine(text,line){
  return text.split(/\r?\n/).filter(x=>x===line).length;
}
export function inspectBuiltInFamilyBinding(pubspec,registry,packagePubspec,id){
  if(!/^[a-z][a-z0-9_]*$/.test(id))FAIL('unsafe family ID');
  const packageName='fable_'+id;
  const varName=id.replace(/_([a-z])/g,(_,c)=>c.toUpperCase())+'Feature';
  const dep='  '+packageName+':\n    path: packages/features/'+packageName+'\n';
  const imported="import 'package:"+packageName+'/'+packageName+".dart';";
  const entry='  '+varName+',';
  const errors=[];
  if(occurrences(pubspec,dep)!==1||exactLine(pubspec,'  '+packageName+':')!==1)
    errors.push('app pubspec dependency is missing/duplicated');
  if(exactLine(registry,imported)!==1)errors.push('app feature import is missing/duplicated');
  const start='const List<FableFeature> installedFeatures = <FableFeature>[\n';
  if(occurrences(registry,start)!==1)errors.push('app feature registry declaration is ambiguous');
  else{
    const after=registry.split(start)[1];
    const close=after.match(/^\];\s*$/m);
    if(!close||exactLine(after.slice(0,close.index),entry)!==1)
      errors.push('app feature registry entry is missing/duplicated');
  }
  if(exactLine(packagePubspec,'name: '+packageName)!==1)
    errors.push('feature package pubspec name differs from canonical identity');
  return errors;
}
export function auditAllBuiltInFamilySources(root=ROOT){
  root=resolve(root);
  // Validate checked-in evidence, not an external server's unsafely named paths.
  const ledgerSource=sourceFile(root,LEDGER);
  const ledger=JSON.parse(ledgerSource.toString('utf8'));
  if(ledger.schemaVersion!==1||ledger.kind!=='fable.flutter-feature-parity-master'||
     ledger.featureCount!==17||!Array.isArray(ledger.features)||ledger.features.length!==17)
    FAIL('canonical parity ledger does not declare exactly 17 families');
  if(FEATURE_IDS.length!==17||new Set(FEATURE_IDS).size!==17)
    FAIL('Flutter source ownership registry does not declare 17 unique families');
  const ids=ledger.features.map(x=>x?.id);
  if(new Set(ids).size!==17||FEATURE_IDS.some(id=>!ids.includes(id))||
     ids.some(id=>!FEATURE_IDS.includes(id)))
    FAIL('parity ledger and Flutter family registry differ');
  const pubspec=sourceFile(root,'pubspec.yaml').toString('utf8');
  const registry=sourceFile(root,'lib/src/generated/feature_registry.dart').toString('utf8');
  if(exactLine(pubspec,'dependencies:')!==1)FAIL('host dependency list is ambiguous');
  if(occurrences(registry,'const List<FableFeature> installedFeatures = <FableFeature>[\n')!==1)
    FAIL('typed installed feature registry is ambiguous');
  const report=[];
  let totalEvidenceFiles=0;
  for(const id of FEATURE_IDS){
    const family=ledger.features.find(x=>x.id===id);
    if(family.ownership!==FEATURE_OWNERSHIP[id]||
       !SOURCE.has(family.sourceStatus)||!EXTERNAL.has(family.externalStatus))
      FAIL(id+': family ownership or status drift');
    if(family.liveE2EVerified!==false||family.complete!==false||
       family.operationCoverage!==NO_ACCEPTANCE)
      FAIL(id+': unsupported live E2E / completeness claim in source-only ledger');
    if(!Array.isArray(family.gaps)||family.gaps.length===0||
       !family.gaps.every(x=>typeof x==='string'&&x.trim()))
      FAIL(id+': missing known gap disclosures');
    if(!Array.isArray(family.frontendEvidence)||family.frontendEvidence.length<1||
       family.frontendEvidence.length>60||
       new Set(family.frontendEvidence).size!==family.frontendEvidence.length)
      FAIL(id+': missing, duplicated or overly large evidence inventory');
    const packagePubspec=sourceFile(root,'packages/features/fable_'+id+'/pubspec.yaml').toString('utf8');
    const wiring=inspectBuiltInFamilyBinding(pubspec,registry,packagePubspec,id);
    if(wiring.length)FAIL(id+': '+wiring.join('; '));
    const receipts=[];
    for(const path of family.frontendEvidence){
      if(!path.endsWith('.dart')||
         !(path.startsWith('packages/')||path.startsWith('lib/')))
        FAIL(id+': non-Dart or non-source evidence path: '+path);
      const bytes=sourceFile(root,path);
      if(bytes.length===0)FAIL(id+': empty evidence file: '+path);
      receipts.push({path,sha256:HASH(bytes),bytes:bytes.length});
      totalEvidenceFiles++;
    }
    receipts.sort((a,b)=>a.path.localeCompare(b.path,'en'));
    const fingerprint=HASH(receipts.map(x=>x.path+'\0'+x.sha256+'\n').join(''));
    report.push({
      id,ownership:family.ownership,sourceStatus:family.sourceStatus,
      evidenceFiles:receipts.length,evidenceSha256:fingerprint,
      evidence:receipts,
      backendCapabilityCount:family.backendCapabilities?.length??0,
      documentedGaps:family.gaps.length,
      appWiring:'CANONICAL_SOURCE_PRESENT',
      liveE2EVerified:false,complete:false,
    });
  }
  return {
    schemaVersion:1,kind:'fable.flutter-17-family-source-evidence',
    sourceLedger:LEDGER,ledgerSha256:HASH(ledgerSource),
    pubspecSha256:HASH(pubspec),featureRegistrySha256:HASH(registry),
    featureCount:17,evidenceFileReferences:totalEvidenceFiles,
    sourceWiredFamilies:report.length,
    acceptedLiveFamilies:0,acceptedCompleteFamilies:0,
    families:report,sourceOnly:true,
    testsExecuted:false,nativeBuildExecuted:false,
    liveE2EVerified:false,productionReady:false,
    note:'File bytes, declared feature ownership and app wiring only; neither an actual generated project nor native runtime was tested.',
  };
}
function cli(argv){
  let root=ROOT;
  const seen=new Set();
  for(let i=0;i<argv.length;i++){
    let arg=argv[i];
    if(arg==='--')continue;
    if(arg==='--help'||arg==='-h')return {help:true};
    if(seen.has(arg))FAIL('repeated argument: '+arg);
    seen.add(arg);
    if(arg==='--root'&&argv[i+1]&&!argv[i+1].startsWith('--')){
      root=argv[++i];continue;
    }
    FAIL('unsupported or incomplete argument: '+arg);
  }
  return {root};
}
if(process.argv[1]&&import.meta.url===pathToFileURL(resolve(process.argv[1])).href){
  try{
    const options=cli(process.argv.slice(2));
    if(options.help)console.log('pnpm run fable:families:source -- [--root FLUTTER_CHECKOUT]');
    else console.log(JSON.stringify(auditAllBuiltInFamilySources(options.root),null,2));
  }catch(error){console.error(error.message);process.exitCode=2;}
}

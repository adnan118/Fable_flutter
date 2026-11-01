#!/usr/bin/env node
// RC86: verify Fable-Backend source identity and Flutter Auth source ledger.
// This verifies imported source declarations, NOT live E2E acceptance.
import {createHash} from 'node:crypto';
import {existsSync,readFileSync,readdirSync} from 'node:fs';
import {resolve,join} from 'node:path';
import {execFileSync} from 'node:child_process';
import {pathToFileURL} from 'node:url';

const pairPath='docs/integrations/FABLE-CROSS-REPO-SOURCE-PAIR-RC86.json';
const assert=(ok,message)=>{if(!ok)throw Error('SOURCE_PAIR_RC86: '+message);};
const json=(path)=>JSON.parse(readFileSync(path,'utf8'));
const hex40=(value)=>typeof value==='string'&&/^[0-9a-f]{40}$/.test(value);
function gitHead(root){
  return execFileSync('git',['rev-parse','HEAD'],{cwd:root,encoding:'utf8'}).trim();
}
function blobHash(buffer){
  return createHash('sha1').update(Buffer.from('blob '+buffer.length+'\0')).update(buffer).digest('hex');
}
export function verifySourcePair({frontendRoot=process.cwd(),backendRoot=null}={}){
  const front=resolve(frontendRoot);
  const pair=json(join(front,pairPath));
  assert(pair.schemaVersion===1&&pair.kind==='fable.cross-repo-source-pair',
    'missing or invalid cross-repository source pairing');
  assert(pair.revision==='RC86','unexpected source pairing revision');
  assert(pair.backend.repository==='adnan118/Fable'&&pair.frontend.repository==='adnan118/Fable_flutter',
    'unexpected remote repositories');
  assert(pair.backend.visibility==='private'&&pair.frontend.visibility==='public',
    'packaging must run privately on Backend, not publicly in Flutter');
  assert(hex40(pair.backend.sourceCommitAtAudit)&&hex40(pair.frontend.sourceCommitAtAudit),
    'invalid source commit identity');
  assert(hex40(pair.backend.authBlueprintBlobSha),'invalid pinned Backend manifest Git blob');
  const auth=json(join(front,pair.frontend.authLedger));
  const master=json(join(front,pair.frontend.masterLedger));
  assert(auth.backendShaAtAudit===pair.backend.sourceCommitAtAudit,
    'Auth ledger is pinned to another Backend commit');
  assert(master.backendMainAtAudit===pair.backend.sourceCommitAtAudit,
    'master feature ledger is pinned to another Backend commit');
  assert(auth.operationCount===pair.counts.authBackendOperations &&
    auth.operations?.length===auth.operationCount,
    'Auth ledger operation count mismatch');
  const counts={sourceReviewed:auth.operations.filter(x=>x.disposition==='SOURCE_IMPLEMENTED_E2E_PENDING').length,
    undecided:auth.operations.filter(x=>x.disposition==='NOT_DECIDED').length};
  assert(counts.sourceReviewed===pair.counts.authSourceReviewed &&
    counts.undecided===pair.counts.authUndecided &&
    counts.sourceReviewed+counts.undecided===auth.operationCount,
    'Auth source disposition drift');
  assert(master.features?.length===pair.counts.featureFamilies,
    '17-feature inventory drift');
  assert(pair.counts.liveE2EAccepted===0 &&
    master.features.every(f=>f.liveE2EVerified!==true),
    'live E2E acceptance must not be inferred from source sync');
  assert(auth.operations.every(x=>x.realE2EVerified===false &&
    x.externalBackendMapped===false && x.wizardDecisionReviewed===false),
    'Fable/Other Backend/Wizard gates incorrectly marked verified');
  const report={
    schemaVersion:1,kind:'fable.cross-repo-source-pair-audit',
    revision:pair.revision,
    frontendGitHead:existsSync(join(front,'.git'))?gitHead(front):null,
    backendGitHead:null,authSourceBlobVerified:false,
    backendRouteCount:null,backendCapabilityCount:null,
    backendCapabilityInventory:[],backendRoutesAbsent:[],backendRouteMismatches:[],
    sourceReviewed:counts.sourceReviewed,notDecided:counts.undecided,
    featureFamilies:master.features.length,liveE2EAccepted:0,
    otherBackendMfaApproved:false,projectGeneratedLiveTested:false,
    sourceOnly:backendRoot==null,
  };
  if(backendRoot!=null){
    const back=resolve(backendRoot);
    const authFile=join(back,pair.backend.authBlueprint);
    assert(existsSync(authFile),'private Backend auth source manifest missing');
    const buffer=readFileSync(authFile);
    const actualBlob=blobHash(buffer);
    assert(actualBlob===pair.backend.authBlueprintBlobSha,
      'Backend auth source changed since Flutter audit; re-audit before packaging');
    const backendAuth=JSON.parse(buffer.toString('utf8'));
    assert(backendAuth.name==='auth'&&backendAuth.version===pair.backend.authCapabilityVersion,
      'Backend Auth capability changed');
    const catalog=new Map();
    for(const route of backendAuth.routes??[]){
      assert(typeof route.id==='string'&&!catalog.has(route.id),'duplicate Backend auth operation');
      catalog.set(route.id,route);
    }
    assert(catalog.size===auth.operationCount,'Backend Auth total differs from Flutter');
    for(const op of auth.operations){
      const actual=catalog.get(op.id);
      if(!actual){report.backendRoutesAbsent.push(op.id);continue;}
      if(actual.method!==op.method||actual.path!==op.path){
        report.backendRouteMismatches.push({id:op.id,expected:{method:op.method,path:op.path},
          actual:{method:actual.method,path:actual.path}});
      }
    }
    assert(report.backendRoutesAbsent.length===0&&report.backendRouteMismatches.length===0,
      'Backend/Flutter Auth operations differ');
    const backendHead=gitHead(back);
    report.backendGitHead=backendHead;
    report.backendRouteCount=catalog.size;
    report.authSourceBlobVerified=true;
    // This never claims feature parity. Inventory is provided for manual review.
    const capabilities=join(back,'Fable-Backend-RC66/blueprints/capabilities');
    const rows=readdirSync(capabilities,{withFileTypes:true})
      .filter(x=>x.isDirectory()).map(x=>x.name).sort();
    report.backendCapabilityCount=rows.length;
    report.backendCapabilityInventory=rows.map(name=>{
      const manifestFile=join(capabilities,name,'manifest.json');
      if(!existsSync(manifestFile))return{name,manifestPresent:false,operations:null};
      const capability=json(manifestFile);
      assert(capability.name===name && Array.isArray(capability.routes),
        'invalid Backend capability blueprint: '+name);
      const ids=capability.routes.map(o=>o.id);
      assert(ids.every(x=>typeof x==='string') &&
        ids.length===new Set(ids).size,'duplicate Backend operations in '+name);
      return{name,manifestPresent:true,version:capability.version??null,
        operations:ids.length,routeIds:ids,liveE2EVerified:false};
    });
    report.sourceOnly=false;
  }
  return report;
}
if(process.argv[1]&&import.meta.url===pathToFileURL(resolve(process.argv[1])).href){
  const idx=process.argv.indexOf('--backend-root');
  const backendRoot=idx>=0?process.argv[idx+1]:null;
  if(idx>=0&&!backendRoot)throw Error('--backend-root requires a directory');
  const report=verifySourcePair({backendRoot});
  console.log(JSON.stringify(report,null,2));
}

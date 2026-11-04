#!/usr/bin/env node
/**
 * RC116 — generate strictly typed Fable read feature packages from a REAL,
 * independently pinned Backend export. No other-backend auto-inference.
 *
 * Preview never writes. Apply stages all files in a sibling folder, verifies
 * source-layer dependency direction, and refuses to overwrite any package.
 */
import {
  existsSync,readFileSync,mkdirSync,mkdtempSync,writeFileSync,
  renameSync,rmSync,lstatSync,
} from 'node:fs';
import {resolve,join,relative,dirname,sep} from 'node:path';
import {pathToFileURL} from 'node:url';
import {verifyFableContract} from './verify-fable-contract.mjs';
import {planTypedFeature} from './plan-typed-feature-rc116.mjs';
import {renderTypedFeature} from './render-typed-feature-rc116.mjs';
import {checkLayerSource} from './enforce-feature-architecture-rc115.mjs';

const HASH=/^[a-f0-9]{64}$/;
const ID=/^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$/;
const read=(root,name)=>JSON.parse(readFileSync(join(root,name),'utf8'));
function checkSourceDir(path){
  if(!existsSync(path)||lstatSync(path).isSymbolicLink()||
     !lstatSync(path).isDirectory()){
    throw Error('RC116 requires non-symlink target project source directory');
  }
}
function selectedProjectFeatures(root){
  const path=join(root,'.fable/project-features.json');
  if(!existsSync(path))throw Error('Explicit custom feature selection manifest missing');
  const value=read(root,'.fable/project-features.json');
  if(!Array.isArray(value.features)||value.schemaVersion!==1){
    throw Error('Invalid custom feature selection');
  }
  return value.features.map(x=>typeof x==='string'?x:x?.id);
}
function testSourceBoundaries(root,featureId,files){
  const base='packages/features/fable_'+featureId+'/';
  for(const [name,source] of files){
    const within=name.slice(base.length);
    const layer=within.match(/^lib\/src\/(domain|application|data|presentation)\//)?.[1];
    if(!layer)continue;
    const issues=checkLayerSource({featureId,layer,source,file:join(root,name)});
    if(issues.length){
      throw Error('Generated source violates RC115 architecture gate: '+
        name+' '+issues.join('; '));
    }
  }
}
export function planPinnedTypedFeature(root,{
  featureId,expectedProjectId,expectedContractHash,
}={}){
  root=resolve(root);
  if(typeof featureId!=='string'||!ID.test(featureId)||featureId.length>64)
    throw Error('Unsafe RC116 project feature ID');
  if(typeof expectedProjectId!=='string'||!expectedProjectId.trim()||
     !HASH.test(expectedContractHash))
    throw Error('Independent project ID + Backend contract SHA-256 are mandatory');
  const backend=read(root,'assets/config/backend.json');
  if(backend?.backend?.kind!=='fable'||backend.backend.adapter!=='fable-contract'||
     backend.backend.status!=='ready'||backend.contractImported!==true){
    throw Error('RC116 generator is Fable-only; external backend requires its OWN verified codegen');
  }
  const setup=read(root,'.fable/frontend-setup.json');
  if(setup?.kind!=='fable.flutter-frontend-setup'||setup.source!=='backend-contract-export'||
     setup.mode!=='import'||setup.projectBound!==true||setup.backendAuthority!==true||
     setup.projectId!==expectedProjectId||setup.contractHash!==expectedContractHash){
    throw Error('Explicitly imported Fable setup is missing/stale or not project-bound');
  }
  const verification=verifyFableContract(root,{
    mode:'project',expectedProjectId,expectedContractHash,
  });
  if(!verification.ok||!verification.projectBound||verification.fixture){
    throw Error('Fable project export not independently verified: '+
      (verification.failures??[]).join(','));
  }
  const contract=read(root,'assets/contracts/contract.json');
  const openapi=read(root,'assets/contracts/openapi.json');
  const requirements=read(root,'.fable/feature-integration-requirements.json');
  const selected=selectedProjectFeatures(root);
  const plan=planTypedFeature({
    featureId,contract,openapi,requirements,selectedFeatures:selected,
  });
  if(plan.projectId!==expectedProjectId||plan.contractHash!==expectedContractHash){
    throw Error('Contract changed between verification and typed feature planning');
  }
  const folder=join(root,'packages/features/fable_'+featureId);
  if(existsSync(folder))throw Error('Refusing to overwrite an existing feature package: '+featureId);
  const files=renderTypedFeature(plan);
  testSourceBoundaries(root,featureId,files);
  return {plan,files};
}
export function generatePinnedTypedFeature(root,options={}){
  root=resolve(root);
  const {plan,files}=planPinnedTypedFeature(root,options);
  const destination=join(root,'packages/features/fable_'+plan.featureId);
  if(options.apply===true){
    const parent=join(root,'packages/features');
    checkSourceDir(root);checkSourceDir(join(root,'packages'));
    checkSourceDir(parent);
    if(existsSync(destination)){
      throw Error('RC116 concurrent feature creation: no overwrite permitted');
    }
    const stage=mkdtempSync(join(parent,'.rc116-'+plan.featureId+'-'));
    const prefix='packages/features/fable_'+plan.featureId+'/';
    try{
      for(const [path,source] of files){
        if(!path.startsWith(prefix))throw Error('RC116 output escaped target package');
        const relativePath=path.slice(prefix.length);
        if(!relativePath||relativePath.split('/').some(x=>!x||x==='..'||x==='.')){
          throw Error('RC116 path traversal rejected');
        }
        const full=join(stage,...relativePath.split('/'));
        mkdirSync(dirname(full),{recursive:true});
        writeFileSync(full,source,{encoding:'utf8',flag:'wx'});
      }
      if(existsSync(destination))throw Error('RC116 package appeared while staging');
      renameSync(stage,destination);
    }finally{
      if(existsSync(stage))rmSync(stage,{recursive:true,force:true});
    }
  }
  return {
    feature:plan.featureId,projectId:plan.projectId,
    contractHash:plan.contractHash,
    operations:plan.operations.map(op=>op.operationId),
    files:files.size,applied:options.apply===true,
    destination:'packages/features/fable_'+plan.featureId,
    integrationStatus:'typed-package-generated; project DI/routes/pubspec review required',
    liveE2EVerified:false,
  };
}
function cli(args){
  const o={root:process.cwd(),apply:false};
  for(let i=0;i<args.length;i++){
    const flag=args[i];
    if(flag==='--apply'){o.apply=true;continue;}
    const keys={
      '--root':'root','--feature':'featureId',
      '--expected-project-id':'expectedProjectId',
      '--expected-contract-hash':'expectedContractHash',
    };
    if(!Object.hasOwn(keys,flag)||!args[i+1]||args[i+1].startsWith('--')){
      throw Error('RC116 unknown/missing flag '+flag);
    }
    o[keys[flag]]=args[++i];
  }
  return generatePinnedTypedFeature(o.root,o);
}
if(process.argv[1]&&import.meta.url===pathToFileURL(resolve(process.argv[1])).href){
  try{
    console.log(JSON.stringify(cli(process.argv.slice(2)),null,2));
  }catch(e){
    console.error(String(e?.message??e));
    process.exitCode=2;
  }
}

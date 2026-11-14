#!/usr/bin/env node
/** RC213 W5 operation-level source trace gate — no runtime or production GO. */
import {resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import {auditW5FeatureFlows} from './w5-feature-flow-audit.mjs';

export function parseW5Args(argv) {
  const args={root:process.cwd(),expectedProjectId:null,
    expectedContractHash:null,json:false};
  const used=new Set();
  for(let i=0;i<argv.length;i++){
    const flag=argv[i];
    if(used.has(flag))throw Error('Duplicate W5 flag: '+flag);
    used.add(flag);
    if(flag==='--json'){args.json=true;continue;}
    if(!['--root','--expected-project-id','--expected-contract-hash'].includes(flag) ||
       !argv[i+1] || argv[i+1].startsWith('--'))
      throw Error('Unsupported/incomplete W5 option: '+flag);
    const value=argv[++i];
    if(flag==='--root')args.root=resolve(value);
    if(flag==='--expected-project-id')args.expectedProjectId=value;
    if(flag==='--expected-contract-hash')args.expectedContractHash=value;
  }
  if(Boolean(args.expectedProjectId)!==Boolean(args.expectedContractHash))
    throw Error('Both independent Fable project ID and SHA-256 are required');
  if(args.expectedContractHash&&!/^[a-f0-9]{64}$/.test(args.expectedContractHash))
    throw Error('Expected Fable contract SHA-256 must be 64 lowercase hex chars');
  return args;
}
function main(argv) {
  const args=parseW5Args(argv);
  const report=auditW5FeatureFlows(args.root,{
    expectedProjectId:args.expectedProjectId,
    expectedContractHash:args.expectedContractHash,
  });
  if(args.json)process.stdout.write(JSON.stringify(report,null,2)+'\n');
  else{
    process.stdout.write('Fable W5 source trace: '+
      (report.sourceTracePassed?'SOURCE PASS':'BLOCKED')+'\n');
    process.stdout.write('Selected '+report.counts.selected+
      ', traced '+report.counts.sourceMapped+', blocked '+report.counts.blocked+'\n');
    for(const item of report.features.filter(x=>x.status==='BLOCKED'))
      process.stdout.write(item.id+': '+item.issues.join(',')+'\n');
    process.stdout.write('Native Flutter, live E2E and production: UNVERIFIED\n');
  }
  if(!report.sourceTracePassed)process.exitCode=2;
}
if(process.argv[1]&&import.meta.url===pathToFileURL(resolve(process.argv[1])).href)
  try{main(process.argv.slice(2));}
  catch(error){process.stderr.write('W5 REFUSED: '+error.message+'\n');process.exitCode=2;}

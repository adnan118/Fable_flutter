#!/usr/bin/env node
/** RC212 W4 source matrix: never invent missing Backend exports or E2E proof. */
import {resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import {runW4WizardMatrix,w4ScenarioPlan,W4_PROFILES} from './w4-wizard-matrix.mjs';

const FLAGS=new Set(['--plan','--json','--materialize','--keep']);
const VALUES=new Set(['--workspace','--flutter-source',...W4_PROFILES.flatMap(p=>[
  '--fable-'+p+'-export','--fable-'+p+'-project-id','--fable-'+p+'-contract-hash',
])]);
export function parseW4MatrixArgs(argv) {
  const values={}, flags=new Set();
  for(let i=0;i<argv.length;i++){
    const key=argv[i];
    if(FLAGS.has(key)){
      if(flags.has(key))throw Error('Duplicate W4 flag: '+key);
      flags.add(key);
    }else if(VALUES.has(key)){
      if(key in values || !argv[i+1] || argv[i+1].startsWith('--'))
        throw Error('Duplicate or missing W4 option: '+key);
      values[key]=argv[++i];
    }else throw Error('Unsupported W4 matrix option: '+key);
  }
  const fableExports={};
  for(const p of W4_PROFILES){
    const fields=['--fable-'+p+'-export','--fable-'+p+'-project-id',
      '--fable-'+p+'-contract-hash'];
    if(fields.some(k=>k in values)){
      if(!fields.every(k=>k in values))throw Error('W4 Fable '+p+' requires export, project ID and independent contract hash');
      if(!/^[a-f0-9]{64}$/.test(values[fields[2]]))
        throw Error('Invalid Fable '+p+' contract SHA-256');
      fableExports[p]={
        source:resolve(values[fields[0]]),
        expectedProjectId:values[fields[1]],
        expectedContractHash:values[fields[2]],
      };
    }
  }
  return {planOnly:flags.has('--plan'),json:flags.has('--json'),
    fableExports,workspaceRoot:values['--workspace']?
      resolve(values['--workspace']):null,
    flutterSourceRoot:values['--flutter-source']?
      resolve(values['--flutter-source']):undefined,
    materializeFlutterSource:flags.has('--materialize'),
    keepWorkspace:flags.has('--keep')};
}
async function main(argv){
  const options=parseW4MatrixArgs(argv);
  if(options.planOnly){
    process.stdout.write(JSON.stringify({batch:'RC212-W4',scenarios:w4ScenarioPlan(),
      requiredIndependentFableExports:W4_PROFILES,
      noDefaultProductionApproval:true},null,2)+'\n');
    return;
  }
  // Legacy Wizard integration-gap diagnostics log while applying. For a
  // machine-readable matrix report, collect only deterministic return data.
  const log=console.log,warn=console.warn;
  if(options.json){console.log=()=>{};console.warn=()=>{};}
  let report;
  try{report=await runW4WizardMatrix(options);}
  finally{console.log=log;console.warn=warn;}
  process.stdout.write(JSON.stringify(report,null,2)+'\n');
  if(!report.passed)process.exitCode=2;
}
if(process.argv[1]&&import.meta.url===pathToFileURL(resolve(process.argv[1])).href)
  main(process.argv.slice(2)).catch(error=>{
    process.stderr.write('RC212 W4 REFUSED: '+error.message+'\n');
    process.exitCode=2;
  });

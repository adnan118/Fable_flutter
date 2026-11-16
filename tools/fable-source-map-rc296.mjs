#!/usr/bin/env node
/**
 * RC296: one W0–W8 source-only summary. Reads the authoritative parity ledger;
 * it NEVER executes Flutter, tests, deployments or production checks.
 */
import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {resolve,join} from 'node:path';

const root=resolve(fileURLToPath(new URL('..',import.meta.url)));
const ledgerPath=join(root,'docs/integrations/FABLE-FLUTTER-PARITY-MASTER.json');
function main(){
  const opts=process.argv.slice(2);
  if(opts.some(x=>!['--json','--help'].includes(x)))
    throw Error('Unknown flag; allowed --json or --help');
  if(opts.includes('--help')){
    console.log('Usage: pnpm run fable:source-map [-- --json] (read-only, no tests)');
    return;
  }
  const report=JSON.parse(readFileSync(ledgerPath,'utf8'));
  if(report.kind==null||report.featureCount!==17||
      !Array.isArray(report.features)||report.features.length!==17||
      !report.w5TypedListMilestone)
    throw Error('Authoritative parity ledger is missing or incompatible');
  const families=report.features;
  const claimedLive=families.filter(f=>f.liveE2EVerified===true).length;
  const claimedComplete=families.filter(f=>f.complete===true).length;
  const milestone=report.w5TypedListMilestone;
  const stages=[
    {id:'W0',task:'Project inventory / choices',status:'FOUNDATION_SOURCE',
      accepted:false},
    {id:'W1',task:'Backend Wizard',status:'SOURCE_IMPLEMENTED',accepted:false},
    {id:'W2',task:'Backend Generator',status:'SOURCE_IMPLEMENTED',accepted:false},
    {id:'W3',task:'Backend + Flutter signed contracts',status:'PARTIAL_INTEGRATION',accepted:false},
    {id:'W4',task:'Flutter Wizard',status:'PARTIAL_INTEGRATION',accepted:false},
    {id:'W5',task:'Operations / navigation / signed CRUD',status:milestone.w5Closed?'SOURCE_CLOSED':'SOURCE_IN_PROGRESS',accepted:false},
    {id:'W6',task:'17 feature families + security',status:milestone.w6Closed?'SOURCE_CLOSED':'LIVE_ACCEPTANCE_PENDING',accepted:false},
    {id:'W7',task:'Real generated project / device E2E',status:milestone.w7Closed?'SOURCE_GATE_CLOSED':'NOT_ACCEPTED',accepted:false},
    {id:'W8',task:'Combined full release delivery',status:milestone.w8Closed?'SOURCE_GATE_CLOSED':'NOT_ACCEPTED',accepted:false},
  ];
  const out={
    schemaVersion:1,kind:'fable.w0-w8-source-only-map',
    source:'docs/integrations/FABLE-FLUTTER-PARITY-MASTER.json',
    latestSourceUpdate:milestone.lastSourceUpdate,
    featureFamilies:families.length,liveVerifiedFamilies:claimedLive,
    completeFamilies:claimedComplete,
    stages,testsExecuted:false,productionReady:false,
    note:'Statuses reflect source documentation only. Backend independent live trial is NOT full generated project E2E.',
    next:'Finish W3/W4 source binding and W5 scopes; user owns W7 testing and W8 acceptance.',
  };
  if(opts.includes('--json'))console.log(JSON.stringify(out,null,2));
  else{
    console.log('FABLE W0–W8 · SOURCE MAP ('+out.latestSourceUpdate+')');
    for(const stage of stages)
      console.log(stage.id.padEnd(3)+' '+stage.status.padEnd(24)+' '+stage.task);
    console.log('Families live-verified: '+claimedLive+'/17, source-complete: '+claimedComplete+'/17');
    console.log('No tests executed · Production NO_GO');
  }
}
try{main()}catch(error){
  console.error('Fable source map refused: '+error.message);
  process.exitCode=2;
}

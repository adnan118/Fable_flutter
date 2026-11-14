#!/usr/bin/env node
/** RC216: run W0-W8 local checks once, retain precise NO-GO evidence. */
import {writeFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {buildLocalAcceptancePlan,runLocalAcceptance} from './w7-w8-local-acceptance.mjs';

const DEFAULT_FLUTTER_ROOT=fileURLToPath(new URL('../',import.meta.url));
const SHA=/^[a-f0-9]{40}$/;
const HASH=/^[a-f0-9]{64}$/;
const PROFILE=['minimal','standard','complex'];
const FIELDS=new Set(['--flutter-root','--backend-root','--generated-flutter-root',
  '--backend-export-root','--expected-backend-sha','--expected-flutter-sha',
  '--project-id','--contract-hash','--output',...PROFILE.flatMap(p=>[
    '--fable-'+p+'-export','--fable-'+p+'-project-id','--fable-'+p+'-contract-hash',
  ])]);
const FLAGS=new Set(['--help','--plan','--with-flutter']);

export function parseLocalCloseoutArgs(args) {
  const values={},flags=new Set();
  for(let i=0;i<args.length;i++){
    const key=args[i];
    if(FLAGS.has(key)){
      if(flags.has(key))throw Error('Duplicate closeout flag: '+key);
      flags.add(key);continue;
    }
    if(!FIELDS.has(key)||Object.hasOwn(values,key)||
      !args[i+1]||args[i+1].startsWith('--'))
      throw Error('Unknown/duplicate/missing closeout option: '+key);
    values[key]=args[++i];
  }
  for(const field of ['--expected-backend-sha','--expected-flutter-sha'])
    if(values[field]&&!SHA.test(values[field]))
      throw Error(field+' must be an independent 40-char Git SHA');
  if(Boolean(values['--project-id'])!==Boolean(values['--contract-hash']))
    throw Error('A project ID and independent contract hash must be provided together');
  if(values['--contract-hash']&&!HASH.test(values['--contract-hash']))
    throw Error('Project contract hash must be lowercase SHA-256');
  const profiles={};
  for(const p of PROFILE){
    const keys=['--fable-'+p+'-export','--fable-'+p+'-project-id',
      '--fable-'+p+'-contract-hash'];
    if(keys.some(k=>values[k])){
      if(!keys.every(k=>values[k])||!HASH.test(values[keys[2]]))
        throw Error('Profile '+p+' requires real export, independent project ID and contract SHA256');
      profiles[p]={source:resolve(values[keys[0]]),
        expectedProjectId:values[keys[1]],
        expectedContractHash:values[keys[2]]};
    }
  }
  return {
    help:flags.has('--help'),planOnly:flags.has('--plan'),
    output:values['--output']?resolve(values['--output']):null,
    options:{
      flutterRoot:resolve(values['--flutter-root']??DEFAULT_FLUTTER_ROOT),
      backendRoot:values['--backend-root']?resolve(values['--backend-root']):null,
      generatedFlutterRoot:values['--generated-flutter-root']?
        resolve(values['--generated-flutter-root']):null,
      backendExportRoot:values['--backend-export-root']?
        resolve(values['--backend-export-root']):null,
      expectedBackendSha:values['--expected-backend-sha']??null,
      expectedFlutterSha:values['--expected-flutter-sha']??null,
      projectId:values['--project-id']??null,
      contractHash:values['--contract-hash']??null,
      fableProfiles:Object.keys(profiles).length?profiles:null,
      withFlutterToolchain:flags.has('--with-flutter'),
    },
  };
}
function main(argv){
  const parsed=parseLocalCloseoutArgs(argv);
  if(parsed.help){
    process.stdout.write([
      'RC216 local Fable W0-W8 source and native evidence collector',
      'Usage: node tools/run-w7-w8-local-acceptance.mjs [--plan] [options]',
      '  --flutter-root PATH',
      '  --backend-root PATH (private Fable repo or Fable-Backend-RC66 subdirectory)',
      '  --expected-backend-sha FULL_40_CHAR_MAIN_SHA',
      '  --expected-flutter-sha FULL_40_CHAR_MAIN_SHA',
      '  --backend-export-root PATH --generated-flutter-root PATH',
      '  --project-id ID --contract-hash SHA256',
      '  --fable-minimal-export PATH --fable-minimal-project-id ID --fable-minimal-contract-hash SHA256',
      '  --fable-standard-export PATH --fable-standard-project-id ID --fable-standard-contract-hash SHA256',
      '  --fable-complex-export PATH --fable-complex-project-id ID --fable-complex-contract-hash SHA256',
      '  --with-flutter (runs Dart test, analyze, flutter test if installed)',
      '  --output REPORT.json',
      'Source/local pass is not Android/iOS, live provider, human signoff or production GO.',
    ].join('\n')+'\n');
    return;
  }
  const plan=buildLocalAcceptancePlan(parsed.options);
  const result=parsed.planOnly?plan:runLocalAcceptance(plan);
  const json=JSON.stringify(result,null,2)+'\n';
  if(parsed.output)writeFileSync(parsed.output,json,{flag:'wx',mode:0o600});
  process.stdout.write(json);
  if(!parsed.planOnly)process.exitCode=2; // Production signoff never auto-issued.
}
if(process.argv[1]&&resolve(process.argv[1])===fileURLToPath(import.meta.url))
  try{main(process.argv.slice(2));}
  catch(error){
    process.stderr.write('RC216 closeout refused: '+error.message+'\n');
    process.exitCode=2;
  }

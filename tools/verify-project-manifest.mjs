#!/usr/bin/env node
/** Read-only verifier; never writes generated files or approves a deployment. */
import {readFileSync,lstatSync} from 'node:fs';
import {resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import {validateProjectGenerationManifest,compareProjectGenerationManifests} from './project-generation-manifest.mjs';

function load(path) {
  const full=resolve(path);
  const stat=lstatSync(full);
  if(!stat.isFile()||stat.size>1024*1024)throw new Error('PROJECT_MANIFEST_FILE_UNSAFE');
  return JSON.parse(readFileSync(full,'utf8'));
}
export function reviewManifestCli(args,print=console.log) {
  if(args.length!==2 && args.length!==4)throw new Error('Usage: --manifest <json> [--compare <json>]');
  if(args[0]!=='--manifest'||(args.length===4&&args[2]!=='--compare'))
    throw new Error('PROJECT_MANIFEST_CLI_OPTIONS_INVALID');
  const main=load(args[1]);
  const validated=validateProjectGenerationManifest(main);
  const comparison=args.length===4?compareProjectGenerationManifests(main,load(args[3])):null;
  const result={kind:'fable.project-generation-review',schemaVersion:1,
    projectId:validated.manifest.project.id,
    backendKind:validated.manifest.backend.kind,
    decisionHash:validated.decisionHash,
    comparison,
    ...validated.trust,
    status:comparison && !comparison.sameDecisions?'DIFFERENT_DECISIONS':'VALIDATED_INPUT_ONLY'};
  print(JSON.stringify(result,null,2));
  return comparison&&!comparison.sameDecisions?2:0;
}
if(process.argv[1]&&import.meta.url===pathToFileURL(resolve(process.argv[1])).href){
  try{process.exitCode=reviewManifestCli(process.argv.slice(2))}
  catch(error){console.error(String(error?.message||error));process.exitCode=1}
}

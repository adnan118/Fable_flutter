#!/usr/bin/env node
/**
 * RC217 — the only command developers need for the available local checks:
 *   pnpm fable:all
 * Retains a report and a strict NO_GO if independent release gates are open.
 */
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {runFableOneCommand} from './fable-one-command.mjs';

const root=fileURLToPath(new URL('../',import.meta.url));
export function runSingleCommand(args=[],options={}){
  if(args.length)throw Error(
    'RC217_ONE_COMMAND_ONLY: run "pnpm fable:all" with no arguments');
  return runFableOneCommand(root,options);
}
if(process.argv[1]&&resolve(process.argv[1])===fileURLToPath(import.meta.url)){
  try{
    const {report}=runSingleCommand(process.argv.slice(2));
    // A failing local test is distinct from source-only / E2E blockers.
    // Never make a release request succeed while production NO_GO persists.
    process.exitCode=report.counts.failed>0?1:2;
  }catch(error){
    process.stderr.write('Fable unified validation REFUSED: '+
      String(error?.message??error)+'\n');
    process.exitCode=1;
  }
}

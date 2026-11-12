#!/usr/bin/env node
/** Read-only audit. --strict exits 2 while missing closure evidence remains. */
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {auditClosureRegister} from './closure-gap-audit.mjs';
const base=fileURLToPath(new URL('../',import.meta.url));
export function runClosureAudit(args=[],print=console.log) {
  if(args.some(x=>!['--strict','--json'].includes(x))||new Set(args).size!==args.length)
    throw Error('CLOSURE_AUDIT_UNSUPPORTED_ARGUMENTS');
  const read=name=>JSON.parse(readFileSync(resolve(base,'docs/integrations',name),'utf8'));
  const out=auditClosureRegister(read('FABLE-FLUTTER-PARITY-MASTER.json'),read('FABLE-FINAL-CLOSURE-W0-GAP-REGISTER.json'));
  print(JSON.stringify(out,null,2));
  return args.includes('--strict')&&out.counts.outstanding>0?2:0;
}
if(process.argv[1]&&resolve(process.argv[1])===fileURLToPath(import.meta.url)){
  try{process.exitCode=runClosureAudit(process.argv.slice(2))}
  catch(error){console.error(String(error?.message||error));process.exitCode=1}
}

/**
 * W0.2: deterministic project-generation manifest shared byte-for-byte by
 * Fable Backend and Flutter setup. This validates decisions, NOT the authority
 * of a contract signature or a production deployment.
 */
import { createHash } from 'node:crypto';

export const KNOWN_FLUTTER_FEATURES = Object.freeze([
  'access_control','analytics','auth','biometrics','content','deeplinks',
  'localization','location','media','messaging','notifications','offline',
  'payments','profile','realtime','social','support',
]);
const ID = /^[a-z][a-z0-9]*(?:-[a-z0-9]+)*$/;
const IDENTIFIER = /^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*$/;
const SHA256 = /^[a-f0-9]{64}$/;
const COMMIT_SHA = /^[a-f0-9]{40}$/;
const BAD_KEYS = /(?:password|secret|private[_-]?key|access[_-]?token|refresh[_-]?token|api[_-]?key|credential)/i;

function fail(code) { throw new Error(`PROJECT_MANIFEST_${code}`); }
function object(value, keys, label) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) fail(`${label}_OBJECT_REQUIRED`);
  for (const key of Object.keys(value)) if (!keys.includes(key)) fail(`${label}_UNKNOWN_FIELD:${key}`);
  return value;
}
function requiredString(value, max, pattern, label) {
  if (typeof value !== 'string' || value.length < 1 || value.length > max ||
      value !== value.trim() || (pattern && !pattern.test(value))) fail(`${label}_INVALID`);
  return value;
}
function sortedUnique(input, pattern, label, allowed = null) {
  if (!Array.isArray(input) || input.length > 200) fail(`${label}_INVALID`);
  const result = [];
  for (const item of input) {
    const value = requiredString(item, 80, pattern, label);
    if (allowed && !allowed.includes(value)) fail(`${label}_UNKNOWN:${value}`);
    if (result.includes(value)) fail(`${label}_DUPLICATE:${value}`);
    result.push(value);
  }
  return result.sort();
}
function origin(value, label) {
  requiredString(value, 250, null, label);
  let url;
  try { url = new URL(value); } catch { fail(`${label}_INVALID`); }
  if (url.protocol !== 'https:' || url.username || url.password || url.search || url.hash ||
      !url.hostname || url.hostname === 'localhost' || url.hostname.endsWith('.localhost') ||
      url.pathname !== '/' || value !== url.origin) fail(`${label}_HTTPS_ORIGIN_REQUIRED`);
  return value;
}
function noCredentials(input, path = '') {
  if (Array.isArray(input)) return input.forEach((v,i) => noCredentials(v,`${path}[${i}]`));
  if (input && typeof input === 'object') for (const [key,value] of Object.entries(input)) {
    if (BAD_KEYS.test(key)) fail(`CREDENTIAL_FIELD_FORBIDDEN:${path}.${key}`);
    noCredentials(value,`${path}.${key}`);
  }
}
function canonical(value) {
  if (Array.isArray(value)) return value.map(canonical);
  if (value && typeof value === 'object') return Object.fromEntries(
    Object.keys(value).sort().map(key => [key, canonical(value[key])]));
  return value;
}
export function projectDecisionHash(decisionPlan) {
  return createHash('sha256').update(JSON.stringify(canonical(decisionPlan))).digest('hex');
}

/** A manifest is explicit input, never evidence that a contract has been verified. */
export function validateProjectGenerationManifest(input) {
  object(input, ['schemaVersion','kind','project','backend','frontend','source','execution'], 'ROOT');
  if (input.schemaVersion !== 1 || input.kind !== 'fable.project-generation-manifest') fail('SCHEMA_UNSUPPORTED');
  noCredentials(input);
  const project = object(input.project, ['id','displayName'], 'PROJECT');
  const projectId = requiredString(project.id, 63, ID, 'PROJECT_ID');
  if (projectId.length < 3) fail('PROJECT_ID_TOO_SHORT');
  const displayName = requiredString(project.displayName, 120, null, 'PROJECT_NAME');
  const backend = object(input.backend, ['kind','adapter','origin','contractSha256','contractProjectId','capabilities','operationIds','dpop'], 'BACKEND');
  if (!['fable','other'].includes(backend.kind)) fail('BACKEND_KIND_INVALID');
  const backendKind = backend.kind;
  const capabilities = sortedUnique(backend.capabilities, IDENTIFIER, 'BACKEND_CAPABILITIES');
  const operationIds = sortedUnique(backend.operationIds, IDENTIFIER, 'BACKEND_OPERATIONS');
  const backendOrigin = origin(backend.origin, 'BACKEND_ORIGIN');
  requiredString(backend.contractSha256, 64, SHA256, 'CONTRACT_SHA256');
  if (backendKind === 'fable') {
    if (backend.adapter !== 'fable-contract' || backend.dpop !== 'required' ||
        backend.contractProjectId !== projectId) fail('FABLE_BACKEND_POLICY');
  } else {
    if (!['openapi','custom'].includes(backend.adapter) || backend.dpop !== 'forbidden' ||
        backend.contractProjectId !== null || capabilities.length > 0) fail('OTHER_BACKEND_POLICY');
  }
  const frontend = object(input.frontend, ['client','features','locales','platforms'], 'FRONTEND');
  if (frontend.client !== 'flutter') fail('FRONTEND_CLIENT_INVALID');
  const features = sortedUnique(frontend.features, IDENTIFIER, 'FLUTTER_FEATURES',KNOWN_FLUTTER_FEATURES);
  const locales = sortedUnique(frontend.locales, /^[a-z]{2}(?:-[A-Z]{2})?$/, 'FLUTTER_LOCALES');
  const platforms = sortedUnique(frontend.platforms, /^[a-z]+$/, 'FLUTTER_PLATFORMS',['android','ios','web']);
  if (locales.length === 0 || platforms.length === 0) fail('FRONTEND_TARGET_REQUIRED');
  if (backendKind === 'other' && features.includes('auth') && operationIds.length === 0) {
    fail('OTHER_AUTH_CONTRACT_OPERATIONS_REQUIRED');
  }
  const source = object(input.source, ['backendCommit','flutterCommit'], 'SOURCE');
  requiredString(source.backendCommit, 40, COMMIT_SHA, 'BACKEND_COMMIT');
  requiredString(source.flutterCommit, 40, COMMIT_SHA, 'FLUTTER_COMMIT');
  const execution = object(input.execution, ['initiator','mode'], 'EXECUTION');
  if (!['developer','agent'].includes(execution.initiator) ||
      !['guided','headless'].includes(execution.mode) ||
      (execution.initiator === 'developer' && execution.mode !== 'guided') ||
      (execution.initiator === 'agent' && execution.mode !== 'headless')) fail('EXECUTION_MODE_INVALID');
  const decisionPlan = canonical({schemaVersion:1,kind:input.kind,
    project:{id:projectId,displayName},
    backend:{kind:backendKind,adapter:backend.adapter,origin:backendOrigin,
      contractSha256:backend.contractSha256,contractProjectId:backend.contractProjectId,
      capabilities,operationIds,dpop:backend.dpop},
    frontend:{client:'flutter',features,locales,platforms},
    source:{backendCommit:source.backendCommit,flutterCommit:source.flutterCommit},
  });
  return {manifest:canonical({...decisionPlan,execution:{initiator:execution.initiator,mode:execution.mode}}),
    decisionPlan,decisionHash:projectDecisionHash(decisionPlan),
    trust:{contractSignatureVerified:false,actualGeneratedProjectVerified:false,
      liveE2EVerified:false,productionReady:false},
  };
}

/** Deterministic comparison; modes are metadata, not selection differences. */
export function compareProjectGenerationManifests(a,b) {
  const A = validateProjectGenerationManifest(a), B = validateProjectGenerationManifest(b);
  return {sameDecisions:A.decisionHash === B.decisionHash,
    leftHash:A.decisionHash,rightHash:B.decisionHash,
    verifiedGeneratedProjects:false};
}

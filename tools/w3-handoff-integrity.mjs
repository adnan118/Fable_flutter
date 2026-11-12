/** RC210 W3 — compare a private Backend's current exported client handoff with
 * the Flutter project's actually imported artifacts. No historic RC86 pin.
 * Source identity MUST be independently supplied and verified by the CLI.
 */
import {createHash} from 'node:crypto';

const sha256 = value => createHash('sha256').update(value).digest('hex');
const hex40 = value => typeof value==='string' && /^[a-f0-9]{40}$/.test(value);
const hex64 = value => typeof value==='string' && /^[a-f0-9]{64}$/.test(value);
const canonical = value => Array.isArray(value) ? value.map(canonical) :
  value && typeof value==='object' ? Object.fromEntries(
    Object.entries(value).filter(([,v])=>v!==undefined)
      .sort(([a],[b])=>a.localeCompare(b))
      .map(([k,v])=>[k,canonical(v)])) : value;
const digest = value => sha256(JSON.stringify(canonical(value)));

export const W3_REQUIRED_DOCUMENTS = Object.freeze([
  'contract.json','flutter-handoff.json','openapi.json','mobile-core-operations.json',
]);

export function compareW3CurrentHandoff(backend,frontend,{
  frontendVerification=null,backendSourceCommit=null,sourcePinVerified=false,
}={}) {
  const issues=[];
  const fail=code=>{if(!issues.includes(code))issues.push(code);};
  if(!backend || !frontend || typeof backend!=='object' || typeof frontend!=='object')
    return {schemaVersion:1,batch:'RC210-W3',passed:false,
      issues:['missing_backend_or_flutter_export'],productionApproved:false};
  const bc=backend['contract.json'],fc=frontend['contract.json'];
  const manifest=backend['manifest.json'];
  if(!bc || bc.kind!=='fable.client-contract' ||
      bc.schemaVersion!==2 ||
      !bc.project || typeof bc.project.id!=='string' || !bc.project.id ||
      typeof bc.project.name!=='string'||!bc.project.name ||
      !Array.isArray(bc.operations)||!Array.isArray(bc.features)||
      !hex64(bc.contractHash))fail('invalid_backend_contract');
  else {
    const {contractHash,...withoutHash}=bc;
    if(digest(withoutHash)!==contractHash)fail('backend_contract_integrity_mismatch');
    if(bc.project.id==='test-project' || bc.project.name==='fable-test')
      fail('fixture_backend_project_not_accepted');
  }
  if(!manifest || manifest.kind!=='fable.client-contract' ||
      !['all','flutter'].includes(manifest.client) ||
      manifest.project?.id!==bc?.project?.id ||
      manifest.project?.name!==bc?.project?.name ||
      manifest.contractHash!==bc?.contractHash ||
      manifest.operationCount!==bc?.operations?.length ||
      manifest.featureCount!==bc?.features?.length)
    fail('backend_export_manifest_mismatch');
  const handoff=backend['flutter-handoff.json'];
  if(!handoff || handoff.kind!=='fable.flutter-handoff' ||
      handoff.client!=='flutter' ||
      handoff.backend?.project?.id!==bc?.project?.id ||
      handoff.backend?.contractHash!==bc?.contractHash ||
      !hex64(handoff.manifestHash))fail('backend_flutter_handoff_invalid');
  else {
    const {manifestHash,...unsigned}=handoff;
    if(sha256(JSON.stringify(unsigned))!==manifestHash)
      fail('backend_flutter_handoff_integrity_mismatch');
  }
  const mobile=backend['mobile-core-operations.json'];
  if(!mobile || mobile.kind!=='fable.mobile-core-operations' ||
      mobile.backendContractHash!==bc?.contractHash ||
      !Array.isArray(mobile.operations) ||
      !hex64(mobile.operationsHash) ||
      sha256(JSON.stringify(mobile.operations))!==mobile.operationsHash)
    fail('backend_mobile_core_integrity_mismatch');
  const openapi=backend['openapi.json'];
  if(!openapi || openapi.openapi!=='3.1.0' ||
      !openapi.paths || typeof openapi.paths!=='object' || Array.isArray(openapi.paths))
    fail('backend_openapi_invalid');
  for(const name of W3_REQUIRED_DOCUMENTS) {
    if(!backend[name] || !frontend[name])fail('missing_export_or_import:'+name);
    else if(digest(backend[name])!==digest(frontend[name]))
      fail('backend_flutter_artifact_drift:'+name);
  }
  if(!frontendVerification || frontendVerification.ok!==true ||
      frontendVerification.mode!=='project' ||
      frontendVerification.projectBound!==true ||
      frontendVerification.projectId!==bc?.project?.id ||
      frontendVerification.contractHash!==bc?.contractHash ||
      frontendVerification.productionReady!==false)
    fail('flutter_independent_project_verification_failed');
  if(!hex40(backendSourceCommit) || !sourcePinVerified)
    fail('backend_source_sha_not_independently_pinned');
  return {
    schemaVersion:1,batch:'RC210-W3',
    passed:issues.length===0,
    issues,
    backendSourceCommit:hex40(backendSourceCommit)?backendSourceCommit:null,
    backendSourcePinned:Boolean(sourcePinVerified && hex40(backendSourceCommit)),
    projectId:bc?.project?.id??null,
    contractHash:bc?.contractHash??null,
    operations:bc?.operations?.length??null,
    documentsCompared:W3_REQUIRED_DOCUMENTS.length,
    flutterProjectVerified:frontendVerification?.ok===true&&frontendVerification?.projectBound===true,
    productionApproved:false,
    scope:{sourceAndImportedContractOnly:true,
      flutterGeneratedFeatureBindingVerified:false,
      realProvidersVerified:false,liveE2EVerified:false,productionApproved:false},
  };
}

/**
 * Flutter, not Backend, owns this classification.
 * Backend exports capability evidence and runtime permissions; it MUST NOT
 * authorize deletion of native/local or mixed mobile features.
 *
 * server: a feature whose screen has no meaningful operation without Backend.
 * hybrid: the package has independent mobile behavior and optional Backend
 * services (notification UI, camera, location, credential device APIs, etc.).
 * client: standalone frontend decision, not a Backend capability.
 */
export const FEATURE_OWNERSHIP=Object.freeze({
  auth:'server',
  profile:'hybrid',
  notifications:'hybrid',
  media:'hybrid',
  localization:'hybrid',
  support:'server',
  social:'server',
  biometrics:'hybrid',
  realtime:'server',
  deeplinks:'client',
  messaging:'server',
  location:'hybrid',
  payments:'server',
  offline:'client',
  analytics:'hybrid',
  content:'server',
  access_control:'hybrid',
});
export const REQUIRED_CORE=Object.freeze(['auth','access_control']);
export const FEATURE_IDS=Object.freeze(Object.keys(FEATURE_OWNERSHIP));

export function classifyFeatureDecisions(declared, selection=null){
  if(!declared || declared.schemaVersion!==1 ||
    declared.source!=='backend-installed-capabilities' ||
    !Array.isArray(declared.enabled) || !Array.isArray(declared.disabled) ||
    !Array.isArray(declared.clientOnlyReview))throw Error('Missing full Backend feature inventory');

  const backendEnabled=new Set(declared.enabled);
  const backendDisabled=new Set(declared.disabled);
  const frontendOnly=new Set(declared.clientOnlyReview);
  const groups=[declared.enabled,declared.disabled,declared.clientOnlyReview];
  const inventory=groups.flat();
  if(inventory.length!==FEATURE_IDS.length ||
    new Set(inventory).size!==FEATURE_IDS.length ||
    inventory.some(id=>!FEATURE_IDS.includes(id)) ||
    REQUIRED_CORE.some(id=>!backendEnabled.has(id))) {
    throw Error('Incomplete or conflicting Backend capability inventory');
  }
  // Native features are not Backend-owned. Its decision may note a sync API,
  // but the package/lifecycle decision belongs only to the Flutter wizard.
  for(const id of FEATURE_IDS){
    if(FEATURE_OWNERSHIP[id]==='client' && !frontendOnly.has(id))
      throw Error('Backend cannot disable a frontend-owned feature: '+id);
    if(FEATURE_OWNERSHIP[id]!=='client' && frontendOnly.has(id))
      throw Error('Unexpected frontend-only classification from Backend: '+id);
  }
  const explicit=selection?.mode==='explicit';
  const selected=explicit?new Set(selection.features??[]):null;
  if(explicit && (!Array.isArray(selection.features) ||
    [...selected].some(id=>!FEATURE_IDS.includes(id)) ||
    selected.size!==selection.features.length))
    throw Error('Invalid explicit Flutter feature selection');
  // A requested server-only operation cannot be enabled when Backend lacks it.
  if(explicit)for(const id of selected)if(FEATURE_OWNERSHIP[id]==='server' &&
    backendDisabled.has(id))
      throw Error('Backend does not support requested server-only feature: '+id);

  const decisions=FEATURE_IDS.map(id=>{
    const ownership=FEATURE_OWNERSHIP[id];
    const supported=backendEnabled.has(id);
    const selectedByFrontend=selected?.has(id)??null;
    const always=REQUIRED_CORE.includes(id);
    // Retain client and hybrid implementation, even if Backend does not enable
    // any network operation. Explicit mobile decisions are reviewed separately.
    const retain=always || ownership!=='server' || (supported &&
      (!explicit || selectedByFrontend));
    const visible=ownership!=='client' &&
      supported && (always || !explicit || selectedByFrontend);
    const eligibleForBackendPrune=ownership==='server'&&!always&&!supported;
    return {
      id,ownership,backendEnabled:supported,frontendSelected:selectedByFrontend,
      retainPackage:retain,defaultBackendUiVisible:visible,
      requiresFrontendDecision:ownership!=='server',
      backendPruneEligible:eligibleForBackendPrune,
      reason:ownership==='client'?'frontend-owned':
        ownership==='hybrid'?'retain-native-and-optional-backend':'backend-owned',
    };
  });
  const byId=Object.fromEntries(decisions.map(x=>[x.id,x]));
  const ids=key=>decisions.filter(x=>x[key]).map(x=>x.id);
  return {
    schemaVersion:1,source:'flutter-ownership-policy',decisions,byId,
    visibleBackendFeatures:ids('defaultBackendUiVisible'),
    retainedPackages:ids('retainPackage'),
    backendPruneEligible:ids('backendPruneEligible'),
    frontendDecisionsRequired:ids('requiresFrontendDecision'),
    hybridRetained:decisions.filter(x=>x.ownership==='hybrid').map(x=>x.id),
    frontendOnly:decisions.filter(x=>x.ownership==='client').map(x=>x.id),
  };
}

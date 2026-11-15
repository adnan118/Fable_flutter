/**
 * RC266 W5 — idempotence is intentionally refused: never merge a second
 * guessed feature entry into an already edited pubspec or app registry.
 *
 * Pure source transformation. IO, backups, independent project contract pins
 * and safe apply are enforced by generate-typed-feature-rc116.mjs.
 */
const ID=/^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$/;

export function w5FeatureNames(featureId){
  if(typeof featureId!=='string'||featureId.length>64||!ID.test(featureId))
    throw Error('W5 invalid project feature identifier');
  return {
    packageName:'fable_'+featureId,
    variable:featureId.replace(/_([a-z])/g,(_,c)=>c.toUpperCase())+'ProjectFeature',
  };
}

export function planW5AppFeatureBinding({pubspec,registry,featureId}){
  const {packageName,variable}=w5FeatureNames(featureId);
  if(typeof pubspec!=='string'||typeof registry!=='string'||
     pubspec.length>1_000_000||registry.length>1_000_000)
    throw Error('W5 unexpected app source inputs');
  if(/^\s*name:\s*ci_fable\s*$/m.test(pubspec))
    throw Error('W5 refuses to mutate reusable ci_fable validation starter');
  if((pubspec.match(/^dependencies:\s*$/gm)||[]).length!==1||
     (registry.match(/^const List<FableFeature> installedFeatures = <FableFeature>\[$/gm)||[]).length!==1)
    throw Error('W5 app dependencies or typed feature registry are not canonical');
  const dependency='  '+packageName+':\n    path: packages/features/'+packageName+'\n';
  const exportedImport="import 'package:"+packageName+'/'+packageName+".dart';";
  if(new RegExp('^  '+packageName+':\\s*$','m').test(pubspec)||
     registry.includes(exportedImport)||
     new RegExp('^\\s*'+variable+',\\s*$','m').test(registry))
    throw Error('W5 feature already wired; no overwrite permitted');
  const updatedPubspec=pubspec.replace(/^dependencies:\s*$/m,
    ()=> 'dependencies:\n'+dependency.trimEnd());
  const marker='const List<FableFeature> installedFeatures = <FableFeature>[\n';
  const updatedRegistry=registry
    .replace(marker,()=>marker+'  '+variable+',\n')
    .replace(marker,()=>exportedImport+'\n\n'+marker);
  if(updatedPubspec===pubspec||updatedRegistry===registry||
     !updatedRegistry.includes('  '+variable+','))
    throw Error('W5 registry update failed');
  return {pubspec:updatedPubspec,registry:updatedRegistry,
    packageName,variable};
}

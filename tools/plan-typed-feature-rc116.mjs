/**
 * RC116: plan *only* source-exported, fully typed, authenticated Fable GET
 * operations. This is deliberately a strict subset of OpenAPI 3.1.
 * Unsupported schema MUST fail, never silently become dynamic or empty [].
 */
const FEATURE=/^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$/;
const OP_ID=/^[A-Za-z][A-Za-z0-9_.-]{0,150}$/;
const HASH=/^[a-f0-9]{64}$/;
const IDENT=/^[a-zA-Z][a-zA-Z0-9]*$/;
const KEYWORDS=new Set([
  'class','enum','extends','implements','with','final','const','var','int',
  'double','bool','String','dynamic','void','null','true','false','default',
  'abstract','interface','sealed','base','mixin','late','new','factory',
  'return','switch','case','if','else','while','for','in','is','as','try',
  'catch','throw','on','async','await','yield','super','this','required',
  'operator','static','get','set','import','export','library','part','typedef',
  'extension','covariant','external','continue','break','do','rethrow','assert',
  'hashCode','runtimeType','toString','noSuchMethod',
]);
const PATH=/^\/(?:[a-zA-Z0-9_-]+|:[a-zA-Z][a-zA-Z0-9_]*)(?:\/(?:[a-zA-Z0-9_-]+|:[a-zA-Z][a-zA-Z0-9_]*))*$/;
const primitive={string:'String',integer:'int',number:'double',boolean:'bool'};
const fail=(message)=>{throw Error('RC116 typed feature: '+message);};
function safeIdent(name){return IDENT.test(name)&&!KEYWORDS.has(name)&&name.length<=60;}
function safeString(s){if(typeof s!=='string'||/[\x00-\x1f\x7f\\$]/.test(s))fail('unsafe contract text');return s;}
function typeName(id){return id.split(/[._-]/).map(x=>
  x.length?x[0].toUpperCase()+x.slice(1):'').join('');}
function dataFields(schema){
  if(!schema||schema.type!=='object'||!schema.properties||
     typeof schema.properties!=='object'||Array.isArray(schema.properties)||
     '$ref'in schema ||'allOf'in schema||'oneOf'in schema||'anyOf'in schema ||
     'additionalProperties'in schema&&schema.additionalProperties!==false){
    fail('ambiguous object DTO schema; no runtime-contract/unknown data accepted');
  }
  const entries=Object.entries(schema.properties);
  if(entries.length<1||entries.length>32)fail('DTO must have 1..32 explicitly declared fields');
  const required=schema.required??[];
  if(!Array.isArray(required)||required.some(x=>!Object.hasOwn(schema.properties,x))||
     new Set(required).size!==required.length)fail('invalid DTO required fields');
  const fields=[];
  for(const [name,definition] of entries){
    if(!safeIdent(name))fail('unsafe Dart DTO field '+String(name));
    if(!definition||typeof definition!=='object'||
       !Object.hasOwn(primitive,definition.type)||
       Object.keys(definition).some(k=>!['type','description','format'].includes(k))||
       definition.format!==undefined &&
         !(definition.type==='string'&&['date-time','date','uuid','email','uri'].includes(definition.format))){
      fail('unsupported/ambiguous DTO field '+name);
    }
    fields.push({name,type:primitive[definition.type],required:required.includes(name)});
  }
  return fields;
}
export function planTypedFeature({featureId,contract,openapi,requirements,selectedFeatures}){
  if(typeof featureId!=='string'||!FEATURE.test(featureId)||featureId.length>64)
    fail('unsafe project feature identifier');
  if(contract?.kind!=='fable.client-contract'||!HASH.test(contract.contractHash)||
     !Array.isArray(contract.operations)||!contract.project?.id)
    fail('signed Fable contract and real project identity required');
  if(openapi?.openapi!=='3.1.0'||!openapi.paths||typeof openapi.paths!=='object')
    fail('OpenAPI 3.1 exported paths required');
  if(requirements?.kind!=='fable.feature-integration-requirements'||
     requirements.schemaVersion!==1 ||!requirements.features||
     typeof requirements.features!=='object')fail('explicit integration requirements required');
  if(!Array.isArray(selectedFeatures)||!selectedFeatures.includes(featureId))
    fail('feature not explicitly selected');
  const specs=requirements.features[featureId];
  if(!specs||specs.needsBackend!==true||!Array.isArray(specs.operations)||
      specs.operations.length===0||specs.operations.length>8)
    fail('1..8 explicitly selected backend read operations required');
  const seen=new Set(),names=new Set(),out=[];
  for(const spec of specs.operations){
    const id=spec?.operationId;
    if(typeof id!=='string'||!OP_ID.test(id)||seen.has(id))fail('unsafe/duplicate operation ID');
    seen.add(id);
    if(spec.method!=='GET'||typeof spec.path!=='string'||!PATH.test(spec.path))
      fail('read-only GET with a safe explicit contract path required for '+id);
    const candidates=contract.operations.filter(op=>op.operationId===id);
    if(candidates.length!==1)fail('operation not unique in project export: '+id);
    const op=candidates[0];
    if(op.method!=='GET'||op.path!==spec.path||op.feature!==featureId||
       op.public!==false||!HASH.test(op.contractHash)||
       !Array.isArray(op.permissions)||op.permissions.length===0)
      fail('operation/method/path/permission not pinned to Fable source: '+id);
    const normalized=spec.path.replace(/:([A-Za-z][A-Za-z0-9_]*)/g,'{$1}');
    const route=openapi.paths[normalized]?.get;
    if(!route||route.operationId!==id||
       route['x-fable-contract-hash']!==op.contractHash||
       route['x-fable-public']!==false||
       !Array.isArray(route.security)||route.security.length!==1||
       !Object.hasOwn(route.security[0],'bearerAuth'))
      fail('OpenAPI route/security/hash differs from Fable project contract: '+id);
    if(route.requestBody!==undefined)fail('GET with request body is unsupported: '+id);
    const params=[...spec.path.matchAll(/:([A-Za-z][A-Za-z0-9_]*)/g)].map(x=>x[1]);
    if(new Set(params).size!==params.length||params.some(x=>!safeIdent(x)))
      fail('unsafe path parameters: '+id);
    if((route.parameters??[]).length!==params.length||
       params.some(name=>!route.parameters.some(p=>p.in==='path'&&
         p.name===name&&p.required===true&&p.schema?.type==='string')))
      fail('only explicitly-typed string path parameters supported: '+id);
    const okStatuses=Object.entries(route.responses??{}).filter(([k])=>
      /^2\d\d$/.test(k));
    if(okStatuses.length!==1)fail('one unambiguous success response required: '+id);
    const schema=okStatuses[0][1]?.content?.['application/json']?.schema;
    if(!schema||schema.type!=='object'||
       schema.properties?.success?.const!==true||
       !Array.isArray(schema.required)||
       !schema.required.includes('success')||!schema.required.includes('data'))
      fail('strict Fable success envelope and data schema required: '+id);
    const fields=dataFields(schema.properties?.data);
    const className=typeName(id);
    if(!/^[A-Z][A-Za-z0-9]*$/.test(className)||className.length>80||
       names.has(className))fail('unsafe/colliding Dart type name: '+id);
    names.add(className);
    if(typeof op.contractHash!=='string')fail('missing operation hash');
    for(const value of [id,spec.path,op.contractHash])safeString(value);
    out.push({operationId:id,method:'GET',path:spec.path,contractHash:op.contractHash,
      className,fields,params});
  }
  return {featureId,projectId:contract.project.id,contractHash:contract.contractHash,
    operations:out.sort((a,b)=>a.operationId.localeCompare(b.operationId)),
    liveE2EVerified:false,
    unsupportedMethods:'POST/PUT/PATCH/DELETE and ambiguous schemas deliberately rejected'};
}

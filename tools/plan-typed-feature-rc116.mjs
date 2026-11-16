/**
 * RC116/RC292: plan only source-exported authenticated Fable GET, reviewed POST
 * and narrowly owner-scoped DELETE. Strict subset of OpenAPI 3.1.
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
/**
 * Independently recompute flat field shapes from the signed Fable operation's
 * response. OpenAPI's route hash metadata alone does not authenticate JSON
 * schema bodies; they must agree with the op response covered by opHash.
 */
function checkSignedResponseShape(op,schema,fields,signedData=op.response?.data){
  const source=signedData;
  if(op.response?.kind!=='fable-success-envelope'||source?.type!=='object'||
     !Array.isArray(source.fields)||source.fields.length!==fields.length){
    fail('signed operation has no matching flat response DTO: '+op.operationId);
  }
  const mappings={
    string:{type:'String'},text:{type:'String'},uuid:{type:'String',format:'uuid'},
    datetime:{type:'String',format:'date-time'},
    int:{type:'int'},decimal:{type:'double'},boolean:{type:'bool'},
  };
  const seen=new Set();
  for(const field of source.fields){
    const name=field?.name;
    if(typeof name!=='string'||seen.has(name)||!Object.hasOwn(mappings,field.type))
      fail('unsupported signed Backend response field: '+op.operationId);
    seen.add(name);
    const expected=mappings[field.type];
    const actual=fields.find(x=>x.name===name);
    const encoded=schema.properties[name];
    if(!actual || actual.type!==expected.type ||
       actual.required===(field.optional===true)||
       (encoded.format??null)!==(expected.format??null)){
      fail('OpenAPI data schema contradicts signed Backend response: '+op.operationId);
    }
  }
}

/**
 * RC267: explicit, signed, narrow create-POST only. We do NOT invent fields
 * from OpenAPI and we refuse security-sensitive/financial operations.
 * Only all-required text fields are supported so generated UI never guesses
 * boolean/date/currency behavior, secrets or a PATCH concurrency policy.
 */
/**
 * RC271: READ only source-verified unpaginated list results. No guessed
 * page/search input or fake runtime list. Use an immutable typed items model.
 */
function signedUnpaginatedListFields(op,schema){
  const signed=op.response?.data;
  if(op.method!=='GET'||!op.operationId.endsWith('.list.unpaginated')||
     op.response?.kind!=='fable-success-envelope'||
     signed?.type!=='list-result'||
     signed?.item?.type!=='object'||
     !Array.isArray(signed?.item?.fields)||
     !Array.isArray(signed?.meta?.modes)||
     signed.meta.modes.length!==1||
     signed.meta.modes[0]!=='unpaginated'||
     (op.request?.query??[]).length!==0||
     (op.request?.headers??[]).length!==0)
    fail('list operation requires signed unpaginated response and no unbound query/header: '+op.operationId);
  if(!schema||schema.type!=='object'||!schema.properties||
     Object.keys(schema.properties).sort().join(',')!=='items,meta'||
     !Array.isArray(schema.required)||
     schema.required.length!==2||
     !schema.required.includes('items')||!schema.required.includes('meta')||
     schema.properties.items?.type!=='array')
    fail('list response must contain explicit items + meta envelope: '+op.operationId);
  const metadata=schema.properties.meta;
  if(!metadata||metadata.type!=='object' ||
     Object.keys(metadata.properties??{}).sort().join(',')!=='count,limitExceeded,maxRows,mode'||
     metadata.properties.mode?.const!=='unpaginated'||
     metadata.properties.count?.type!=='integer'||
     metadata.properties.maxRows?.type!=='integer'||
     metadata.properties.limitExceeded?.type!=='boolean'||
     !Array.isArray(metadata.required)||
     metadata.required.length!==4||
     !['mode','count','maxRows','limitExceeded'].every(k=>metadata.required.includes(k)))
    fail('list metadata must match signed unpaginated format: '+op.operationId);
  const itemSchema=schema.properties.items.items;
  const fields=dataFields(itemSchema);
  checkSignedResponseShape(op,itemSchema,fields,signed.item);
  return fields;
}

/**
 * RC272 page-only read mode from a signed Backend list.paginated contract.
 * Search/filter/sort are intentionally NOT sent: their opt-in consumer UI is
 * a separate W5 gate. We still validate the full signed query declaration.
 */
function signedPaginatedListFields(op,schema,route){
  const signed=op.response?.data,id=op.operationId;
  if(op.recordAccess!=null &&
     !['permission-wide','global','none'].includes(op.recordAccess))
    fail('scoped/managed-entity pagination requires an explicitly bound tenant context: '+id);
  if(op.method!=='GET'||!id.endsWith('.list.paginated')||
     op.response?.kind!=='fable-success-envelope'||
     signed?.type!=='list-result'||signed.item?.type!=='object'||
     !Array.isArray(signed.item.fields)||
     !Array.isArray(signed.meta?.modes)||
     signed.meta.modes.length!==2||
     !['page','search'].every(mode=>signed.meta.modes.includes(mode))||
     !Array.isArray(op.request?.query) ||
     (op.request?.headers??[]).length!==0||
     op.request?.body!==undefined)
    fail('paginated read requires signed page/search metadata and no custom headers: '+id);
  const q=new Map();
  for(const raw of op.request.query){
    if(typeof raw?.key!=='string'||q.has(raw.key)||
       !/^[A-Za-z][A-Za-z0-9_]{0,50}$/.test(raw.key)||
       raw.required===true)
      fail('paginated read has unbound/invalid required query: '+id);
    q.set(raw.key,raw);
  }
  const declared=(route.parameters??[]).filter(p=>p.in==='query');
  if(declared.length!==q.size)fail('paginated query does not match signed route: '+id);
  for(const spec of declared){
    const source=q.get(spec.name);
    if(!source||spec.required===true||!spec.schema||
       spec.schema.type!==(source.type??'string')||
       (spec.schema.format??null)!==(source.format??null)||
       JSON.stringify(spec.schema.enum??null)!==JSON.stringify(source.enum??null)||
       (spec.schema.minimum??null)!==(source.minimum??null)||
       (spec.schema.maximum??null)!==(source.maximum??null)||
       (spec.name==='sort'&&
        JSON.stringify(spec['x-fable-sort-allowlist']??null)!==
          JSON.stringify(source.sortAllowedFields??null)))
      fail('paginated query schema differs from signed Backend: '+id);
  }
  for(const name of ['page','limit']){
    const source=q.get(name);
    if(!source||source.type!=='integer'||source.minimum!==1||
       (name==='limit'&&(typeof source.maximum!=='number'||source.maximum<20||
         source.maximum>500)))
      fail('paginated query must publish bounded page/limit: '+id);
  }
  const mode=q.get('mode');
  if(!mode||mode.type!=='string'||
     !Array.isArray(mode.enum)||mode.enum.length!==2||
     !['page','search'].every(x=>mode.enum.includes(x)))
    fail('paginated query mode must be explicit page/search enum: '+id);
  if(!schema||schema.type!=='object'||!schema.properties||
     Object.keys(schema.properties).sort().join(',')!=='items,meta'||
     schema.properties.items?.type!=='array'||
     !Array.isArray(schema.required)||schema.required.length!==2||
     !['items','meta'].every(x=>schema.required.includes(x)))
    fail('paginated items/meta result missing: '+id);
  const variants=schema.properties.meta?.oneOf;
  if(!Array.isArray(variants)||variants.length!==2)
    fail('paginated metadata requires signed page/search alternatives: '+id);
  const expectedPage={page:'integer',limit:'integer',total:'integer',totalPages:'integer'};
  const legacySearch={limit:'integer',count:'integer'};
  const pagedSearch={page:'integer',limit:'integer',total:'integer',totalPages:'integer',count:'integer'};
  const same=(a,b)=>JSON.stringify(Object.entries(a??{}).sort())===
    JSON.stringify(Object.entries(b).sort());
  if(!same(signed.meta?.page,expectedPage))
    fail('page metadata semantics are not signed: '+id);
  const searchPaged=same(signed.meta?.search,pagedSearch);
  if(!searchPaged&&!same(signed.meta?.search,legacySearch))
    fail('unknown search metadata shape: '+id);
  const searchQuery=q.get('q');
  if(searchQuery&&(searchQuery.type!=='string'||searchQuery.required===true))
    fail('search input must be a signed optional string: '+id);
  const searchPageSupported=searchPaged&&Boolean(searchQuery);
  const byMode=new Map();
  for(const entry of variants){
    const mode=entry?.properties?.mode?.const;
    if(!['page','search'].includes(mode)||byMode.has(mode)||
       entry?.type!=='object'||!Array.isArray(entry.required))
      fail('invalid paginated meta alternative: '+id);
    const names=mode==='page'
      ?['mode','page','limit','total','totalPages']
      :(searchPaged
        ?['mode','page','limit','total','totalPages','count']
        :['mode','limit','count']);
    if(entry.required.length!==names.length||
       Object.keys(entry.properties).sort().join(',')!==names.slice().sort().join(',')||
       !names.every(x=>entry.required.includes(x))||
       names.slice(1).some(x=>entry.properties[x]?.type!=='integer'))
      fail('paginated meta fields drift from Backend modes: '+id);
    byMode.set(mode,entry);
  }
  if(byMode.size!==2)fail('paginated mode alternative missing: '+id);
  const fields=dataFields(schema.properties.items.items);
  checkSignedResponseShape(op,schema.properties.items.items,fields,signed.item);
  // RC278: only exact-match filters proven by BOTH the signed query and
  // signed response item projection. This deliberately excludes fields that
  // may be protected/sensitive, numeric ranges, dates, and arbitrary sort.
  const reserved=new Set(['page','limit','mode','q','locale','sort']);
  const signedItems=new Map(signed.item.fields.map(f=>[f.name,f]));
  const filters=[];
  for(const [name,source] of q){
    if(reserved.has(name)||!safeIdent(name)||
       /(?:password|secret|token|otp|pin|private|credential|session|payment|billing|accesskey)/i.test(name))
      continue;
    const item=signedItems.get(name);
    const declaredItem=fields.find(f=>f.name===name);
    if(!item||!declaredItem||source.type!=='string'||
       source.required===true||source.format!=null||
       source.minimum!==undefined||source.maximum!==undefined||
       item.protectedAuth===true||item.sensitiveFilterSort===true)
      continue;
    let type=null;
    if(item.type==='boolean'&&declaredItem.type==='bool'&&
       Array.isArray(source.enum)&&source.enum.length===2&&
       source.enum.includes('true')&&source.enum.includes('false')){
      type='boolean';
    }else if(['string','text'].includes(item.type)&&
             declaredItem.type==='String'&&source.enum===undefined){
      type='text';
    }
    if(type)filters.push({name,type});
  }
  // RC280/RC281: append only complete signed numeric or UTC datetime ranges
  // after the existing RC278 exact-match controls. A pair consumes two slots.
  const selected=filters.slice(0,3);
  for(const item of signed.item.fields){
    if(selected.length>1)break; // a pair is atomic; never emit a lone bound
    const name=item?.name,declared=fields.find(f=>f.name===name);
    const numeric=['int','decimal'].includes(item?.type);
    const datetime=item?.type==='datetime';
    if((!numeric&&!datetime)||!safeIdent(name)||
       /(?:password|secret|token|otp|pin|private|credential|session|payment|billing|accesskey)/i.test(name)||
       item.protectedAuth===true||item.sensitiveFilterSort===true||
       declared?.type!==(item.type==='int'?'int':
         item.type==='decimal'?'double':'String'))continue;
    const min=name+(datetime?'From':'Min'),max=name+(datetime?'To':'Max');
    if(!safeIdent(min)||!safeIdent(max)||
       selected.some(f=>[name,min,max].includes(f.name)))continue;
    const expectedType=datetime?'string':'number';
    const expectedFormat=datetime?'date-time':null;
    const range=[q.get(name),q.get(min),q.get(max)];
    if(!range.every(v=>v?.type===expectedType && v.required!==true &&
       (v.format??null)===expectedFormat && v.enum===undefined &&
       v.minimum===undefined && v.maximum===undefined))continue;
    selected.push({name:min,type:item.type},{name:max,type:item.type});
  }
  // RC282: sorting is opt-in ONLY when the signed query agrees with
  // OpenAPI's explicit generated Backend allowlist, never inferred from DTO.
  const sorting=q.get('sort');
  const allow=sorting?.sortAllowedFields;
  const sortFields=(sorting?.type==='string' && sorting.required!==true &&
    sorting.enum===undefined && sorting.format==null &&
    Array.isArray(allow) && allow.length>0 && allow.length<=64 &&
    new Set(allow).size===allow.length &&
    allow.every(name=>safeIdent(name)&&
      !/(?:password|secret|token|otp|pin|private|credential|session|payment|billing|accesskey)/i.test(name)&&
      !signedItems.get(name)?.protectedAuth &&
      !signedItems.get(name)?.sensitiveFilterSort)
  )?allow.slice(0,8):[];
  return {fields,searchPageSupported,filters:selected,sortFields};
}

function validatedCreateFields(op,route,id,featureId){
  // A generic typed form cannot invent fresh OTP/Idempotency-Key headers,
  // managed-entity scope, URL query binding, or server-issued revisions.
  // Such operations need reviewed dedicated adapters and flow evidence.
  if(op.idempotency?.required===true ||
     (op.request?.headers??[]).length>0 ||
     (op.request?.query??[]).length>0 ||
     (op.recordAccess && !['global','none'].includes(op.recordAccess.mode)) ||
     (op.permissions??[]).some(p=>typeof p!=='string'||!p.trim()||
       /(?:^|[._-])(admin|manage|billing|payment|security|revoke|transfer)(?:$|[._-])/i.test(p)))
    fail('create POST needs a reviewed idempotency, context or privileged write adapter: '+id);
  if(!/(?:^|[._-])create$/i.test(id))
    fail('POST operation must declare an explicit create role: '+id);
  const restricted=new Set(['auth','payments','biometrics','access_control',
    'social','media','messaging','support']);
  if(restricted.has(featureId)||
     /(?:^|[.\/_-])(admin|security|billing|payment|delete|revoke|transfer|refund|token|otp|execute|purge|rotate|sync|cancel|disable|approve|send|charge|settle|run)(?:$|[.\/_-])/i.test(id+' '+op.path))
    fail('sensitive POST operation requires a dedicated reviewed workflow: '+id);
  const spec=route.requestBody;
  if(!spec||spec.required!==true ||
      !spec.content||Object.keys(spec.content).join(',')!=='application/json')
    fail('signed create POST requires an explicit JSON request body: '+id);
  const schema=spec.content['application/json']?.schema;
  if(!schema||schema.type!=='object' ||
      schema.additionalProperties!==false||
      !schema.properties||typeof schema.properties!=='object'||
      Array.isArray(schema.properties)||
      !Array.isArray(schema.required)||
      Object.keys(schema.properties).length<1||
      Object.keys(schema.properties).length>16||
      schema.required.length<1||
      schema.required.length>Object.keys(schema.properties).length||
      new Set(schema.required).size!==schema.required.length ||
      schema.required.some(name=>!Object.hasOwn(schema.properties,name)))
    fail('create POST requires a bounded flat object with at least one required field: '+id);
  const body=op.request?.body;
  if(body?.type!=='object'||!Array.isArray(body.fields)||
      body.fields.length!==Object.keys(schema.properties).length)
    fail('OpenAPI POST body lacks independently signed operation field evidence: '+id);
  const signed=new Map();
  for(const field of body.fields){
    if(field?.protectedAuth===true||field?.sensitiveFilterSort===true)
      fail('protected or sensitive Backend field requires a dedicated creator: '+id);
    if(!field||typeof field.name!=='string'||signed.has(field.name)||
       typeof field.optional!=='boolean'||
       !['string','text','uuid'].includes(field.type))
      fail('unsupported signed create POST field: '+id);
    signed.set(field.name,field);
  }
  const fields=[];
  for(const [name,definition] of Object.entries(schema.properties)){
    if(/(?:password|secret|token|otp|pin|cvv|card|bank|private|credential|session|amount|price|currency|balance|payment|billing|accesskey)/i.test(name))
      fail('sensitive or financial create field requires a reviewed feature workflow: '+id);
    if(!safeIdent(name)||
       !definition||definition.type!=='string'||
       Object.keys(definition).some(key=>!['type','format','description',
         'minLength','maxLength'].includes(key))||
       definition.minLength!==undefined && definition.minLength!==1 ||
       definition.maxLength!==undefined &&
         (!Number.isSafeInteger(definition.maxLength)||definition.maxLength<1||
          definition.maxLength>512))
      fail('unsafe or ambiguous create POST request field: '+id);
    const signedField=signed.get(name);
    const required=schema.required.includes(name);
    if(!signedField || signedField.optional===required ||
       (definition.format??null)!==(signedField.type==='uuid'?'uuid':null))
      fail('OpenAPI POST body does not match signed required/optional request fields: '+id);
    fields.push({name,type:'String',required,
      maxLength:definition.maxLength??512,uuid:signedField.type==='uuid'});
  }
  return fields;
}

/**
 * RC292: deletion is *not* a generic CRUD shortcut. A signed one-record,
 * owner-scoped DELETE with no custom headers/tenant binding is the only
 * subtype that can use the existing authenticated gateway without guessing
 * idempotency or optimistic concurrency support. The UI must show a second
 * explicit confirmation, never retry and never infer success from 404/409.
 */
function validatedOwnerDelete(op,route,featureId,params,id,schema){
  const forbidden=new Set(['auth','payments','media','access_control','biometrics',
    'messaging','support','social','notifications','account_lifecycle','roles',
    'organizations','system_settings','content_pages']);
  if(forbidden.has(featureId) ||
     /(?:^|[._-])(admin|billing|payment|security|revoke|transfer|purge|erase|destroy)(?:$|[._-])/i.test(id) ||
     op.method!=='DELETE'||!id.endsWith('.delete')||
     op.path!=='/'+featureId+'/:id' ||
     params.length!==1||params[0]!=='id'||
     !/^owner:[A-Za-z][A-Za-z0-9_]{0,50}$/.test(op.recordAccess??'')||
     (op.permissions??[]).length!==1||
     op.permissions[0]!==featureId+'.delete'||
     route['x-fable-permissions']?.length!==1 ||
     route['x-fable-permissions'][0]!==featureId+'.delete'||
     op.idempotency?.required===true||
     (op.request?.headers??[]).length!==0||
     (op.request?.query??[]).length!==0||
     op.request?.body!=null||
     route.requestBody!==undefined ||
     op.response?.kind!=='fable-success-envelope'||
     op.response.data?.type!=='null' ||
     schema.properties?.data?.type!=='null' ||
     op.httpStatus!==200)
    fail('DELETE requires signed owner-only UUID, null acknowledgement, no idempotency/header or privileged action: '+id);
  const idParam=(op.request?.params??[]).find(p=>p.name==='id');
  const routeId=route.parameters?.find(p=>p.name==='id'&&p.in==='path');
  if(idParam?.type!=='uuid'||routeId?.schema?.format!=='uuid')
    fail('DELETE requires a signed UUID record identifier: '+id);
  return true;
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
    fail('1..8 explicitly selected signed GET/reviewed POST/owner DELETE operations required');
  const seen=new Set(),names=new Set(),out=[];
  for(const spec of specs.operations){
    const id=spec?.operationId;
    if(typeof id!=='string'||!OP_ID.test(id)||seen.has(id))fail('unsafe/duplicate operation ID');
    seen.add(id);
    if(!['GET','POST','DELETE'].includes(spec.method)||typeof spec.path!=='string'||!PATH.test(spec.path))
      fail('GET, reviewed create POST, or reviewed owner DELETE contract path required for '+id);
    const candidates=contract.operations.filter(op=>op.operationId===id);
    if(candidates.length!==1)fail('operation not unique in project export: '+id);
    const op=candidates[0];
    if(op.method!==spec.method||op.path!==spec.path||op.feature!==featureId||
       op.public!==false||!HASH.test(op.contractHash)||
       !Array.isArray(op.permissions)||op.permissions.length===0)
      fail('operation/method/path/permission not pinned to Fable source: '+id);
    const normalized=spec.path.replace(/:([A-Za-z][A-Za-z0-9_]*)/g,'{$1}');
    const route=openapi.paths[normalized]?.[spec.method.toLowerCase()];
    if(!route||route.operationId!==id||
       route['x-fable-contract-hash']!==op.contractHash||
       route['x-fable-public']!==false||
       !Array.isArray(route.security)||route.security.length!==1||
       !Object.hasOwn(route.security[0],'bearerAuth'))
      fail('OpenAPI route/security/hash differs from Fable project contract: '+id);
    if(spec.method==='GET'&&route.requestBody!==undefined)
      fail('GET with request body is unsupported: '+id);
    const params=[...spec.path.matchAll(/:([A-Za-z][A-Za-z0-9_]*)/g)].map(x=>x[1]);
    if(new Set(params).size!==params.length||params.some(x=>!safeIdent(x)))
      fail('unsafe path parameters: '+id);
    const routePathParams=(route.parameters??[]).filter(p=>p.in==='path');
    const extraParams=(route.parameters??[]).filter(p=>p.in!=='path');
    if(routePathParams.length!==params.length||
       (extraParams.length>0&&!id.endsWith('.list.paginated'))||
       extraParams.some(p=>p.in!=='query')||
       params.some(name=>!routePathParams.some(p=>
         p.name===name&&p.required===true&&p.schema?.type==='string')))
      fail('only signed path parameters and explicitly reviewed paginated queries supported: '+id);
    // Verify parameter formats against the signed operation response/source,
    // not merely against the OpenAPI route's untrusted body.
    const sourceParams=op.request?.params;
    if(!Array.isArray(sourceParams)||sourceParams.length!==params.length||
       sourceParams.some(p=>{
         const declared=route.parameters.find(x=>x.in==='path'&&x.name===p.name);
         return !params.includes(p.name)||p.required!==true||
           !['string','uuid'].includes(p.type)||!declared||
           (declared.schema?.format??null)!==(p.type==='uuid'?'uuid':null);
       })){
      fail('OpenAPI path parameters contradict signed Backend operation: '+id);
    }
    const okStatuses=Object.entries(route.responses??{}).filter(([k])=>
      /^2\d\d$/.test(k));
    if(okStatuses.length!==1)fail('one unambiguous success response required: '+id);
    const schema=okStatuses[0][1]?.content?.['application/json']?.schema;
    if(!schema||schema.type!=='object'||
       schema.properties?.success?.const!==true||
       !Array.isArray(schema.required)||
       !schema.required.includes('success')||!schema.required.includes('data'))
      fail('strict Fable success envelope and data schema required: '+id);
    const resultKind=spec.method==='DELETE'?'confirmed-delete':
      op.response?.data?.type==='list-result'
      ?(op.operationId.endsWith('.list.paginated')?'paginated-list':'unpaginated-list')
      :'single';
    const paginated=resultKind==='paginated-list'
      ?signedPaginatedListFields(op,schema.properties?.data,route):null;
    const fields=resultKind==='confirmed-delete'?[]:
      resultKind==='unpaginated-list'
      ?signedUnpaginatedListFields(op,schema.properties?.data)
      :paginated?.fields??dataFields(schema.properties?.data);
    if(resultKind==='single')
      checkSignedResponseShape(op,schema.properties.data,fields);
    if(resultKind==='confirmed-delete')
      validatedOwnerDelete(op,route,featureId,params,id,schema);
    const className=typeName(id);
    if(!/^[A-Z][A-Za-z0-9]*$/.test(className)||className.length>80||
       names.has(className))fail('unsafe/colliding Dart type name: '+id);
    names.add(className);
    if(typeof op.contractHash!=='string')fail('missing operation hash');
    for(const value of [id,spec.path,op.contractHash])safeString(value);
    const bodyFields=spec.method==='POST'
      ?validatedCreateFields(op,route,id,featureId):[];
    if(bodyFields.some(f=>params.includes(f.name)))
      fail('request/body/path parameter name conflicts with response fields: '+id);
    out.push({operationId:id,method:spec.method,path:spec.path,contractHash:op.contractHash,
      className,fields,params,bodyFields,resultKind,
      supportsSearch:paginated?.searchPageSupported??false,
      filters:paginated?.filters??[],sortFields:paginated?.sortFields??[]});
  }
  return {featureId,projectId:contract.project.id,contractHash:contract.contractHash,
    operations:out.sort((a,b)=>a.operationId.localeCompare(b.operationId)),
    liveE2EVerified:false,
    unsupportedMethods:'PUT/PATCH, idempotency-required DELETE, tenant-scoped DELETE and sensitive POST deliberately rejected'};
}

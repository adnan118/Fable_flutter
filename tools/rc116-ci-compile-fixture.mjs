#!/usr/bin/env node
/**
 * ONLY GitHub Actions compile fixture; never a real exported Backend.
 * This is generated after source checks and before pub get / dart analyze.
 */
import {existsSync,mkdirSync,writeFileSync} from 'node:fs';
import {join,dirname} from 'node:path';
import {planTypedFeature} from './plan-typed-feature-rc116.mjs';
import {renderTypedFeature} from './render-typed-feature-rc116.mjs';
import {auditFeatureArchitectures} from './enforce-feature-architecture-rc115.mjs';
if(process.env.GITHUB_ACTIONS!=='true'||process.argv.length!==3||
   process.argv[2]!=='--ci-mock-only'){
  throw Error('RC116 fixture is CI mock-only; never run against a production project');
}
const hash='a'.repeat(64),opHash='b'.repeat(64);
const operationId='rc116_ci.orders.read',path='/orders/:id',featureId='rc116_ci';
const schema={
  type:'object',
  properties:{
    success:{const:true},
    data:{type:'object',properties:{
      id:{type:'string'},count:{type:'integer'},price:{type:'number'},
      published:{type:'boolean'},subtitle:{type:'string'},
    },required:['id','count','price','published']},
  },required:['success','data'],
};
const plan=planTypedFeature({
  featureId,contract:{kind:'fable.client-contract',
    project:{id:'synthetic-ci-only'},contractHash:hash,
    operations:[{operationId,path,feature:featureId,method:'GET',
      public:false,permissions:['orders.read'],contractHash:opHash,
      response:{kind:'fable-success-envelope',data:{type:'object',fields:[
        {name:'id',type:'string',optional:false},
        {name:'count',type:'int',optional:false},
        {name:'price',type:'decimal',optional:false},
        {name:'published',type:'boolean',optional:false},
        {name:'subtitle',type:'string',optional:true},
      ]}}}]},
  openapi:{openapi:'3.1.0',paths:{'/orders/{id}':{get:{
    operationId,'x-fable-public':false,'x-fable-contract-hash':opHash,
    security:[{bearerAuth:[]}],
    parameters:[{in:'path',name:'id',required:true,schema:{type:'string'}}],
    responses:{'200':{content:{'application/json':{schema}}}},
  }}}},
  requirements:{kind:'fable.feature-integration-requirements',schemaVersion:1,
    features:{rc116_ci:{needsBackend:true,operations:[
      {operationId,method:'GET',path},
    ]}}},
  selectedFeatures:[featureId],
});
const files=renderTypedFeature(plan);
const directory=join(process.cwd(),'packages/features/fable_rc116_ci');
if(existsSync(directory))throw Error('Refusing to overwrite CI mock package');
for(const [path,source] of files){
  const full=join(process.cwd(),path);
  mkdirSync(dirname(full),{recursive:true});
  writeFileSync(full,source,{flag:'wx',encoding:'utf8'});
}
const audit=auditFeatureArchitectures();
if(audit.findings.length)throw Error(audit.findings.join('\n'));
console.log('RC116 synthetic feature generated for CI compilation only; not a production Backend');

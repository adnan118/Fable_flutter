import test from 'node:test';
import assert from 'node:assert/strict';
import {renderTypedFeature} from '../tools/render-typed-feature-rc116.mjs';

function generated(kind){
 const featureId='schedule_ci',opId=featureId+'.'+
  (kind==='single'?'get':'list.unpaginated');
 const files=renderTypedFeature({
  featureId,projectId:'source-only',contractHash:'a'.repeat(64),
  operations:[{
   operationId:opId,method:'GET',path:'/schedule_ci',
   contractHash:'b'.repeat(64),
   className:kind==='single'?'ScheduleCiGet':'ScheduleCiListUnpaginated',
   resultKind:kind,params:[],bodyFields:[],
   fields:[
    {name:'startsAt',type:'String',required:true,datetime:true},
    {name:'endsAt',type:'String',required:false,datetime:true},
    {name:'note',type:'String',required:false},
   ],filters:[],sortFields:[],
  }],
 });
 const key=opId.replaceAll('.','_');
 const root='packages/features/fable_schedule_ci/';
 return {
  dto:files.get(root+'lib/src/data/'+key+'_dto.dart'),
  regression:files.get(root+'test/'+key+'_dto_test.dart'),
 };
}
test('RC354 source-signed datetime requires parseable offset-aware ISO instant and real Gregorian day',()=>{
 for(const kind of ['single','unpaginated-list']){
  const {dto,regression}=generated(kind);
  assert.ok(dto.includes('bool _validFableInstant(Object? input)'));
  assert.ok(dto.includes('DateTime.tryParse(input)==null'));
  assert.ok(dto.includes('DateTime.utc(y,m,d)'));
  assert.ok(dto.includes('day.year==y && day.month==m && day.day==d'));
  assert.ok(dto.includes('Invalid startsAt datetime field'));
  assert.ok(dto.includes('Invalid endsAt datetime field'));
  assert.ok(!dto.includes('Invalid note datetime field'));
  assert.ok(regression.includes('2026-11-17T12:34:56.000+01:00'));
  assert.ok(dto.includes('Z|[+-]'));
  assert.ok(dto.includes('input.length>40'));
 }
});
test('RC354 regular text fields retain their declared plain string semantics',()=>{
 const files=renderTypedFeature({
  featureId:'notes_ci',projectId:'source-only',contractHash:'a'.repeat(64),
  operations:[{
   operationId:'notes_ci.get',method:'GET',path:'/notes_ci',
   contractHash:'b'.repeat(64),className:'NotesCiGet',
   resultKind:'single',params:[],bodyFields:[],
   fields:[{name:'note',type:'String',required:true}],
  }],
 });
 const dto=files.get('packages/features/fable_notes_ci/lib/src/data/notes_ci_get_dto.dart');
 assert.ok(!dto.includes('_validFableInstant'));
});

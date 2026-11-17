import test from 'node:test';
import assert from 'node:assert/strict';
import {renderTypedFeature} from '../tools/render-typed-feature-rc116.mjs';

// Deferred source regression: no Flutter, Dart, or acceptance execution.
test('RC355 signed datetime DTOs reject impossible UTC offsets',()=>{
  const files=renderTypedFeature({
    featureId:'calendar_ci',projectId:'source-only',contractHash:'a'.repeat(64),
    operations:[{
      operationId:'calendar_ci.get',method:'GET',path:'/calendar_ci',
      contractHash:'b'.repeat(64),className:'CalendarCiGet',
      resultKind:'single',params:[],bodyFields:[],
      fields:[{name:'startsAt',type:'String',required:true,datetime:true}],
    }],
  });
  const dto=files.get('packages/features/fable_calendar_ci/lib/src/data/calendar_ci_get_dto.dart');
  assert.ok(dto.includes('14:00'), 'maximum positive/negative offset must be 14:00');
  assert.ok(dto.includes('1[0-3]'), 'hours 10-13 may carry minute offsets');
  assert.ok(!dto.includes('1[0-4]):[0-5][0-9]'),
    '14:01 through 14:59 must never be accepted');
  assert.ok(dto.includes('DateTime.utc(y,m,d)'), 'calendar-day validation retained');
});

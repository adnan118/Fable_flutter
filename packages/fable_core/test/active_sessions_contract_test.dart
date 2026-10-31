import 'package:flutter_test/flutter_test.dart';
import 'package:fable_core/fable_core.dart';

void main(){
  const sessionId='550e8400-e29b-41d4-a716-446655440000';
  final valid=<String,dynamic>{
    'id':sessionId,'isCurrent':true,
    'displayName':'Work laptop','deviceName':'Laptop',
    'clientType':'flutter','platform':'android','appVersion':'2.1',
    'createdAt':'2026-10-01T12:00:00.000Z',
    'lastUsedAt':'2026-10-20T10:20:00.000Z',
    'expiresAt':'2026-11-01T12:00:00.000Z',
  };
  test('Sessions are mapped from Backend presentation fields, not local tokens',(){
    final record=FableActiveSession.fromMap(valid);
    expect(record.id,sessionId);
    expect(record.isCurrent,true);
    expect(record.displayName,'Work laptop');
    expect(record.platform,'android');
    expect(record.createdAt.toUtc().month,10);
    expect(record.expiresAt.toUtc().month,11);
    expect(record.lastUsedAt,isNotNull);
  });
  test('Nullable device metadata is allowed without fabricating a name',(){
    final record=FableActiveSession.fromMap({
      'id':sessionId,'isCurrent':false,'createdAt':valid['createdAt'],
      'expiresAt':valid['expiresAt'],
    });
    expect(record.deviceName,isNull);
    expect(record.displayName,isNull);
    expect(record.isCurrent,false);
    expect(record.lastUsedAt,isNull);
  });
  test('Malformed session records fail closed',(){
    for(final bad in <Map<String,dynamic>>[
      {...valid,'id':'not-uuid'},
      {...valid,'id':'550e8400-e29b-41d4-0716-446655440000'},
      {...valid,'isCurrent':'true'},
      {...valid,'expiresAt':'tomorrow'},
      {...valid,'createdAt':null},
      {...valid,'deviceName':'device\u0000hidden'},
      {...valid,'displayName':List<String>.filled(200,'a').join()},
      {...valid,'platform':42},
    ]){
      expect(()=>FableActiveSession.fromMap(bad),throwsFormatException);
    }
  });
}

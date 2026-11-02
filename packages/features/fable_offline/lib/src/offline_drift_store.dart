import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

/// SQLite/Drift persistence for approved, non-secret cache and writes.
/// This database is not encrypted; never store credentials or sensitive data.
final class FableOfflineDriftStore extends GeneratedDatabase {
  FableOfflineDriftStore(super.executor);
  factory FableOfflineDriftStore.onDevice({
    required String backendOrigin, required String projectId,
    required String accountId, required String entityId,
  }) {
    final origin=Uri.tryParse(backendOrigin);
    if(origin==null||origin.scheme!='https'||!origin.hasAuthority||
      origin.userInfo.isNotEmpty||origin.hasQuery||origin.hasFragment||
      (origin.path.isNotEmpty&&origin.path!='/')||
      [projectId,accountId,entityId].any((x)=>x.trim().isEmpty)){
      throw ArgumentError('Verified HTTPS Backend/project/account/entity required');
    }
    final name=sha256.convert(utf8.encode(
      '$backendOrigin|$projectId|$accountId|$entityId')).toString().substring(0,24);
    return FableOfflineDriftStore(driftDatabase(
      name:'fable_offline_v1_$name',
      native:const DriftNativeOptions(shareAcrossIsolates:true)));
  }
  @override int get schemaVersion=>1;
  @override Iterable<TableInfo<Table,dynamic>> get allTables=>const [];
  @override Iterable<DatabaseSchemaEntity> get allSchemaEntities=>const [];
  @override MigrationStrategy get migration=>MigrationStrategy(
    onCreate:(m)async{
      await m.issueCustomQuery('''
CREATE TABLE fable_offline_cache(
 scope TEXT NOT NULL,cache_key TEXT NOT NULL,payload TEXT NOT NULL,
 expires_at_ms INTEGER NOT NULL,received_at_ms INTEGER NOT NULL,
 source_version TEXT,PRIMARY KEY(scope,cache_key))
''');
      await m.issueCustomQuery('''
CREATE TABLE fable_offline_outbox(
 id TEXT PRIMARY KEY,scope TEXT NOT NULL,operation_id TEXT NOT NULL,
 resource_id TEXT NOT NULL,body_json TEXT NOT NULL,base_version TEXT,
 created_at_ms INTEGER NOT NULL,retry_at_ms INTEGER NOT NULL,
 attempts INTEGER NOT NULL DEFAULT 0,
 status TEXT NOT NULL CHECK(status IN ('pending','review')),
 last_error_code TEXT)
''');
      await m.issueCustomQuery('''
CREATE INDEX fable_offline_pending ON fable_offline_outbox
(scope,status,retry_at_ms,created_at_ms)
''');
    },
    onUpgrade:(m,from,to)async{
      throw StateError('Offline schema migration requires explicit safe upgrade');
    });
  static void _valid(String x,[int max=256]){
    if(x.trim().isEmpty||x.length>max)throw ArgumentError('Invalid offline identity/key');
  }

  Future<void> putCache({required String scope,required String key,
    required Map<String,dynamic> value,required DateTime expiresAt,
    String? sourceVersion})async{
    _valid(scope);_valid(key,190);
    if(!expiresAt.isAfter(DateTime.now().toUtc()))
      throw ArgumentError('Cache expiry must be in future');
    final body=jsonEncode(value);
    if(body.length>128000)throw ArgumentError('Cache payload too large');
    await customStatement('''
INSERT INTO fable_offline_cache
(scope,cache_key,payload,expires_at_ms,received_at_ms,source_version)
VALUES(?,?,?,?,?,?)
ON CONFLICT(scope,cache_key) DO UPDATE SET payload=excluded.payload,
expires_at_ms=excluded.expires_at_ms,received_at_ms=excluded.received_at_ms,
source_version=excluded.source_version
''',[scope,key,body,expiresAt.millisecondsSinceEpoch,
      DateTime.now().toUtc().millisecondsSinceEpoch,sourceVersion]);
  }
  Future<Map<String,dynamic>?> getCache({required String scope,
    required String key,bool allowStale=false})async{
    _valid(scope);_valid(key,190);
    final rows=await customSelect(
      'SELECT payload,expires_at_ms FROM fable_offline_cache WHERE scope=? AND cache_key=?',
      variables:[Variable.withString(scope),Variable.withString(key)]).get();
    if(rows.isEmpty)return null;
    if(!allowStale&&rows.single.read<int>('expires_at_ms')<=
       DateTime.now().toUtc().millisecondsSinceEpoch)return null;
    return Map<String,dynamic>.from(jsonDecode(rows.single.read<String>('payload')) as Map);
  }
  Future<void> enqueue({required String id,required String scope,
    required String operationId,required String resourceId,
    required String bodyJson,String? baseVersion})async{
    _valid(id,190);_valid(scope);_valid(operationId,190);_valid(resourceId,190);
    if(bodyJson.length>16000)throw ArgumentError('Offline write too large');
    final now=DateTime.now().toUtc().millisecondsSinceEpoch;
    await customStatement('''
INSERT INTO fable_offline_outbox
(id,scope,operation_id,resource_id,body_json,base_version,
created_at_ms,retry_at_ms,attempts,status)
VALUES(?,?,?,?,?,?,?,?,0,'pending')
''',[id,scope,operationId,resourceId,bodyJson,baseVersion,now,now]);
  }
  Future<List<OfflineOutboxRow>> pending({required String scope,
    int limit=50,bool includeRetryDelay=false})async{
    _valid(scope);
    if(limit<1||limit>100)throw ArgumentError('Invalid pending limit');
    final retryClause=includeRetryDelay?'':'AND retry_at_ms <= ?';
    final rows=await customSelect('''
SELECT * FROM fable_offline_outbox WHERE scope=? AND status='pending'
$retryClause ORDER BY created_at_ms ASC,id ASC LIMIT ?
''',variables:[Variable.withString(scope),
      if(!includeRetryDelay)Variable.withInt(DateTime.now().toUtc().millisecondsSinceEpoch),
      Variable.withInt(limit)]).get();
    return rows.map((r)=>OfflineOutboxRow(
      id:r.read<String>('id'),operationId:r.read<String>('operation_id'),
      resourceId:r.read<String>('resource_id'),
      bodyJson:r.read<String>('body_json'),
      baseVersion:r.readNullable<String>('base_version'),
      attempts:r.read<int>('attempts'))).toList(growable:false);
  }
  Future<int> pendingCount(String scope)async{
    _valid(scope);
    final rows=await customSelect(
      'SELECT COUNT(*) AS total FROM fable_offline_outbox WHERE scope=?',
      variables:[Variable.withString(scope)]).get();
    return rows.single.read<int>('total');
  }
  Future<void> acknowledge(String scope,String id)async{
    _valid(scope);await customStatement(
      'DELETE FROM fable_offline_outbox WHERE scope=? AND id=?',[scope,id]);
  }
  Future<void> markReview(String scope,String id,String reason)async{
    _valid(scope);_valid(reason,190);
    await customStatement('''
UPDATE fable_offline_outbox SET status='review',last_error_code=?
WHERE scope=? AND id=?
''',[reason,scope,id]);
  }
  Future<void> markRetry(String scope,String id,int attempts,
    DateTime retryAt,String reason)async{
    _valid(scope);_valid(reason,190);
    if(attempts<1||attempts>100)throw ArgumentError('Invalid attempt count');
    await customStatement('''
UPDATE fable_offline_outbox SET attempts=?,retry_at_ms=?,last_error_code=?
WHERE scope=? AND id=? AND status='pending'
''',[attempts,retryAt.toUtc().millisecondsSinceEpoch,reason,scope,id]);
  }
  Future<void> clearScope(String scope)async{
    _valid(scope);
    await transaction(()async{
      await customStatement('DELETE FROM fable_offline_cache WHERE scope=?',[scope]);
      await customStatement('DELETE FROM fable_offline_outbox WHERE scope=?',[scope]);
    });
  }
}
final class OfflineOutboxRow {
  const OfflineOutboxRow({required this.id,required this.operationId,
    required this.resourceId,required this.bodyJson,required this.attempts,
    this.baseVersion});
  final String id,operationId,resourceId,bodyJson;
  final String? baseVersion;
  final int attempts;
}

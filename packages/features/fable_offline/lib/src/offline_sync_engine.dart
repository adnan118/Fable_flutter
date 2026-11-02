import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'offline_drift_store.dart';

enum FableSyncDisposition { acknowledged, retryLater, conflict, authorizationRequired, refused }

final class FableSyncAck {
  const FableSyncAck(this.disposition,{this.serverVersion});
  final FableSyncDisposition disposition;
  final String? serverVersion;
}
abstract interface class FableOfflineCommandExecutor {
  /// Server MUST receive idempotencyKey, enforce identity and authorize.
  /// Unknown timeout is 'retryLater', NEVER 'acknowledged'.
  Future<FableSyncAck> submit(OfflineOutboxRow row,{required String idempotencyKey});
}
abstract interface class FableVerifiedSyncContext {
  /// Null when logged out, offline, credentials stale, or scope changed.
  /// Scope must include Backend origin, Project, User, Managed Entity.
  Future<String?> verifiedScope();
  Future<bool> networkAvailable();
}
final class FableOfflineWriteGrant {
  const FableOfflineWriteGrant({
    required this.operationId,required this.method,
    required this.backendContractHash,required this.idempotencyVerified,
    required this.conflictProtocolVerified,
  });
  final String operationId,method,backendContractHash;
  final bool idempotencyVerified,conflictProtocolVerified;
}

/// Best-effort core; no guessed endpoints, no automatic payments or bookings.
///
/// The host must supply individually reviewed Backend operations and an
/// authenticated executor. Starting a sync never means changes were accepted.
final class FableOfflineSyncEngine {
  FableOfflineSyncEngine({required this.store,required this.context,
    required this.scope,required this.verifiedBackendContractHash,
    required Iterable<FableOfflineWriteGrant> writeGrants,
    required Iterable<String> publicCacheReadOperations,
    this.maxPending=100,
  }):_writeGrants={for(final p in writeGrants)p.operationId:p},
     _cacheReads=Set.unmodifiable(publicCacheReadOperations){
    if(scope.trim().isEmpty||verifiedBackendContractHash.trim().isEmpty)
      throw ArgumentError('Verified scope and backend contract hash required');
    if(maxPending<1||maxPending>1000)throw ArgumentError('Invalid queue capacity');
    for(final p in _writeGrants.values){
      if(p.backendContractHash!=verifiedBackendContractHash||
          !p.idempotencyVerified||!p.conflictProtocolVerified||
          !const {'POST','PUT','PATCH','DELETE'}.contains(p.method.toUpperCase())||
          _unsafeOperation.hasMatch(p.operationId)){
        throw ArgumentError('Offline mutation not approved by Backend contract');
      }
    }
    if(_cacheReads.any((id)=>_unsafeOperation.hasMatch(id)))
      throw ArgumentError('Sensitive API cannot be locally cached without review');
  }
  final FableOfflineDriftStore store;
  final FableVerifiedSyncContext context;
  final String scope,verifiedBackendContractHash;
  final int maxPending;
  final Map<String,FableOfflineWriteGrant> _writeGrants;
  final Set<String> _cacheReads;
  bool _busy=false;

  static final _rng=Random.secure();
  static final _unsafeOperation=RegExp(
    r'(payment|purchase|billing|balance|wallet|ledger|financial|price|refund|order|booking|reservation|stock|inventory|transfer|message|admin|auth|permission|password|user|account|security|delete-account)',
    caseSensitive:false);
  static final _unsafeFields=RegExp(
    r'(password|secret|access.?token|refresh.?token|authorization|otp|passkey|credit.?card|iban|cvv|private.?key|health|medical)',
    caseSensitive:false);
  static bool _containsSecret(dynamic value){
    if(value is Map){
      for(final entry in value.entries){
        if(_unsafeFields.hasMatch(entry.key.toString())||
           _containsSecret(entry.value))return true;
      }
    }else if(value is List){
      return value.any(_containsSecret);
    }
    return false;
  }
  static String _nextKey(){
    final b=List<int>.generate(32,(_)=>_rng.nextInt(256));
    return base64UrlEncode(b).replaceAll('=','');
  }
  Future<void> _requireScope()async{
    if(await context.verifiedScope()!=scope)
      throw StateError('Offline identity is not verified for this scope');
  }
  Future<void> cacheApprovedRead({required String operationId,
    required String cacheKey,required Map<String,dynamic> response,
    required Duration ttl,String? sourceVersion})async{
    if(!_cacheReads.contains(operationId)||_containsSecret(response)||
      ttl<=Duration.zero||ttl>const Duration(days:30))
      throw ArgumentError('Cache requires approved non-secret read and valid TTL');
    await _requireScope();
    await store.putCache(scope:scope,key:'$operationId:$cacheKey',
      value:response,expiresAt:DateTime.now().toUtc().add(ttl),
      sourceVersion:sourceVersion);
  }
  Future<Map<String,dynamic>?> cachedRead({required String operationId,
    required String cacheKey,bool allowStale=false})async{
    if(!_cacheReads.contains(operationId))throw ArgumentError('Read not allowed');
    await _requireScope();
    return store.getCache(scope:scope,key:'$operationId:$cacheKey',
      allowStale:allowStale);
  }
  Future<String> enqueueApprovedWrite({required String operationId,
    required String resourceId,required Map<String,dynamic> body,
    String? baseVersion})async{
    if(!_writeGrants.containsKey(operationId)||_containsSecret(body))
      throw ArgumentError('Offline mutation is not approved or contains secrets');
    if(baseVersion==null||baseVersion.trim().isEmpty)
      throw ArgumentError('Offline write needs server version/precondition');
    await _requireScope();
    if(await store.pendingCount(scope)>=maxPending)
      throw StateError('Offline queue capacity exceeded');
    final id=_nextKey();
    await store.enqueue(id:id,scope:scope,operationId:operationId,
      resourceId:resourceId,bodyJson:jsonEncode(body),baseVersion:baseVersion);
    return id;
  }

  /// Foreground or system-granted worker calls this with verified credentials.
  /// No active network or session => no attempts. A 401/403 stops the batch.
  Future<int> flush(FableOfflineCommandExecutor executor)async{
    if(_busy)return 0;
    _busy=true;
    var count=0;
    try{
      if(!(await context.networkAvailable()))return 0;
      await _requireScope();
      final rows=await store.pending(scope:scope);
      for(final row in rows){
        if(!(await context.networkAvailable()))break;
        // Recheck identity before every operation: never replay across logout.
        if(await context.verifiedScope()!=scope)break;
        if(!_writeGrants.containsKey(row.operationId)){
          await store.markReview(scope,row.id,'OPERATION_NO_LONGER_APPROVED');
          break;
        }
        FableSyncAck ack;
        try{
          ack=await executor.submit(row,idempotencyKey:row.id);
        }catch(_){
          ack=const FableSyncAck(FableSyncDisposition.retryLater);
        }
        switch(ack.disposition){
          case FableSyncDisposition.acknowledged:
            if(ack.serverVersion==null||ack.serverVersion!.isEmpty){
              await store.markReview(scope,row.id,'ACK_WITHOUT_SERVER_VERSION');
              return count;
            }
            await store.acknowledge(scope,row.id);
            count++;
          case FableSyncDisposition.retryLater:
            final attempt=row.attempts+1;
            if(attempt>6){
              await store.markReview(scope,row.id,'RETRY_EXHAUSTED');
            }else{
              final seconds=min(3600,15*(1<<min(attempt,7)))+_rng.nextInt(15);
              await store.markRetry(scope,row.id,attempt,
                DateTime.now().toUtc().add(Duration(seconds:seconds)),
                'TRANSIENT_OR_UNKNOWN_OUTCOME');
            }
            return count;
          case FableSyncDisposition.conflict:
            await store.markReview(scope,row.id,'SERVER_CONFLICT');
            return count;
          case FableSyncDisposition.authorizationRequired:
            // Don't remove pending data; user must re-authenticate.
            return count;
          case FableSyncDisposition.refused:
            await store.markReview(scope,row.id,'SERVER_REFUSED');
            return count;
        }
      }
      return count;
    }finally{_busy=false;}
  }
  Future<int> get pendingCount=>store.pendingCount(scope);
  Future<void> clearOnConfirmedLogout()async=>store.clearScope(scope);
}

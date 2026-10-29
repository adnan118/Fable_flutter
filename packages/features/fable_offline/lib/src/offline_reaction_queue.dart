import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fable_core/fable_core.dart';

/// This is NOT a general offline mutation queue. Only user-confirmed boolean
/// reactions with a server-verified idempotency contract may be deferred.
/// Payments, balances, orders, bookings, stock, private messages and secrets
/// must NEVER enter SharedPreferences or this queue.
enum OfflineReactionOutcome { acknowledged, retryLater, conflict }

abstract interface class OfflineReactionExecutor {
  /// Domain adapter MUST send idempotencyKey through its declared backend
  /// transport and enforce authenticated actor and authorization server-side.
  Future<OfflineReactionOutcome> apply({required String operationId,
    required String resourceId,required bool desired,
    required String idempotencyKey});
}

class DeferredReaction {
  const DeferredReaction({required this.id,required this.operationId,
    required this.resourceId,required this.desired,required this.createdAt,
    this.needsReview=false});
  final String id,operationId,resourceId;
  final bool desired,needsReview;
  final DateTime createdAt;
  Map<String,dynamic> toMap()=>{'id':id,'operationId':operationId,
    'resourceId':resourceId,'desired':desired,'createdAt':createdAt.toIso8601String(),
    'needsReview':needsReview};
  DeferredReaction review()=>DeferredReaction(id:id,operationId:operationId,
    resourceId:resourceId,desired:desired,createdAt:createdAt,needsReview:true);
}

class OfflineReactionQueue {
  OfflineReactionQueue({required Uri backendOrigin,required String accountId,
    required this.catalog,required Set<String> serverApprovedOperations,
    SharedPreferencesAsync? storage,this.maxActions=100})
   :_storage=storage??SharedPreferencesAsync(),
    _approved=Set.unmodifiable(serverApprovedOperations),
    _key='fable.offline.reaction.v1.${sha256.convert(utf8.encode('$backendOrigin:$accountId'))}' {
    final local=backendOrigin.scheme=='http'&&
      const {'localhost','127.0.0.1','10.0.2.2','::1'}.contains(backendOrigin.host);
    if(accountId.trim().isEmpty||accountId.length>190||
      !(backendOrigin.scheme=='https'||local)||!backendOrigin.hasAuthority||
      backendOrigin.userInfo.isNotEmpty||backendOrigin.hasQuery||
      backendOrigin.hasFragment||(backendOrigin.path.isNotEmpty&&backendOrigin.path!='/')){
      throw ArgumentError('Offline queue requires a verified account and backend origin');
    }
    if(maxActions<1||maxActions>500)throw ArgumentError('Invalid bounded queue size');
    for(final id in _approved){
      final op=catalog.require(id);
      if(!op.requiresAuth||!const {'POST','PUT','PATCH'}.contains(op.method.toUpperCase())||
        _unsafeOperation.hasMatch(id)){
        throw ArgumentError('Offline replay operation is not an approved authenticated interaction');
      }
    }
  }
  static final _unsafeOperation=RegExp(
    r'(payment|purchase|billing|balance|wallet|ledger|financial|price|refund|order|booking|stock|inventory|transfer|message|admin|account|auth|permission|delete)',
    caseSensitive:false);
  static final _resource=RegExp(r'^[A-Za-z0-9][A-Za-z0-9_.:-]{0,95}$');
  static final _random=Random.secure();
  final OperationCatalog catalog;
  final SharedPreferencesAsync _storage;
  final Set<String> _approved;
  final String _key;
  final int maxActions;
  bool _busy=false;
  static String _id(){
    final bytes=List<int>.generate(32,(_)=>_random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=','');
  }
  static DeferredReaction _parse(dynamic row){
    if(row is! Map||row['id'] is! String||row['operationId'] is! String||
      row['resourceId'] is! String||row['desired'] is! bool||
      row['createdAt'] is! String||row['needsReview'] is! bool){
      throw const FormatException('Invalid offline reaction entry');
    }
    final id=row['id'] as String;
    if(!RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(id)){
      throw const FormatException('Invalid replay key');
    }
    return DeferredReaction(id:id,operationId:row['operationId'] as String,
      resourceId:row['resourceId'] as String,desired:row['desired'] as bool,
      createdAt:DateTime.parse(row['createdAt'] as String),
      needsReview:row['needsReview'] as bool);
  }
  Future<List<DeferredReaction>> _read()async{
    final raw=await _storage.getString(_key);
    if(raw==null)return[];
    if(raw.length>150000)throw const FormatException('Offline queue exceeds safety size');
    final parsed=jsonDecode(raw);
    if(parsed is! List||parsed.length>maxActions)throw const FormatException('Invalid offline queue');
    final items=parsed.map(_parse).toList();
    if(items.any((x)=>!_approved.contains(x.operationId)||
      !_resource.hasMatch(x.resourceId)||_unsafeOperation.hasMatch(x.operationId))){
      throw StateError('Queue contains an operation no longer authorized for deferred replay');
    }
    return items;
  }
  Future<void> _write(List<DeferredReaction> items)async{
    if(items.length>maxActions)throw StateError('Offline queue capacity reached');
    await _storage.setString(_key,jsonEncode(items.map((x)=>x.toMap()).toList()));
  }
  Future<List<DeferredReaction>> pending()=>_read();
  Future<DeferredReaction> enqueue({required String operationId,
    required String resourceId,required bool desired})async{
    if(_busy)throw StateError('Queue is busy; retry interaction');
    _busy=true;
    try{
    if(!_approved.contains(operationId)||!_resource.hasMatch(resourceId)||
      _unsafeOperation.hasMatch(operationId)){
      throw ArgumentError('Only verified idempotent public reaction operations may be deferred');
    }
    final items=await _read();
    if(items.length>=maxActions)throw StateError('Offline queue full');
    final next=DeferredReaction(id:_id(),operationId:operationId,
      resourceId:resourceId,desired:desired,createdAt:DateTime.now().toUtc());
    await _write([...items,next]);
    return next;
    }finally{_busy=false;}
  }
  /// Explicitly invoke after connectivity and auth have been restored. Never
  /// auto-call on app launch before the active account has been verified.
  Future<int> flush(OfflineReactionExecutor executor)async{
    if(_busy)return 0;
    _busy=true;var confirmed=0;
    try{
      var items=await _read();
      while(items.isNotEmpty){
        final next=items.first;if(next.needsReview)break;
        final result=await executor.apply(operationId:next.operationId,
          resourceId:next.resourceId,desired:next.desired,idempotencyKey:next.id);
        if(result==OfflineReactionOutcome.retryLater)break;
        if(result==OfflineReactionOutcome.conflict){
          items=[next.review(),...items.skip(1)];await _write(items);break;
        }
        items=items.skip(1).toList();
        await _write(items); // successful replay is removed DURABLY
        confirmed++;
      }
      return confirmed;
    }finally{_busy=false;}
  }
  /// User-driven action; e.g. after a server-side conflict or on logout.
  Future<void> discard(String id)async{
    if(_busy)throw StateError('Cannot change queue during replay');
    _busy=true;
    try{final items=await _read();await _write(items.where((x)=>x.id!=id).toList());}
    finally{_busy=false;}
  }
  Future<void> clearOnLogout()async{
    if(_busy)throw StateError('Wait for in-flight replay before clearing');
    _busy=true;try{await _storage.remove(_key);}finally{_busy=false;}
  }
}

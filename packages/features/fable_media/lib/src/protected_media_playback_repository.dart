import 'dart:async';
import 'package:fable_core/fable_core.dart';

/// RC112 is intentionally Fable Backend-only. The Backend's published media
/// blueprint and controller are evidence of routes, NOT proof that the current
/// application's signed OpenAPI exports them. Missing exports disable playback.
class VerifiedFablePlaybackBindings {
  const VerifiedFablePlaybackBindings._(this.open,this.refresh,this.end);
  final String open,refresh,end;

  static String _path(String path)=>path.replaceAll('{id}',':id');
  static String _requireUnique(FableContract contract,String method,String path) {
    final matching=contract.operations.values.where((op)=>
      op.method.toUpperCase()==method &&
      _path(op.path)==path && op.requiresAuth && op.enforceAuth &&
      op.credentialHeader==null &&
      RegExp(r'^[a-f0-9]{64}$').hasMatch(op.contractHash)).toList();
    if(matching.length!=1){
      throw StateError('Signed Fable project contract has no unique protected media playback operation');
    }
    return matching.single.id;
  }
  factory VerifiedFablePlaybackBindings.fromGateway(FableAuthGateway gateway){
    final contract=gateway.verifiedContract;
    final open=_requireUnique(contract,'POST','/media/:id/playback');
    final refresh=_requireUnique(contract,'POST','/media/playback-sessions/:id/refresh');
    final end=_requireUnique(contract,'DELETE','/media/playback-sessions/:id');
    if({open,refresh,end}.length!=3){
      throw StateError('Protected media playback operations must be unique');
    }
    return VerifiedFablePlaybackBindings._(open,refresh,end);
  }
}

/// Non-sensitive, immutable view; access/license/grant tokens are NEVER held
/// by this DTO. A view from before refresh/logout/end is no longer valid.
class ProtectedMediaPlaybackView {
  const ProtectedMediaPlaybackView._({
    required this.sessionId,required this.assetId,required this.expiresAt,
    required this.idleExpiresAt,required this.accessTokenExpiresAt,
    required this.streamPath,
  });
  final String sessionId,assetId,streamPath;
  final DateTime expiresAt,idleExpiresAt,accessTokenExpiresAt;
  @override String toString() =>
      'ProtectedMediaPlaybackView(sessionId: [redacted], token: [redacted])';
}

class _PlaybackState {
  const _PlaybackState(this.view,this.token,this.epoch);
  final ProtectedMediaPlaybackView view;
  final String token;
  final int epoch;
}

/// Short-lived authenticated-stream session. No DRM-native integration is
/// implied, and a protected media bearer is never converted to a query URL.
/// Only one active playback session is managed per instance. Explicitly end
/// before starting another; the Backend is authoritative for revoke/expiry.
class FableProtectedMediaPlaybackRepository {
  FableProtectedMediaPlaybackRepository({required this.gateway})
    : bindings=VerifiedFablePlaybackBindings.fromGateway(gateway) {
    _identities=gateway.session.identityEvents.listen((_){
      // The event is synchronous in FableSecureSession. Purge tokens before
      // a previous user's delayed response can become visible to the next.
      _generation++;
      _state=null;
      _opening=false;
      _refreshing=false;
    });
  }
  final FableAuthGateway gateway;
  final VerifiedFablePlaybackBindings bindings;
  StreamSubscription<FableIdentityEvent>? _identities;
  _PlaybackState? _state;
  int _generation=0;
  bool _disposed=false,_opening=false,_refreshing=false;

  static final RegExp _uuid=RegExp(
    r'^[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-4[a-fA-F0-9]{3}-[89abAB][a-fA-F0-9]{3}-[a-fA-F0-9]{12}$');

  static String _id(String raw){
    if(!_uuid.hasMatch(raw))throw ArgumentError('Invalid protected media UUID');
    return raw;
  }
  bool _stillCurrent(int epoch,int generation)=>
      !_disposed && _generation==generation &&
      gateway.session.identityRevision==epoch;

  void _assertCurrent(int epoch,int generation){
    if(!_stillCurrent(epoch,generation)){
      throw StateError('Protected playback identity changed; discard response');
    }
  }

  static Map<String,dynamic> _payload(Object? raw){
    if(raw is! Map)throw const FormatException('Invalid Fable playback payload');
    final nested=raw['data'];
    final value=nested is Map?nested:raw;
    try{return Map<String,dynamic>.from(value);}
    catch(_){throw const FormatException('Malformed Fable playback payload');}
  }
  static Map<String,dynamic> _map(Object? raw){
    if(raw is! Map)throw const FormatException('Missing playback session metadata');
    try{return Map<String,dynamic>.from(raw);}
    catch(_){throw const FormatException('Malformed playback session metadata');}
  }
  static DateTime _expiry(Object? raw){
    if(raw is! String || raw.length>64 ||
       !(raw.endsWith('Z')||RegExp(r'[+-][0-9]{2}:[0-9]{2}$').hasMatch(raw))){
      throw const FormatException('Playback expiry must include timezone');
    }
    final parsed=DateTime.tryParse(raw)?.toUtc();
    if(parsed==null)throw const FormatException('Invalid playback expiry');
    return parsed;
  }
  static String _token(Object? value){
    if(value is! String||value.length<24||value.length>8192){
      throw const FormatException('Invalid protected media access token');
    }
    return value;
  }
  static bool _future(DateTime time)=>time.isAfter(DateTime.now().toUtc());

  static _PlaybackState _parseOpen(
    Map<String,dynamic> data,String assetId,String platform,int epoch){
    if(data['enabled']!=true || data['type']!='AUTHENTICATED_STREAM' ||
       data['platform']!=platform){
      // DRM is not an authenticated-clear-stream. Native DRM manifest/license
      // handling is a separate feature which must not silently fall back.
      throw StateError('Protected authenticated stream is unavailable or needs native DRM');
    }
    final session=_map(data['playbackSession']);
    final rawId=session['id'];
    final id=_id(rawId is String ? rawId : '');
    final expires=_expiry(session['expiresAt']);
    final idle=_expiry(session['idleExpiresAt']);
    final accessExpires=_expiry(data['accessTokenExpiresAt']);
    if(!_future(expires)||!_future(idle)||!_future(accessExpires)){
      throw StateError('Expired protected playback credentials');
    }
    final access=_token(data['accessToken']);
    final stream=_map(data['stream']);
    final expected='/media/' + assetId + '/content';
    final url=stream['url'];
    final authorization=_map(stream['authorization']);
    if(url!=expected || authorization['header']!='X-Fable-Media-Token' ||
       authorization['token']!=access){
      throw const FormatException('Protected content endpoint/header differs from Backend contract');
    }
    return _PlaybackState(ProtectedMediaPlaybackView._(
      sessionId:id,assetId:assetId,expiresAt:expires,
      idleExpiresAt:idle,accessTokenExpiresAt:accessExpires,
      streamPath:expected),access,epoch);
  }

  /// No implicit permission grants. grantToken comes from an independent
  /// authorised server action and is held only for this one request.
  Future<ProtectedMediaPlaybackView> open(String assetId,{
    required String platform,String? grantToken,
  }) async {
    _id(assetId);
    if(!const {'ANDROID','IOS'}.contains(platform)){
      throw ArgumentError('Protected Flutter playback is Android/iOS only');
    }
    if(grantToken!=null&&(grantToken.isEmpty||grantToken.length>4096)){
      throw ArgumentError('Invalid optional playback grant');
    }
    if(_disposed||_opening||_state!=null){
      throw StateError('End the active playback before starting another');
    }
    final epoch=gateway.session.identityRevision;
    final generation=++_generation;
    _opening=true;
    try{
      _assertCurrent(epoch,generation);
      final response=await gateway.execute(bindings.open,path:{'id':assetId},
        body:{'platform':platform,if(grantToken!=null)'grantToken':grantToken});
      _assertCurrent(epoch,generation);
      final parsed=_parseOpen(_payload(response.data),assetId,platform,epoch);
      _assertCurrent(epoch,generation);
      _state=parsed;
      return parsed.view;
    }finally{
      if(_generation==generation)_opening=false;
    }
  }

  /// This returns only the *additional* media access header, not the OAuth
  /// bearer used by the authenticated Backend transport. A verified native
  /// player/transport must supply BOTH; no URL query token is allowed.
  Map<String,String> currentContentHeader(ProtectedMediaPlaybackView view){
    final active=_state;
    if(_disposed||active==null||!identical(active.view,view)||
       gateway.session.identityRevision!=active.epoch ||
       !_future(view.expiresAt)||!_future(view.idleExpiresAt)||
       !_future(view.accessTokenExpiresAt)){
      throw StateError('Protected playback credentials are stale; refresh or reopen');
    }
    return Map<String,String>.unmodifiable({
      'X-Fable-Media-Token':active.token,
    });
  }

  Future<ProtectedMediaPlaybackView> refresh(ProtectedMediaPlaybackView view)async{
    final active=_state;
    if(_disposed||active==null||!identical(active.view,view)||_refreshing ||
       gateway.session.identityRevision!=active.epoch ||
       !_future(view.expiresAt)||!_future(view.idleExpiresAt)){
      throw StateError('Playback session is inactive or expired');
    }
    final epoch=gateway.session.identityRevision;
    final generation=_generation;
    _refreshing=true;
    try{
      _assertCurrent(epoch,generation);
      final response=await gateway.execute(bindings.refresh,path:{'id':view.sessionId});
      _assertCurrent(epoch,generation);
      if(!identical(_state,active))throw StateError('Playback ended during refresh');
      final data=_payload(response.data);
      final session=_map(data['playbackSession']);
      if(session['id']!=view.sessionId||session['assetId']!=view.assetId){
        throw const FormatException('Playback refresh changed session/asset');
      }
      final expires=_expiry(session['expiresAt']);
      final idle=_expiry(session['idleExpiresAt']);
      final accessExpires=_expiry(data['accessTokenExpiresAt']);
      if(!_future(expires)||!_future(idle)||!_future(accessExpires)){
        throw StateError('Expired refreshed playback session');
      }
      final token=_token(data['accessToken']);
      final next=ProtectedMediaPlaybackView._(
        sessionId:view.sessionId,assetId:view.assetId,
        expiresAt:expires,idleExpiresAt:idle,
        accessTokenExpiresAt:accessExpires,streamPath:view.streamPath);
      _assertCurrent(epoch,generation);
      if(!identical(_state,active))throw StateError('Playback ended during refresh');
      _state=_PlaybackState(next,token,epoch);
      return next;
    }finally{
      if(_generation==generation)_refreshing=false;
    }
  }

  /// Clear local access synchronously BEFORE invoking DELETE. An ambiguous
  /// network outcome is not retried automatically; the authoritative server
  /// session/TTL and Auth revocation control final access.
  Future<void> end(ProtectedMediaPlaybackView view)async{
    final active=_state;
    if(_disposed||active==null||!identical(active.view,view)||
       gateway.session.identityRevision!=active.epoch){
      throw StateError('Playback already ended or belongs to another session');
    }
    final epoch=gateway.session.identityRevision;
    final generation=++_generation;
    _state=null;
    _refreshing=false;
    _opening=false;
    _assertCurrent(epoch,generation);
    final response=await gateway.execute(bindings.end,path:{'id':view.sessionId});
    _assertCurrent(epoch,generation);
    final data=_payload(response.data);
    if(data['id']!=view.sessionId || data['status']!='REVOKED'){
      throw const FormatException('Backend did not confirm playback revocation');
    }
  }

  Future<void> dispose()async{
    _disposed=true;
    _generation++;
    _state=null;
    _opening=false;
    _refreshing=false;
    await _identities?.cancel();
    _identities=null;
  }
}

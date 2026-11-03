import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:fable_core/fable_core.dart';

/// Optional Firebase/APNs integration. Project-owned native Firebase setup,
/// explicit notification consent, and an authenticated Backend are mandatory.
class PushDeviceBindings {
  const PushDeviceBindings({required this.register,required this.unregister});
  const PushDeviceBindings.fable()
      : register='push.device.register',unregister='push.device.unregister';
  final String register,unregister;
  void verify(OperationCatalog catalog) {
    final a=catalog.require(register),b=catalog.require(unregister);
    if(register==unregister||a.method.toUpperCase()!='POST'||
       b.method.toUpperCase()!='DELETE'||!a.requiresAuth||!a.enforceAuth||
       !b.requiresAuth||!b.enforceAuth) {
      throw StateError('Push device registration needs a verified authenticated POST and DELETE');
    }
  }
}

/// Injectable native seam for deterministic simulation without Firebase or
/// physical devices. A real app uses FirebasePushTokenPlatform by default.
abstract interface class PushTokenPlatform {
  Future<bool> requestPermission();
  Future<bool> permissionGranted();
  Future<bool> apnsReady();
  Future<String?> getToken();
  Stream<String> get tokenChanges;
  Future<void> deleteToken();
}

class FirebasePushTokenPlatform implements PushTokenPlatform {
  FirebasePushTokenPlatform(this.messaging);
  final FirebaseMessaging messaging;
  static bool _allowed(AuthorizationStatus status) =>
      status==AuthorizationStatus.authorized||
      status==AuthorizationStatus.provisional;
  @override Future<bool> requestPermission()async {
    final settings=await messaging.requestPermission(alert:true,badge:true,
      sound:true,announcement:false,carPlay:false,criticalAlert:false,
      provisional:false);
    return _allowed(settings.authorizationStatus);
  }
  @override Future<bool> permissionGranted()async =>
      _allowed((await messaging.getNotificationSettings()).authorizationStatus);
  @override Future<bool> apnsReady()async=>(await messaging.getAPNSToken())!=null;
  @override Future<String?> getToken()=>messaging.getToken();
  @override Stream<String> get tokenChanges=>messaging.onTokenRefresh;
  @override Future<void> deleteToken()=>messaging.deleteToken();
}

class _PushAttempt {
  const _PushAttempt(this.generation,this.identity,this.tokenSerial);
  final int generation,identity,tokenSerial;
}

/// RC109: optional Push registrations must never borrow the next user's
/// identity, reuse the previous user's token/consent, or send stale token
/// refreshes after a newer registration has been queued.
///
/// The backend still owns device/session revocation. A client cannot undo a
/// mutation already committed by the server when the connection was cancelled.
/// For Other Backend both identityRevision and identityEvents MUST come from
/// its verified auth-session namespace, never the Fable namespace.
class FablePushDeviceRegistration {
  FablePushDeviceRegistration({
    required this.gateway,required OperationCatalog catalog,
    required this.bindings,required this.isSessionCurrent,required this.platform,
    this.deviceId,this.appKey,this.channel,FirebaseMessaging? messaging,
    PushTokenPlatform? tokenPlatform,
    int Function()? identityRevision,
    Stream<FableIdentityEvent>? identityEvents,
  }) : _tokenPlatform=tokenPlatform ??
        FirebasePushTokenPlatform(messaging??FirebaseMessaging.instance) {
    bindings.verify(catalog);
    if(!const {'ios','android'}.contains(platform)){
      throw ArgumentError('Use an Android or iOS mobile platform');
    }
    final fable=gateway is FableAuthGateway?gateway as FableAuthGateway:null;
    if(fable!=null && (identityRevision!=null||identityEvents!=null)){
      throw ArgumentError('Fable Push identity must come from the Fable gateway session');
    }
    if(fable==null && (identityRevision==null||identityEvents==null)){
      throw ArgumentError('Other Backend requires its verified session epoch and identity events');
    }
    _identityRevision=fable!=null
      ?()=>fable.session.identityRevision
      :identityRevision!;
    _identityEvents=(fable?.session.identityEvents ?? identityEvents!).listen((_){
      // Revoke even a registration still waiting on native permission/network.
      // Consent given by user A is NEVER automatically transferred to user B.
      _invalidateIdentity();
    });
  }
  final BackendApiGateway gateway;
  final PushDeviceBindings bindings;
  final bool Function() isSessionCurrent;
  final String platform;
  final String? deviceId,appKey,channel;
  final PushTokenPlatform _tokenPlatform;
  late final int Function() _identityRevision;
  StreamSubscription<FableIdentityEvent>? _identityEvents;
  StreamSubscription<String>? _tokens;
  StreamSubscription<RemoteMessage>? _foreground;
  Future<void> _tail=Future<void>.value();
  Future<void>? _identityCleanup;
  int _generation=0,_tokenSerial=0;
  int? _registeredIdentityRevision;
  bool _needsTokenDeletion=false;
  bool _optedIn=false;
  bool _disposed=false;
  bool get configured=>_tokens!=null;

  // Serialize all backend writes and native token deletion per device instance.
  // Errors from any earlier operation must not poison later cleanup/retries.
  Future<T> _serial<T>(Future<T> Function() operation)async {
    final previous=_tail;
    final completion=Completer<void>();
    _tail=completion.future;
    await previous;
    try{return await operation();}
    finally{completion.complete();}
  }

  _PushAttempt _capture()=>
    _PushAttempt(_generation,_identityRevision(),_tokenSerial);

  bool _sameIdentity(_PushAttempt attempt)=>
    !_disposed&&_optedIn&&isSessionCurrent()&&
    _generation==attempt.generation&&
    _identityRevision()==attempt.identity;

  bool _latestToken(_PushAttempt attempt)=>
    _sameIdentity(attempt)&&_tokenSerial==attempt.tokenSerial;

  void _invalidateIdentity(){
    _generation++;
    _tokenSerial++;
    _optedIn=false;
    _registeredIdentityRevision=null;
    _scheduleCleanup();
  }

  void _scheduleCleanup(){
    // Mark unsafe synchronously, even when an older HTTP request is in flight.
    _needsTokenDeletion=true;
    _identityCleanup=_serial<void>(()async{
      await _tokens?.cancel();_tokens=null;
      await _foreground?.cancel();_foreground=null;
      try{
        await _tokenPlatform.deleteToken();
        _needsTokenDeletion=false;
      }catch(_){
        // Keep new-account registration disabled until next explicit retry
        // successfully removes the old device token.
        _needsTokenDeletion=true;
      }
    });
  }

  Future<bool> _ensureClean()async {
    await _identityCleanup;
    if(_needsTokenDeletion){
      _scheduleCleanup();
      await _identityCleanup;
    }
    return !_needsTokenDeletion;
  }

  Future<bool> requestPermissionAndRegister({
    void Function()? onForegroundHint,
  })async {
    if(_disposed)throw StateError('Push device registration has been disposed');
    if(!await _ensureClean()){
      throw StateError('Previous account FCM token could not be cleared');
    }
    if(!isSessionCurrent())throw StateError('Verified authenticated session required');
    // This is an explicit USER action, never called implicitly by bootstrap.
    _optedIn=true;
    final attempt=_capture();
    final allowed=await _tokenPlatform.requestPermission();
    if(!_sameIdentity(attempt)||!allowed)return false;
    if(platform=='ios' && !await _tokenPlatform.apnsReady())return false;
    if(!_sameIdentity(attempt))return false;
    final token=await _tokenPlatform.getToken();
    if(!_sameIdentity(attempt)||token==null||token.length<20)return false;
    final accepted=await _register(token,attempt);
    if(!accepted||!_sameIdentity(attempt))return false;
    await _observeTokenChanges(attempt);
    if(!_sameIdentity(attempt))return false;
    await _foreground?.cancel();
    if(onForegroundHint!=null){
      _foreground=FirebaseMessaging.onMessage.listen((_){
        // Push invalidates cached state; the app must fetch protected data.
        if(_sameIdentity(attempt))onForegroundHint();
      });
    }
    return _sameIdentity(attempt);
  }

  Future<bool> _register(String token,_PushAttempt attempt)async{
    if(token.length<20||token.length>4096)throw StateError('Invalid FCM token');
    // A pending token refresh wins over an older queued attempt.
    final ticket=_PushAttempt(attempt.generation,attempt.identity,++_tokenSerial);
    return _serial<bool>(()async{
      if(!_latestToken(ticket))return false;
      // Do NOT move this check earlier: a queued old-user request may wait
      // behind native deletion or another registration before dispatch.
      await gateway.execute(bindings.register,body:{
        'token':token,'platform':platform,
        if(deviceId!=null)'deviceId':deviceId,
        if(appKey!=null)'appKey':appKey,
        if(channel!=null)'channel':channel,
        'clientPlatform':platform=='ios'?'IOS':'ANDROID',
      });
      if(!_sameIdentity(ticket)){
        // Never attribute an A response to the newly logged-in user B.
        _registeredIdentityRevision=null;
        _scheduleCleanup();
        return false;
      }
      if(!_latestToken(ticket))return false;
      _registeredIdentityRevision=ticket.identity;
      return true;
    });
  }

  Future<void> _observeTokenChanges(_PushAttempt attempt)async{
    await _tokens?.cancel();_tokens=null;
    if(!_sameIdentity(attempt))return;
    _tokens=_tokenPlatform.tokenChanges.listen((next){
      if(_sameIdentity(attempt)){
        // Event order, not network completion order, owns token freshness.
        unawaited(_register(next,attempt).catchError((Object _) => false));
      }
    });
  }

  /// Only retry after this account has opted in. Never request OS permission
  /// here; iOS/APNs readiness may change independently on app resume.
  Future<bool> retryRegistrationOnResume()async{
    if(_disposed||!await _ensureClean()||!_optedIn||!isSessionCurrent())return false;
    final attempt=_capture();
    if(!await _tokenPlatform.permissionGranted()||!_sameIdentity(attempt))return false;
    if(platform=='ios' && !await _tokenPlatform.apnsReady())return false;
    if(!_sameIdentity(attempt))return false;
    final token=await _tokenPlatform.getToken();
    if(!_sameIdentity(attempt)||token==null||token.length<20)return false;
    final accepted=await _register(token,attempt);
    if(!accepted||!_sameIdentity(attempt))return false;
    if(_tokens==null)await _observeTokenChanges(attempt);
    return _sameIdentity(attempt);
  }

  /// Explicit logout should call this before session revocation when online.
  /// Backend must also sever session/device associations on authoritative
  /// logout, regardless of whether the network DELETE completes.
  Future<void> unregisterCurrent()async{
    final identity=_identityRevision();
    final epoch=++_generation;
    _tokenSerial++;
    _optedIn=false;
    _registeredIdentityRevision=null;
    await _serial<void>(()async{
      await _tokens?.cancel();_tokens=null;
      await _foreground?.cancel();_foreground=null;
      try{
        // Refuse to send a stale DELETE using user B's bearer token.
        if(!_disposed&&_generation==epoch&&_identityRevision()==identity&&
           isSessionCurrent()){
          await gateway.execute(bindings.unregister);
        }
      }finally{
        try{
          await _tokenPlatform.deleteToken();
          _needsTokenDeletion=false;
        }catch(_){
          _needsTokenDeletion=true;
          rethrow;
        }
      }
    });
  }

  Future<void> dispose()async{
    _disposed=true;
    _generation++;
    _tokenSerial++;
    _optedIn=false;
    await _identityEvents?.cancel();
    await _tail;
    await _tokens?.cancel();_tokens=null;
    await _foreground?.cancel();_foreground=null;
  }
}

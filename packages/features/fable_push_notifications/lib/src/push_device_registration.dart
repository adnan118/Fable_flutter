import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:fable_core/fable_core.dart';

/// Optional Firebase/APNs integration; this package is installed ONLY when
/// notifications capability is selected. Application must configure Firebase
/// Android/iOS natively and initialize Firebase BEFORE using this class.
/// There is no implicit permission prompt, backend login or device registration.
class PushDeviceBindings {
  const PushDeviceBindings({required this.register,required this.unregister});
  const PushDeviceBindings.fable()
      :register='push.device.register',unregister='push.device.unregister';
  final String register,unregister;
  void verify(OperationCatalog catalog) {
    final a=catalog.require(register),b=catalog.require(unregister);
    if(register==unregister||a.method.toUpperCase()!='POST'||
       b.method.toUpperCase()!='DELETE'||!a.requiresAuth||!a.enforceAuth||
       !b.requiresAuth||!b.enforceAuth){
      throw StateError('Push device registration needs a verified authenticated POST and DELETE');
    }
  }
}

/// Requires a VERIFIED user session and an explicit opt-in to notifications.
/// `isSessionCurrent` should check account identity + auth revision, not merely
/// whether a token exists. It is rechecked before each backend write.
class FablePushDeviceRegistration {
  FablePushDeviceRegistration({required this.gateway,required OperationCatalog catalog,
    required this.bindings,required this.isSessionCurrent,required this.platform,
    this.deviceId,this.appKey,this.channel,FirebaseMessaging? messaging})
      : _messaging=messaging??FirebaseMessaging.instance {
    bindings.verify(catalog);
    if(!const {'ios','android'}.contains(platform))throw ArgumentError('Use an Android or iOS mobile platform');
    // Fable secure-session events are emitted after a committed login/logout.
    // A device token must not remain attached to an earlier account locally.
    if(gateway is FableAuthGateway){
      _identityEvents=gateway.session.identityEvents.listen((event){
        if(_registeredIdentityRevision!=null &&
           _registeredIdentityRevision!=event.revision){
          _registeredIdentityRevision=null;
          _identityCleanup=_forgetAfterIdentityChange();
        }
      });
    }
  }
  final BackendApiGateway gateway;
  final PushDeviceBindings bindings;
  final bool Function() isSessionCurrent;
  final String platform;
  final String? deviceId,appKey,channel;
  final FirebaseMessaging _messaging;
  StreamSubscription<String>? _tokens;
  StreamSubscription<RemoteMessage>? _foreground;
  StreamSubscription<FableIdentityEvent>? _identityEvents;
  Future<void>? _identityCleanup;
  int? _registeredIdentityRevision;
  bool _disposed=false;
  bool get configured=>_tokens!=null;

  Future<bool> requestPermissionAndRegister({void Function()? onForegroundHint})async{
    await _identityCleanup;
    if(_disposed||!isSessionCurrent())throw StateError('Verified authenticated session required');
    // User action must invoke this method; never prompt during app bootstrap.
    final p=await _messaging.requestPermission(alert:true,badge:true,sound:true,
      announcement:false,carPlay:false,criticalAlert:false,provisional:false);
    if(p.authorizationStatus!=AuthorizationStatus.authorized&&
       p.authorizationStatus!=AuthorizationStatus.provisional)return false;
    if(platform=='ios' && (await _messaging.getAPNSToken())==null){
      // APNs registration may not be ready yet; retry explicitly at lifecycle resume.
      return false;
    }
    final token=await _messaging.getToken();
    if(token==null||token.length<20)return false;
    await _register(token);
    await _observeTokenChanges();
    await _foreground?.cancel();
    if(onForegroundHint!=null){
      _foreground=FirebaseMessaging.onMessage.listen((_){
        // Push is an invalidation HINT; fetch current content and financial data
        // via protected domain GETs before showing/confirming updated values.
        if(isSessionCurrent()&&!_disposed)onForegroundHint();
      });
    }
    return true;
  }
  Future<void> _observeTokenChanges()async{
    await _tokens?.cancel();
    _tokens=_messaging.onTokenRefresh.listen((next){
      // Token refresh is retried on verified app resume if backend unavailable.
      if(isSessionCurrent()&&!_disposed){unawaited(_register(next).catchError((Object _)=>null));}
    });
  }
  /// Call when the app becomes active again after permissions/APNs registration
  /// or a transient network error. Does not display the OS permission dialog.
  Future<bool> retryRegistrationOnResume()async{
    await _identityCleanup;
    if(_disposed||!isSessionCurrent())return false;
    final settings=await _messaging.getNotificationSettings();
    if(settings.authorizationStatus!=AuthorizationStatus.authorized&&
       settings.authorizationStatus!=AuthorizationStatus.provisional)return false;
    if(platform=='ios' && (await _messaging.getAPNSToken())==null)return false;
    final token=await _messaging.getToken();
    if(token==null||token.length<20)return false;
    await _register(token);
    if(_tokens==null)await _observeTokenChanges();
    return true;
  }
  Future<void> _register(String token)async{
    if(_disposed||!isSessionCurrent())return;
    if(token.length<20||token.length>4096)throw StateError('Invalid FCM token');
    final fable=gateway is FableAuthGateway?gateway as FableAuthGateway:null;
    final identity=fable?.session.identityRevision;
    await gateway.execute(bindings.register,body:{'token':token,'platform':platform,
      if(deviceId!=null)'deviceId':deviceId,
      if(appKey!=null)'appKey':appKey,
      if(channel!=null)'channel':channel,
      'clientPlatform':platform=='ios'?'IOS':'ANDROID'});
    if(_disposed || !isSessionCurrent() ||
       (identity!=null && fable!.session.identityRevision!=identity)){
      // A late successful registration belongs to a revoked/replaced login.
      _registeredIdentityRevision=null;
      _identityCleanup=_forgetAfterIdentityChange();
      await _identityCleanup;
      return;
    }
    _registeredIdentityRevision=identity;
  }
  Future<void> _forgetAfterIdentityChange()async{
    // Do not make a privileged unregister request using a replaced identity.
    // Backend session-revocation events delete server token associations.
    await _tokens?.cancel();_tokens=null;
    await _foreground?.cancel();_foreground=null;
    if(!_disposed)await _messaging.deleteToken();
  }
  /// Logout calls this BEFORE revoking the session if online; the backend
  /// also revokes push device associations on session logout independently.
  Future<void> unregisterCurrent()async{
    await _identityCleanup;
    _registeredIdentityRevision=null;
    await _tokens?.cancel();_tokens=null;
    await _foreground?.cancel();_foreground=null;
    if(isSessionCurrent())await gateway.execute(bindings.unregister);
    await _messaging.deleteToken();
  }
  Future<void> dispose()async{
    _disposed=true;
    await _identityEvents?.cancel();
    await _identityCleanup;
    await _tokens?.cancel();await _foreground?.cancel();
  }
}

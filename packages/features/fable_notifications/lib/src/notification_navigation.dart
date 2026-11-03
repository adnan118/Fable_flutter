import 'package:flutter/widgets.dart';

/// Common notification-tap handler for FCM and the in-app inbox.
/// It never interprets arbitrary notification text as code, routes or permissions.
/// Generated app registers only installed, verified destinations.
class FableNotificationNavigation {
  FableNotificationNavigation._();
  static final instance = FableNotificationNavigation._();
  final navigatorKey = GlobalKey<NavigatorState>();
  Future<bool> Function(String destination, Map<String, String> data)? navigateCapability;
  Future<bool> Function(Uri url)? navigateVerifiedUrl;
  /// Project must register the matching local route. No implicit route builder.
  Future<bool> Function(String route)? navigateVerifiedAppRoute;
  Future<bool> Function()? isAuthenticated;
  /// Optional identity epoch supplied by the app's verified Auth session.
  /// A token's presence is not proof that an awaited navigation still belongs
  /// to the user who tapped the notification.
  int Function()? identityRevision;
  Map<String,String>? _pending;
  int _revision = 0;
  bool get hasPending => _pending != null;
  Future<bool> resumeAfterLogin() async {
    final saved=_pending;
    if(saved==null)return false;
    // New attempt revalidates the current session; queued data grants nothing.
    return open(saved);
  }
  void clearPending() {_revision++;_pending=null;}
  /// Stop navigation started by the prior login without discarding a pending
  /// anonymous tap that may be resumed after an explicit successful login.
  void invalidateInFlight() {_revision++;}


  Future<bool> open(Map<String, String> data) async {
    final revision = ++_revision;
    final identityAtTap = identityRevision?.call();
    bool sameContext() => revision == _revision &&
      (identityRevision == null || identityRevision!() == identityAtTap);
    final target = data['target'] ?? data['route'];
    final rawUrl = data['deepLink'] ?? data['url'];
    try {
      if(isAuthenticated != null && !await isAuthenticated!()) {
        if(sameContext()) _pending = Map.unmodifiable(Map<String,String>.from(data));
        return false;
      }
      if(!sameContext()) return false;
      _pending = null;
      if (rawUrl != null && rawUrl.isNotEmpty && rawUrl.length <= 2048) {
        final url = Uri.tryParse(rawUrl);
        if (url != null && url.scheme == 'https' && url.userInfo.isEmpty &&
            !url.hasPort && navigateVerifiedUrl != null) {
          // The app owns the verified host/path allowlist; check the epoch
          // BEFORE dispatch as well as after an awaited callback completes.
          if(!sameContext()) return false;
          final result = await navigateVerifiedUrl!(url);
          if(!sameContext()) return false;
          if(result) return true;
        }
      }
      if (target != null && RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(target) &&
          navigateCapability != null && target != 'notifications') {
        if(!sameContext()) return false;
        final result = await navigateCapability!(target, Map.unmodifiable(data));
        if(!sameContext()) return false;
        if(result) return true;
      }
      if(!sameContext()) return false;
      // No destination is an explicit request to open notifications.
      // Failed or forbidden routes must never be followed with an unsafe fallback.
      final fallback = await (navigateCapability?.call(
        'notifications', Map.unmodifiable(data)) ?? Future.value(false));
      return sameContext() && fallback;
    } catch (_) {
      if(!sameContext()) return false;
      try {
        final fallback=await (navigateCapability?.call(
          'notifications', Map.unmodifiable(data)) ?? Future.value(false));
        return sameContext() && fallback;
      } catch (_) { return false; }
    }
  }

  Future<bool> openVerifiedInternalRoute(String route) async {
    if(route.length>240||!RegExp(r'^/[a-zA-Z0-9_/-]+$').hasMatch(route)||
       route.contains('//')||route.contains('..')||!route.contains('password'))
      return false;
    final handler=navigateVerifiedAppRoute;
    if(handler==null)return false;
    try {return await handler(route);} catch(_){return false;}
  }
  void reset() { clearPending(); navigateCapability = null; navigateVerifiedUrl = null; navigateVerifiedAppRoute=null; isAuthenticated=null; identityRevision=null; }
}

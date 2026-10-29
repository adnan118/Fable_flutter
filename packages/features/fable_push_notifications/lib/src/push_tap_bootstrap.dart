import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:fable_notifications/fable_notifications.dart';

/// Handles only USER TAPS. Foreground FCM onMessage is not a tap event.
/// A real Firebase native configuration is required. No fake service account,
/// application IDs or default push permission is generated.
class FablePushTapBootstrap extends StatefulWidget {
  const FablePushTapBootstrap({super.key, required this.child});
  final Widget child;
  @override State<FablePushTapBootstrap> createState()=>_FablePushTapBootstrapState();
}
class _FablePushTapBootstrapState extends State<FablePushTapBootstrap> {
  StreamSubscription<RemoteMessage>? _opened;
  StreamSubscription<RemoteMessage>? _foreground;
  bool _closed=false;
  String? _lastId;
  DateTime? _lastTap;
  @override void initState(){super.initState();unawaited(_start());}
  Future<void> _start()async{
    try{
      // Native Firebase resources must have been configured by flutterfire.
      if(Firebase.apps.isEmpty)await Firebase.initializeApp();
      if(_closed||!mounted)return;
      final messaging=FirebaseMessaging.instance;
      // Foreground delivery is NOT a user tap; refresh any visible inbox only.
      _foreground=FirebaseMessaging.onMessage.listen((_) {
        FableInboxRefreshSignal.instance.notifyChanged();
      }, onError:(Object error)=>debugPrint('Foreground push stream unavailable: $error'));
      _opened=FirebaseMessaging.onMessageOpenedApp.listen((message){
        unawaited(_deliver(message));
      }, onError:(Object error)=>debugPrint('Notification click stream unavailable: $error'));
      final initial=await messaging.getInitialMessage();
      if(initial!=null)await _deliver(initial);
    }catch(error){debugPrint('Firebase notification tap setup requires native configuration: $error');}
  }
  Future<void> _deliver(RemoteMessage message)async{
    if(_closed||!mounted)return;
    final now=DateTime.now();
    if(message.messageId!=null&&_lastId==message.messageId&&_lastTap!=null&&
       now.difference(_lastTap!)<const Duration(seconds:3))return;
    _lastId=message.messageId;_lastTap=now;
    // Delay until MaterialApp installs its navigation callbacks.
    await WidgetsBinding.instance.endOfFrame;
    if(_closed||!mounted)return;
    await FableNotificationNavigation.instance.open(message.data);
  }
  @override void dispose(){_closed=true;unawaited(_opened?.cancel());unawaited(_foreground?.cancel());super.dispose();}
  @override Widget build(BuildContext context)=>widget.child;
}

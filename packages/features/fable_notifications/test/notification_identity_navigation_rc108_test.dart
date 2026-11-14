import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:fable_notifications/fable_notifications.dart';

/// Simulated sessions/network completion only: no FCM credentials, DB, or
/// physical Android/iOS assertions are made by this test.
void main(){
  final navigation=FableNotificationNavigation.instance;
  tearDown(navigation.reset);

  test('RC108 login changes during awaited Auth check: old tap never navigates',()async{
    var identity=11;
    final auth=Completer<bool>();
    final opened=<String>[];
    navigation.identityRevision=()=>identity;
    navigation.isAuthenticated=()=>auth.future;
    navigation.navigateCapability=(target,_)async{
      opened.add(target);
      return true;
    };
    final pending=navigation.open({'target':'profile'});
    identity=12; // A -> B while check for A is unresolved.
    auth.complete(true);
    expect(await pending,false);
    expect(opened,isEmpty);
    expect(navigation.hasPending,false);
  });

  test('RC108 same-session verified navigation remains functional',()async{
    var identity=20;
    final opened=<String>[];
    navigation.identityRevision=()=>identity;
    navigation.isAuthenticated=()async=>true;
    navigation.navigateCapability=(target,_)async{
      opened.add(target);
      return target=='content';
    };
    expect(await navigation.open({'target':'content'}),true);
    expect(opened,['content']);
    identity=21;
    expect(await navigation.open({'target':'content'}),true);
    expect(opened.length,2);
  });

  test('RC108 event revokes old tap without dropping deferred anonymous tap',()async{
    var identity=0;
    var loggedIn=false;
    final invoked=<String>[];
    navigation.identityRevision=()=>identity;
    navigation.isAuthenticated=()async=>loggedIn;
    navigation.navigateCapability=(target,_)async{
      invoked.add(target);
      return true;
    };
    expect(await navigation.open({'target':'notifications'}),false);
    expect(navigation.hasPending,true);
    identity=1;
    navigation.invalidateInFlight(); // Auth event, not logout.
    loggedIn=true;
    expect(await navigation.resumeAfterLogin(),true);
    expect(invoked,['notifications']);
    expect(navigation.hasPending,false);
  });

  test('RC108 identity switch during verified URL callback cannot fall back to another user',()async{
    var identity=31;
    final tapped=Completer<bool>();
    final opened=<String>[];
    navigation.identityRevision=()=>identity;
    navigation.isAuthenticated=()async=>true;
    navigation.navigateVerifiedUrl=(_)=>tapped.future;
    navigation.navigateCapability=(target,_)async{
      opened.add(target);
      return true;
    };
    final pending=navigation.open({'url':'https://links.example.test/known'});
    // Pump the microtask queue to begin the simulated URL callback.
    await Future<void>.delayed(Duration.zero);
    identity=32;
    tapped.complete(false);
    expect(await pending,false);
    expect(opened,isEmpty);
  });

  test('RC108 logout cancels pending authenticated navigation',()async{
    var identity=33;
    final auth=Completer<bool>();
    final called=<String>[];
    navigation.identityRevision=()=>identity;
    navigation.isAuthenticated=()=>auth.future;
    navigation.navigateCapability=(target,_)async{
      called.add(target);
      return true;
    };
    final old=navigation.open({'target':'content'});
    identity=34;
    navigation.clearPending();
    auth.complete(true);
    expect(await old,false);
    expect(navigation.hasPending,false);
    expect(called,isEmpty);
  });

  test('RC215 delayed security password-route result is not accepted after account switch',()async{
    var identity=73;
    final pendingRoute=Completer<bool>();
    final routed=<String>[];
    navigation.identityRevision=()=>identity;
    navigation.navigateVerifiedAppRoute=(route)async{
      routed.add(route);
      return pendingRoute.future;
    };
    final pending=navigation.openVerifiedInternalRoute('/account/reset-password');
    await Future<void>.delayed(Duration.zero);
    identity=74;
    pendingRoute.complete(true);
    expect(await pending,false);
    expect(routed,['/account/reset-password']);
  });

  test('RC215 clearing notification navigation invalidates a pending password route',()async{
    var identity=81;
    final completed=Completer<bool>();
    navigation.identityRevision=()=>identity;
    navigation.navigateVerifiedAppRoute=(_)=>completed.future;
    final pending=navigation.openVerifiedInternalRoute('/account/reset-password');
    await Future<void>.delayed(Duration.zero);
    navigation.clearPending();
    completed.complete(true);
    expect(await pending,false);
  });

  test('RC215 verified same-session password recovery route remains allowed',()async{
    var identity=91;
    navigation.identityRevision=()=>identity;
    navigation.navigateVerifiedAppRoute=(route)async=>
      route=='/account/reset-password';
    expect(await navigation.openVerifiedInternalRoute('/account/reset-password'),true);
    expect(await navigation.openVerifiedInternalRoute('//evil.test/password'),false);
  });

  test('RC108 reset detaches the prior account epoch provider',()async{
    navigation.identityRevision=()=>99;
    navigation.reset();
    expect(navigation.identityRevision,isNull);
  });
}

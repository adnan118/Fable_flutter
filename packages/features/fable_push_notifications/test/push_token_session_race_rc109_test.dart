import 'dart:async';
import 'package:dio/dio.dart';
import 'package:fable_core/fable_core.dart';
import 'package:fable_push_notifications/fable_push_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

const _tokenA='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _tokenB='bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const _tokenC='cccccccccccccccccccccccccccccccc';

FableContract _contract()=>FableContract(
  contractHash:List.filled(64,'a').join(),
  operations:{
    'push.device.register':FableOperation(
      'push.device.register','POST','/push/devices',List.filled(64,'b').join(),
      requiresAuth:true,enforceAuth:true),
    'push.device.unregister':FableOperation(
      'push.device.unregister','DELETE','/push/devices',List.filled(64,'b').join(),
      requiresAuth:true,enforceAuth:true),
  },
  featureIds:const <String>{'notifications'},
  projectName:'rc109-simulated-contract',
  selectionMode:'explicit',
);

class _FakeGateway implements BackendApiGateway {
  final calls=<String>[];
  final tokens=<String>[];
  Future<void> Function(String operation,Object? body)? onCall;
  @override
  Future<Response<dynamic>> execute(String operationId,{
    Map<String,dynamic>? path,Map<String,dynamic>? query,Object? body,
    CancelToken? cancelToken,String? ifMatch,
  })async{
    calls.add(operationId);
    if(body is Map&&body['token'] is String)tokens.add(body['token'] as String);
    await onCall?.call(operationId,body);
    return Response<dynamic>(requestOptions:RequestOptions(path:'/simulated'),statusCode:200);
  }
  @override void dispose(){}
}

class _FakePlatform implements PushTokenPlatform {
  final changes=StreamController<String>.broadcast(sync:true);
  bool permission=true,apns=true,failDelete=false;
  String? currentToken=_tokenA;
  Completer<bool>? permissionGate;
  Completer<String?>? tokenGate;
  int deletes=0,prompts=0;
  @override Future<bool> requestPermission()async{
    prompts++;
    if(permissionGate!=null)return permissionGate!.future;
    return permission;
  }
  @override Future<bool> permissionGranted()async=>permission;
  @override Future<bool> apnsReady()async=>apns;
  @override Future<String?> getToken()async{
    if(tokenGate!=null)return tokenGate!.future;
    return currentToken;
  }
  @override Stream<String> get tokenChanges=>changes.stream;
  @override Future<void> deleteToken()async{
    deletes++;
    if(failDelete)throw StateError('simulated native token-delete failure');
  }
  Future<void> close()=>changes.close();
}

class _Harness {
  _Harness({this.platform='android'}){
    service=FablePushDeviceRegistration(
      gateway:gateway,catalog:_contract(),
      bindings:const PushDeviceBindings.fable(),
      isSessionCurrent:()=>authenticated,
      platform:platform,
      tokenPlatform:native,
      identityRevision:()=>revision,
      identityEvents:events.stream,
    );
  }
  final String platform;
  final gateway=_FakeGateway();
  final native=_FakePlatform();
  final events=StreamController<FableIdentityEvent>.broadcast(sync:true);
  late final FablePushDeviceRegistration service;
  int revision=0;
  bool authenticated=true;
  void changeUser(){
    revision++;
    events.add(FableIdentityEvent(revision,true));
  }
  void logout(){
    revision++;
    authenticated=false;
    events.add(FableIdentityEvent(revision,false));
  }
  Future<void> close()async{
    await service.dispose();
    await events.close();
    await native.close();
  }
}

void main(){
  test('RC109 rejects Other Backend push without verified session epoch/events',(){
    final gateway=_FakeGateway();
    final native=_FakePlatform();
    expect(()=>FablePushDeviceRegistration(
      gateway:gateway,catalog:_contract(),
      bindings:const PushDeviceBindings.fable(),
      isSessionCurrent:()=>true,platform:'android',
      tokenPlatform:native,
    ),throwsArgumentError);
  });

  test('RC109 A to B during native permission prompt: no inherited token write',()async{
    final h=_Harness();
    try{
      h.native.permissionGate=Completer<bool>();
      final registering=h.service.requestPermissionAndRegister();
      await Future<void>.delayed(Duration.zero);
      h.changeUser();
      h.native.permissionGate!.complete(true);
      expect(await registering,false);
      expect(h.gateway.calls,isEmpty);
      await Future<void>.delayed(Duration.zero);
      expect(h.native.deletes,greaterThanOrEqualTo(1));
    }finally{await h.close();}
  });

  test('RC109 A to B while awaiting native getToken blocks old device register',()async{
    final h=_Harness();
    try{
      h.native.tokenGate=Completer<String?>();
      final registering=h.service.requestPermissionAndRegister();
      await Future<void>.delayed(Duration.zero);
      h.changeUser();
      h.native.tokenGate!.complete(_tokenA);
      expect(await registering,false);
      expect(h.gateway.calls,isEmpty);
    }finally{await h.close();}
  });

  test('RC109 late success from A never registers B or inherits A opt-in',()async{
    final h=_Harness();
    try{
      final network=Completer<void>();
      h.gateway.onCall=(op,_)=>network.future;
      final registering=h.service.requestPermissionAndRegister();
      await Future<void>.delayed(Duration.zero);
      expect(h.gateway.calls,['push.device.register']);
      h.changeUser();
      network.complete();
      expect(await registering,false);
      expect(await h.service.retryRegistrationOnResume(),false);
      expect(h.gateway.tokens,[_tokenA]);
      expect(h.native.deletes,greaterThanOrEqualTo(1));
    }finally{await h.close();}
  });

  test('RC109 refreshes serialize A->B and latest FCM token is last accepted',()async{
    final h=_Harness();
    try{
      expect(await h.service.requestPermissionAndRegister(),true);
      expect(h.service.configured,true);
      final delayed=Completer<void>();
      h.gateway.onCall=(operation,body)async{
        if(body is Map&&body['token']==_tokenB)await delayed.future;
      };
      h.native.changes.add(_tokenB);
      await Future<void>.delayed(Duration.zero);
      expect(h.gateway.tokens,[_tokenA,_tokenB]);
      h.native.changes.add(_tokenC);
      // The new token is queued but must not dispatch before B settles.
      expect(h.gateway.tokens,[_tokenA,_tokenB]);
      delayed.complete();
      await Future<void>.delayed(const Duration(milliseconds:10));
      expect(h.gateway.tokens,[_tokenA,_tokenB,_tokenC]);
    }finally{await h.close();}
  });

  test('RC109 unregister queued after registration never sends DELETE as B',()async{
    final h=_Harness();
    try{
      expect(await h.service.requestPermissionAndRegister(),true);
      final delayed=Completer<void>();
      h.gateway.onCall=(operation,body)async{
        if(body is Map&&body['token']==_tokenB)await delayed.future;
      };
      h.native.changes.add(_tokenB);
      await Future<void>.delayed(Duration.zero);
      final unreg=h.service.unregisterCurrent();
      h.changeUser();
      delayed.complete();
      await unreg;
      expect(h.gateway.calls.where((x)=>x=='push.device.unregister'),isEmpty);
      expect(h.native.deletes,greaterThanOrEqualTo(1));
    }finally{await h.close();}
  });

  test('RC109 failed native delete blocks registration until cleanup succeeds',()async{
    final h=_Harness();
    try{
      expect(await h.service.requestPermissionAndRegister(),true);
      h.native.failDelete=true;
      h.changeUser();
      await Future<void>.delayed(Duration.zero);
      await expectLater(h.service.requestPermissionAndRegister(),throwsStateError);
      expect(h.gateway.tokens,[_tokenA]);
      h.native.failDelete=false;
      h.native.currentToken=_tokenB;
      expect(await h.service.requestPermissionAndRegister(),true);
      expect(h.gateway.tokens,[_tokenA,_tokenB]);
    }finally{await h.close();}
  });

  test('RC109 iOS app resume uses APNs readiness, never re-prompts for consent',()async{
    final h=_Harness(platform:'ios');
    try{
      h.native.apns=false;
      expect(await h.service.retryRegistrationOnResume(),false);
      expect(h.native.prompts,0);
      expect(await h.service.requestPermissionAndRegister(),false);
      expect(h.native.prompts,1);
      expect(h.gateway.calls,isEmpty);
      h.native.apns=true;
      expect(await h.service.retryRegistrationOnResume(),true);
      expect(h.native.prompts,1);
      expect(h.gateway.calls,['push.device.register']);
      h.logout();
      expect(await h.service.retryRegistrationOnResume(),false);
    }finally{await h.close();}
  });
}

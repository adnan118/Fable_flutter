import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fable_core/fable_core.dart';
import 'package:fable_media/fable_media.dart';

const _asset='123e4567-e89b-42d3-a456-426614174000';
const _sessionId='123e4567-e89b-42d3-a456-426614174001';
const _openOp='project.media.playback.open';
const _refreshOp='project.media.playback.renew';
const _endOp='project.media.playback.terminate';

FableContract _contract({
  bool includeRefresh=true,bool unprotected=false,bool badPath=false,
}){
  FableOperation op(String id,String method,String path)=>FableOperation(
    id,method,path,List.filled(64,'c').join(),
    requiresAuth:!unprotected,enforceAuth:true);
  return FableContract(
    contractHash:List.filled(64,'a').join(),
    operations:{
      _openOp:op(_openOp,'POST',badPath?'/unverified/:id':'/media/:id/playback'),
      if(includeRefresh)_refreshOp:op(_refreshOp,'POST',
        '/media/playback-sessions/{id}/refresh'),
      _endOp:op(_endOp,'DELETE','/media/playback-sessions/:id'),
    },featureIds:const {'media'},projectName:'rc112-verified-fixture',
    selectionMode:'explicit',
  );
}

class _FakeSession extends FableSecureSession {
  @override int identityRevision=1;
  final events=StreamController<FableIdentityEvent>.broadcast(sync:true);
  @override Stream<FableIdentityEvent> get identityEvents=>events.stream;
  @override Future<String?> get accessToken async=>'simulated-fable-auth-token';
  @override Future<String?> get refreshToken async=>null;
  @override Future<String> installationId()async=>'0123456789abcdef0123456789abcdef';
  void replaceUser(){
    identityRevision++;
    events.add(FableIdentityEvent(identityRevision,true));
  }
  Future<void> close()=>events.close();
}

String _iso(int seconds)=>DateTime.now().toUtc()
  .add(Duration(seconds:seconds)).toIso8601String();
String _secret(String v)=>List.filled(36,v).join();

Map<String,dynamic> _openPayload({
  String? accessToken, int accessExpiresIn=90,
  bool enabled=true,String type='AUTHENTICATED_STREAM',
  String assetId=_asset,
}){
  final token=accessToken??_secret('A');
  return {
    'enabled':enabled,
    'type':type,
    'platform':'ANDROID',
    'playbackSession':{
      'id':_sessionId,'expiresAt':_iso(1200),'idleExpiresAt':_iso(600),
      'refreshEndpoint':'/media/playback-sessions/$_sessionId/refresh',
      'endEndpoint':'/media/playback-sessions/$_sessionId',
    },
    'accessToken':token,'accessTokenExpiresAt':_iso(accessExpiresIn),
    'licenseToken':_secret('L'),'licenseTokenExpiresAt':_iso(55),
    'stream':{
      'url':'/media/$assetId/content',
      'authorization':{'header':'X-Fable-Media-Token','token':token}
    },
  };
}
Map<String,dynamic> _refreshedPayload({String id=_sessionId,String asset=_asset})=> {
  'playbackSession':{
    'id':id,'assetId':asset,'expiresAt':_iso(1200),'idleExpiresAt':_iso(600),
  },
  'accessToken':_secret('R'),'accessTokenExpiresAt':_iso(90),
  'licenseToken':_secret('N'),'licenseTokenExpiresAt':_iso(50),
};

class _Harness {
  _Harness(FableContract contract):
    dio=Dio(),session=_FakeSession(){
    dio.interceptors.add(InterceptorsWrapper(onRequest:(request,handler) async {
      requests.add(request);
      if(request.path.endsWith('/playback')){
        if(!openStarted.isCompleted)openStarted.complete();
        if(blockOpen!=null)await blockOpen!.future;
      }
      if(request.path.endsWith('/refresh')){
        if(!refreshStarted.isCompleted)refreshStarted.complete();
        if(blockRefresh!=null)await blockRefresh!.future;
      }
      Map<String,dynamic> response;
      if(request.path.endsWith('/playback')){
        response=openResponse??_openPayload();
      }else if(request.path.endsWith('/refresh')){
        response=refreshResponse??_refreshedPayload();
      }else if(request.method=='DELETE'){
        response={'id':_sessionId,'status':'REVOKED'};
      }else{
        throw StateError('Unverified test operation dispatched');
      }
      handler.resolve(Response<dynamic>(requestOptions:request,
        statusCode:200,data:{'success':true,'data':response}));
    }));
    gateway=FableAuthGateway(baseUri:Uri.parse('https://api.example.test'),
      contract:contract,secureSession:session,client:dio);
  }
  final Dio dio;
  final _FakeSession session;
  final requests=<RequestOptions>[];
  final openStarted=Completer<void>();
  final refreshStarted=Completer<void>();
  Completer<void>? blockOpen,blockRefresh;
  Map<String,dynamic>? openResponse,refreshResponse;
  late final FableAuthGateway gateway;
  Future<void> close()async{
    gateway.dispose();
    await session.close();
  }
}

void main(){
  test('RC112 missing or public or mismatched signed operations disable playback before network',()async{
    for(final contract in [
      _contract(includeRefresh:false),_contract(unprotected:true),
      _contract(badPath:true),
    ]){
      final h=_Harness(contract);
      try{
        expect(()=>FableProtectedMediaPlaybackRepository(gateway:h.gateway),
          throwsStateError);
        expect(h.requests,isEmpty);
      }finally{await h.close();}
    }
  });

  test('RC112 discovers actual project operation IDs and revokes local token on end',()async{
    final h=_Harness(_contract());
    try{
      final repo=FableProtectedMediaPlaybackRepository(gateway:h.gateway);
      addTearDown(repo.dispose);
      final view=await repo.open(_asset,platform:'ANDROID');
      expect(repo.bindings.open,_openOp);
      expect(repo.bindings.refresh,_refreshOp);
      expect(repo.bindings.end,_endOp);
      expect(view.streamPath,'/media/$_asset/content');
      expect(repo.currentContentHeader(view),
        {'X-Fable-Media-Token':_secret('A')});
      expect(view.toString(),isNot(contains(_secret('A'))));
      expect(view.toString(),isNot(contains(_sessionId)));
      expect(h.requests.first.path,'/media/$_asset/playback');
      expect(h.requests.first.method,'POST');
      expect(h.requests.first.data,{'platform':'ANDROID'});

      await repo.end(view);
      expect(h.requests.last.method,'DELETE');
      expect(h.requests.last.path,'/media/playback-sessions/$_sessionId');
    }finally{await h.close();}
  });

  test('RC112 account replacement wipes all exposed stream headers',()async{
    final h=_Harness(_contract());
    try{
      final repo=FableProtectedMediaPlaybackRepository(gateway:h.gateway);
      addTearDown(repo.dispose);
      final view=await repo.open(_asset,platform:'ANDROID');
      h.session.replaceUser();
      expect(()=>repo.currentContentHeader(view),throwsStateError);
      await expectLater(repo.refresh(view),throwsStateError);
      await expectLater(repo.end(view),throwsStateError);
      expect(h.requests.length,1);
    }finally{await h.close();}
  });

  test('RC112 response with expired access token or missing protected stream fails closed',()async{
    for(final payload in [
      _openPayload(accessExpiresIn:-5),
      _openPayload(enabled:false,type:'STANDARD'),
      _openPayload(type:'MULTI_DRM'),
      {..._openPayload(),'stream':{
        'url':'https://evil.example/content?playbackToken=secret',
        'authorization':{'header':'X-Fable-Media-Token','token':_secret('A')},
      }},
    ]){
      final h=_Harness(_contract());
      try{
        h.openResponse=payload;
        final repo=FableProtectedMediaPlaybackRepository(gateway:h.gateway);
        await expectLater(repo.open(_asset,platform:'ANDROID'),
          throwsA(isA<Exception>()));
        await repo.dispose();
      }finally{await h.close();}
    }
  });

  test('RC112 end invalidates token before delayed network response',()async{
    final h=_Harness(_contract());
    try{
      final repo=FableProtectedMediaPlaybackRepository(gateway:h.gateway);
      addTearDown(repo.dispose);
      final view=await repo.open(_asset,platform:'ANDROID');
      // End triggers local token revocation immediately before DELETE dispatch.
      final ended=repo.end(view);
      expect(()=>repo.currentContentHeader(view),throwsStateError);
      await ended;
    }finally{await h.close();}
  });

  test('RC112 refresh response arriving after end cannot resurrect token',()async{
    final h=_Harness(_contract());
    try{
      final repo=FableProtectedMediaPlaybackRepository(gateway:h.gateway);
      addTearDown(repo.dispose);
      final view=await repo.open(_asset,platform:'ANDROID');
      h.blockRefresh=Completer<void>();
      final refreshing=repo.refresh(view);
      await h.refreshStarted.future;
      await repo.end(view);
      h.blockRefresh!.complete();
      await expectLater(refreshing,throwsA(isA<Exception>()));
      expect(()=>repo.currentContentHeader(view),throwsStateError);
    }finally{await h.close();}
  });

  test('RC112 stale refresh with mismatched session/asset is rejected',()async{
    final h=_Harness(_contract());
    try{
      final repo=FableProtectedMediaPlaybackRepository(gateway:h.gateway);
      addTearDown(repo.dispose);
      final view=await repo.open(_asset,platform:'ANDROID');
      h.refreshResponse=_refreshedPayload(asset:'123e4567-e89b-42d3-a456-426614174999');
      await expectLater(repo.refresh(view),throwsFormatException);
      expect(repo.currentContentHeader(view),
        {'X-Fable-Media-Token':_secret('A')});
    }finally{await h.close();}
  });
}

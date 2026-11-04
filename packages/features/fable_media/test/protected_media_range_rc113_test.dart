import 'dart:async';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fable_core/fable_core.dart';
import 'package:fable_media/fable_media.dart';

const asset='123e4567-e89b-42d3-a456-426614174000';
const playback='123e4567-e89b-42d3-a456-426614174001';
const mediaToken='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
String expiry()=>DateTime.now().toUtc().add(const Duration(minutes:10))
    .toIso8601String();

FableContract contract({bool content=true,bool isPublic=false}) {
  FableOperation op(String id,String method,String path,{bool public=false})=>
      FableOperation(id,method,path,List.filled(64,'b').join(),
          requiresAuth:!public,enforceAuth:true);
  return FableContract(contractHash:List.filled(64,'a').join(),operations:{
    'open':op('open','POST','/media/:id/playback'),
    'refresh':op('refresh','POST','/media/playback-sessions/:id/refresh'),
    'end':op('end','DELETE','/media/playback-sessions/:id'),
    if(content)'content':op('content','GET','/media/{id}/content',
        public:isPublic),
  },featureIds:const {'media'},projectName:'rc113-fixture',
    selectionMode:'explicit');
}
class FakeSession extends FableSecureSession {
  @override int identityRevision=1;
  final changes=StreamController<FableIdentityEvent>.broadcast(sync:true);
  @override Stream<FableIdentityEvent> get identityEvents=>changes.stream;
  @override Future<String?> get accessToken async=>'fake-account-access';
  @override Future<String> installationId()async=>'0123456789abcdef0123456789abcdef';
  void change(){identityRevision++;changes.add(FableIdentityEvent(identityRevision,true));}
  Future<void> close()=>changes.close();
}
class Harness {
  Harness({bool content=true,bool isPublic=false})
      :session=FakeSession(),dio=Dio(){
    dio.interceptors.add(InterceptorsWrapper(onRequest:(req,handler)async{
      requests.add(req);
      if(req.path.endsWith('/playback')){
        handler.resolve(Response<dynamic>(requestOptions:req,statusCode:200,
          data:{'data':{'enabled':true,'type':'AUTHENTICATED_STREAM',
            'platform':'ANDROID',
            'playbackSession':{'id':playback,'expiresAt':expiry(),
              'idleExpiresAt':expiry()},
            'accessToken':mediaToken,'accessTokenExpiresAt':expiry(),
            'stream':{'url':'/media/$asset/content',
              'authorization':{'header':'X-Fable-Media-Token',
                'token':mediaToken}}}}));
      }else if(req.path.endsWith('/refresh')){
        handler.resolve(Response<dynamic>(requestOptions:req,statusCode:200,
          data:{'data':{'playbackSession':{'id':playback,'assetId':asset,
            'expiresAt':expiry(),'idleExpiresAt':expiry()},
            'accessToken':List.filled(36,'r').join(),
            'accessTokenExpiresAt':expiry()}}));
      }else if(req.method=='DELETE'){
        handler.resolve(Response<dynamic>(requestOptions:req,statusCode:200,
          data:{'data':{'id':playback,'status':'REVOKED'}}));
      }else if(req.path.endsWith('/content')){
        if(!started.isCompleted)started.complete();
        final bytes=payload;
        final contentLength=lengthHeader??bytes.length;
        final headers=Headers.fromMap({
          'content-range':[rangeHeader??'bytes 0-5/6'],
          'content-length':['$contentLength'],
          'content-type':[contentTypeHeader??'video/mp4'],
          'cache-control':['private, no-store, max-age=0'],
        });
        final stream=Stream<Uint8List>.multi((controller)async{
          if(waitChunk!=null)await waitChunk!.future;
          controller.add(bytes);
          controller.close();
        });
        handler.resolve(Response<dynamic>(requestOptions:req,statusCode:status,
          headers:headers,data:ResponseBody(stream,status,headers:{
            'content-range':headers['content-range']!,
            'content-length':headers['content-length']!,
            'content-type':headers['content-type']!,
            'cache-control':headers['cache-control']!,
          })));
      }else{
        throw StateError('Unexpected request');
      }
    }));
    gateway=FableAuthGateway(baseUri:Uri.parse('https://api.example.test'),
      contract:contract(content:content,isPublic:isPublic),
      secureSession:session,client:dio);
    repository=FableProtectedMediaPlaybackRepository(gateway:gateway);
  }
  final FakeSession session;
  final Dio dio;
  late final FableAuthGateway gateway;
  late final FableProtectedMediaPlaybackRepository repository;
  final requests=<RequestOptions>[];
  final started=Completer<void>();
  Uint8List payload=Uint8List.fromList([1,2,3,4,5,6]);
  int status=206;
  int? lengthHeader;
  String? rangeHeader;
  String? contentTypeHeader;
  Completer<void>? waitChunk;
  Future<void> close()async{
    await repository.dispose();
    gateway.dispose();
    await session.close();
  }
}
void main(){
  test('RC113 missing or public content operation rejects before GET',()async{
    for(final flags in [(false,false),(true,true)]){
      final h=Harness(content:flags.$1,isPublic:flags.$2);
      try{
        final view=await h.repository.open(asset,platform:'ANDROID');
        await expectLater(h.repository.readContentRange(view,start:0,length:6),
          throwsStateError);
        expect(h.requests.where((e)=>e.path.endsWith('/content')),isEmpty);
      }finally{await h.close();}
    }
  });
  test('RC113 verified Fable auth and private media header, never URL query',()async{
    final h=Harness();
    try{
      final view=await h.repository.open(asset,platform:'ANDROID');
      final result=await h.repository.readContentRange(view,start:0,length:6);
      expect(result,[1,2,3,4,5,6]);
      final req=h.requests.last;
      expect(req.path,'/media/$asset/content');
      expect(req.method,'GET');
      expect(req.headers['Authorization'],'Bearer fake-account-access');
      expect(req.headers['X-Fable-Media-Token'],mediaToken);
      expect(req.headers['Range'],'bytes=0-5');
      expect(req.headers['Cache-Control'],'no-store');
      expect(req.headers['Accept-Encoding'],'identity');
      expect(req.responseType,ResponseType.stream);
      expect(req.followRedirects,false);
      expect(req.uri.toString(),isNot(contains(mediaToken)));
      expect(req.uri.toString(),isNot(contains('playbackToken')));
    }finally{await h.close();}
  });
  test('RC113 ignores invalid or unsupported Range response and oversized request',()async{
    for(final invalidStatus in [200,302]){
      final h=Harness();
      try{
        h.status=invalidStatus;
        final v=await h.repository.open(asset,platform:'ANDROID');
        await expectLater(h.repository.readContentRange(v,start:0,length:6),
          throwsA(anyOf(isA<StateError>(),isA<FableApiException>())));
        await expectLater(h.repository.readContentRange(v,start:0,length:524289),
          throwsArgumentError);
      }finally{await h.close();}
    }
  });
  test('RC113 malformed Range and larger response payload are rejected',()async{
    final h=Harness();
    try{
      final v=await h.repository.open(asset,platform:'ANDROID');
      h.rangeHeader='bytes 1-6/7';
      await expectLater(h.repository.readContentRange(v,start:0,length:6),
        throwsFormatException);
      h.rangeHeader=null;
      h.lengthHeader=6;
      h.payload=Uint8List.fromList([1,2,3,4,5,6,7]);
      await expectLater(h.repository.readContentRange(v,start:0,length:6),
        throwsFormatException);
    }finally{await h.close();}
  });
  test('RC113 identity change while bytes are in flight never returns old data',()async{
    final h=Harness();
    try{
      h.waitChunk=Completer<void>();
      final v=await h.repository.open(asset,platform:'ANDROID');
      final pending=h.repository.readContentRange(v,start:0,length:6);
      // Attach the rejection expectation BEFORE revocation: the guarded
      // read may fail synchronously after its next await, before teardown.
      final asserted=expectLater(pending,throwsA(anyOf(
        isA<StateError>(),isA<FableApiException>())));
      await h.started.future;
      h.session.change();
      h.waitChunk!.complete();
      await asserted;
    }finally{await h.close();}
  });
  test('RC113 end invalidates pending read even if network stream completes',()async{
    final h=Harness();
    try{
      h.waitChunk=Completer<void>();
      final v=await h.repository.open(asset,platform:'ANDROID');
      final pending=h.repository.readContentRange(v,start:0,length:6);
      final asserted=expectLater(pending,throwsA(anyOf(
        isA<StateError>(),isA<FableApiException>())));
      await h.started.future;
      await h.repository.end(v);
      h.waitChunk!.complete();
      await asserted;
    }finally{await h.close();}
  });
  test('RC113 refresh blocks old view and requires new rotated token',()async{
    final h=Harness();
    try{
      final old=await h.repository.open(asset,platform:'ANDROID');
      final fresh=await h.repository.refresh(old);
      await expectLater(h.repository.readContentRange(old,start:0,length:6),
        throwsStateError);
      expect(await h.repository.readContentRange(fresh,start:0,length:6),
        [1,2,3,4,5,6]);
      expect(h.requests.last.headers['X-Fable-Media-Token'],
        List.filled(36,'r').join());
    }finally{await h.close();}
  });
  test('RC113 cannot use playback POST operation for binary media Range',()async{
    final h=Harness();
    try{
      await expectLater(h.gateway.requestProtectedContentRange('open',
        assetId:asset,mediaToken:mediaToken,start:0,endInclusive:5),
        throwsArgumentError);
      expect(h.requests,isEmpty);
    }finally{await h.close();}
  });
  test('RC117 Fable identity event invalidates bound source before any new GET',()async{
    final h=Harness();
    try{
      final view=await h.repository.open(asset,platform:'ANDROID');
      final source=FableMediaByteSource(repository:h.repository,playback:view);
      final events=<MediaSessionInvalidation>[];
      final subscription=source.invalidations.listen(events.add);
      try{
        expect(source.isActive,true);
        h.session.change();
        expect(events,[MediaSessionInvalidation.accountChanged]);
        expect(source.isActive,false);
        await expectLater(source.read(
          const MediaByteRange(start:0,length:6)),
          throwsA(isA<MediaReadFailure>().having(
            (f)=>f.kind,'kind',MediaReadFailureKind.sessionChanged)));
        expect(h.requests.where((r)=>r.path.endsWith('/content')),isEmpty);
      }finally{
        await subscription.cancel();
        await source.close();
      }
    }finally{await h.close();}
  });

  test('RC117 refresh invalidates old source while new view can fetch bytes',()async{
    final h=Harness();
    try{
      final old=await h.repository.open(asset,platform:'ANDROID');
      final source=FableMediaByteSource(repository:h.repository,playback:old);
      final events=<MediaSessionInvalidation>[];
      final subscription=source.invalidations.listen(events.add);
      try{
        final fresh=await h.repository.refresh(old);
        expect(events,[MediaSessionInvalidation.credentialsRotated]);
        expect(source.isActive,false);
        await expectLater(source.read(const MediaByteRange(start:0,length:6)),
          throwsA(isA<MediaReadFailure>().having(
            (f)=>f.kind,'kind',MediaReadFailureKind.sessionChanged)));
        final rotated=FableMediaByteSource(repository:h.repository,playback:fresh);
        try{
          expect(rotated.isActive,true);
          expect(await rotated.read(const MediaByteRange(start:0,length:6)),
            [1,2,3,4,5,6]);
        }finally{await rotated.close();}
      }finally{
        await subscription.cancel();
        await source.close();
      }
    }finally{await h.close();}
  });

  test('RC117 end invalidation is synchronous and source close never revokes backend',()async{
    final h=Harness();
    try{
      final view=await h.repository.open(asset,platform:'ANDROID');
      final source=FableMediaByteSource(repository:h.repository,playback:view);
      final events=<MediaSessionInvalidation>[];
      final sub=source.invalidations.listen(events.add);
      try{
        await source.close();
        expect(events,[MediaSessionInvalidation.sourceClosed]);
        expect(h.requests.where((r)=>r.method=='DELETE'),isEmpty);
        expect(h.repository.isCurrentView(view),true);
      }finally{await sub.cancel();}
      final another=FableMediaByteSource(repository:h.repository,playback:view);
      final anotherEvents=<MediaSessionInvalidation>[];
      final activeSub=another.invalidations.listen(anotherEvents.add);
      try{
        final ending=h.repository.end(view);
        expect(anotherEvents,[MediaSessionInvalidation.playbackEnded]);
        expect(another.isActive,false);
        await ending;
      }finally{
        await activeSub.cancel();
        await another.close();
      }
    }finally{await h.close();}
  });

  test('RC117 repository disposal emits no-secret source invalidation',()async{
    final h=Harness();
    try{
      final view=await h.repository.open(asset,platform:'ANDROID');
      final source=FableMediaByteSource(repository:h.repository,playback:view);
      final events=<MediaSessionInvalidation>[];
      final sub=source.invalidations.listen(events.add);
      try{
        await h.repository.dispose();
        expect(events,[MediaSessionInvalidation.sourceClosed]);
        expect(source.isActive,false);
      }finally{
        await sub.cancel();
        await source.close();
      }
    }finally{await h.close();}
  });
  test('RC118 verified range metadata is immutable, typed and usable by player port',()async{
    final h=Harness();
    try{
      final view=await h.repository.open(asset,platform:'ANDROID');
      final chunk=await h.repository.readContentRangeChunk(view,start:0,length:6);
      expect(chunk.start,0);
      expect(chunk.length,6);
      expect(chunk.totalLength,6);
      expect(chunk.mimeType,'video/mp4');
      final mutable=chunk.bytes;
      mutable[0]=99;
      expect(chunk.bytes,[1,2,3,4,5,6]);
      final source=FableMediaByteSource(repository:h.repository,playback:view);
      try{
        expect(source,isA<DescribedMediaByteSource>());
        final described=await source.readChunk(
          const MediaByteRange(start:0,length:6));
        expect(described.totalLength,6);
        expect(described.mimeType,'video/mp4');
        expect(described.bytes,[1,2,3,4,5,6]);
        expect(await source.read(const MediaByteRange(start:0,length:6)),
          [1,2,3,4,5,6]);
      }finally{await source.close();}
      expect(h.requests.where((r)=>r.method=='DELETE'),isEmpty);
    }finally{await h.close();}
  });

  test('RC118 accepts verified short tail at EOF with total size',()async{
    final h=Harness();
    try{
      h.payload=Uint8List.fromList([5,6]);
      h.rangeHeader='bytes 4-5/6';
      final view=await h.repository.open(asset,platform:'ANDROID');
      final chunk=await h.repository.readContentRangeChunk(view,
        start:4,length:6);
      expect(chunk.start,4);
      expect(chunk.length,2);
      expect(chunk.totalLength,6);
      expect(chunk.bytes,[5,6]);
    }finally{await h.close();}
  });

  test('RC118 preserves nonvideo legacy ranges but refuses native playback',()async{
    for(final mime in ['image/jpeg','application/json']){
      final h=Harness();
      try{
        h.contentTypeHeader=mime;
        final view=await h.repository.open(asset,platform:'ANDROID');
        expect(await h.repository.readContentRange(view,start:0,length:6),
          [1,2,3,4,5,6]);
        final source=FableMediaByteSource(repository:h.repository,playback:view);
        try{
          expect(await source.read(const MediaByteRange(start:0,length:6)),
            [1,2,3,4,5,6]);
          await expectLater(source.readChunk(
            const MediaByteRange(start:0,length:6)),
            throwsA(isA<MediaReadFailure>().having(
              (failure)=>failure.kind,'kind',
              MediaReadFailureKind.unsupported)));
          expect(source.isActive,true);
        }finally{await source.close();}
      }finally{await h.close();}
    }
  });

  test('RC118 rejects changed metadata across one verified playback view',()async{
    final h=Harness();
    try{
      final view=await h.repository.open(asset,platform:'ANDROID');
      final source=FableMediaByteSource(repository:h.repository,playback:view);
      final invalidations=<MediaSessionInvalidation>[];
      final subscription=source.invalidations.listen(invalidations.add);
      try{
        expect((await source.readChunk(
          const MediaByteRange(start:0,length:6))).totalLength,6);
        h.rangeHeader='bytes 0-5/12';
        await expectLater(source.readChunk(
          const MediaByteRange(start:0,length:6)),
          throwsA(isA<MediaReadFailure>().having(
            (failure)=>failure.kind,'kind',
            MediaReadFailureKind.invalidResponse)));
        expect(invalidations,[MediaSessionInvalidation.resourceChanged]);
        expect(source.isActive,false);
        expect(h.repository.isCurrentView(view),false);
        final replacement=FableMediaByteSource(
          repository:h.repository,playback:view);
        try{
          expect(replacement.isActive,false);
          await expectLater(replacement.readChunk(
            const MediaByteRange(start:0,length:6)),
            throwsA(isA<MediaReadFailure>().having(
              (failure)=>failure.kind,'kind',
              MediaReadFailureKind.sessionChanged)));
        }finally{await replacement.close();}
        await expectLater(h.repository.refresh(view),throwsStateError);
        final getCount=h.requests.where((req)=>req.path.endsWith('/content')).length;
        await expectLater(source.readChunk(
          const MediaByteRange(start:0,length:6)),
          throwsA(isA<MediaReadFailure>().having(
            (failure)=>failure.kind,'kind',
            MediaReadFailureKind.sessionChanged)));
        expect(h.requests.where((req)=>req.path.endsWith('/content')).length,
          getCount);
      }finally{
        await subscription.cancel();
        await source.close();
      }
    }finally{await h.close();}
  });

}

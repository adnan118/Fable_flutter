import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:fable_core/fable_core.dart';
import 'package:fable_media/fable_media.dart';
import 'package:flutter_test/flutter_test.dart';

const _id='123e4567-e89b-42d3-a456-426614174000';
const _url='https://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.r2.cloudflarestorage.com/bucket/file'
    '?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Signature=abc';

FableContract _contract(){
  const roles=MediaUploadBindings.fable();
  final methods=<String,String>{
    roles.prepare:'POST',roles.status:'GET',roles.chunk:'POST',
    roles.partUrl:'POST',roles.partAck:'POST',
    roles.complete:'POST',roles.abort:'DELETE',
  };
  // RC157: fixture paths must be authentic Fable Media controller routes.
  // Route safety is enforced even when the gateway itself is a test double.
  const paths=<String,String>{
    'media.upload.prepare':'/media/uploads/prepare',
    'media.upload.status':'/media/uploads/{id}',
    'media.upload.chunk':'/media/uploads/{id}/chunk',
    'media.upload.partUrl':'/media/uploads/{id}/parts/{partNumber}/url',
    'media.upload.partAck':'/media/uploads/{id}/parts/{partNumber}/complete',
    'media.upload.complete':'/media/uploads/{id}/complete',
    'media.upload.abort':'/media/uploads/{id}',
  };
  return FableContract(
    contractHash:List.filled(64,'a').join(),
    operations:{for(final e in methods.entries)e.key:FableOperation(
      e.key,e.value,paths[e.key]!,List.filled(64,'b').join(),
      requiresAuth:true,enforceAuth:true)},
    featureIds:const <String>{'media'},
    projectName:'simulated-rc110',selectionMode:'explicit',
  );
}

class _FakeMediaGateway implements BackendApiGateway {
  final calls=<String>[];
  int size=8,bytes=0;
  String strategy='LOCAL_RESUMABLE';
  Future<void> Function(String id)? waitBeforeReply;
  void Function(String id)? onDispatch;
  Map<String,dynamic> get state=> <String,dynamic>{
    'id':_id,'sizeBytes':size,'status':bytes==size?'UPLOADING':'UPLOADING',
    'upload':{'strategy':strategy,
      'chunkSizeBytes':strategy=='LOCAL_RESUMABLE'?4:5*1024*1024},
    'progress':{'uploadedBytes':bytes,'totalBytes':size,
      'percentage':size==0?0:bytes*100/size},
    'nextOffsetBytes':bytes,
    'parts':<Object>[],
  };
  @override
  Future<Response<dynamic>> execute(String id,{
    Map<String,dynamic>? path,Map<String,dynamic>? query,Object? body,
    CancelToken? cancelToken,String? ifMatch,
  })async{
    calls.add(id);
    onDispatch?.call(id);
    await waitBeforeReply?.call(id);
    Map<String,dynamic> payload;
    switch(id){
      case 'media.upload.prepare':
      case 'media.upload.status':
      case 'media.upload.abort':
      case 'media.upload.complete':
        payload=state;
      case 'media.upload.chunk':
        if(body is! FormData)throw StateError('Expected streamed chunk');
        final offset=int.parse(body.fields.firstWhere((x)=>x.key=='offset').value);
        bytes=offset+body.files.first.value.length;
        payload=state;
      case 'media.upload.partUrl':
        payload={'url':_url,'expectedSizeBytes':size};
      case 'media.upload.partAck':
        bytes=size;
        payload=state;
      default:
        throw StateError('Unknown media operation $id');
    }
    return Response<dynamic>(requestOptions:RequestOptions(path:'/simulated'),
      data:payload,statusCode:200);
  }
  @override void dispose(){}
}

class _DelayedR2 implements MediaPresignedPartTransport {
  final delay=Completer<String>();
  final started=Completer<void>();
  int puts=0;
  @override Future<String> putPart(Uri url,File file,int start,int end,
      {CancelToken? cancelToken})async {
    CloudflareR2PartTransport.validatePresignedUri(url);
    puts++;
    if(!started.isCompleted)started.complete();
    return delay.future;
  }
  @override void dispose(){}
}

Future<void> _withFile(Future<void> Function(File) test)async{
  final dir=await Directory.systemTemp.createTemp('fable-rc110-');
  final file=File('${dir.path}/sample.jpg');
  try{
    await file.writeAsBytes(List<int>.filled(8,42));
    await test(file);
  }finally{
    await dir.delete(recursive:true);
  }
}

void main(){
  late _FakeMediaGateway gateway;
  late int epoch;
  late bool authenticated;
  late MediaUploadRepository repository;
  setUp((){
    gateway=_FakeMediaGateway();
    epoch=1;authenticated=true;
    repository=MediaUploadRepository(gateway:gateway,catalog:_contract(),
      bindings:const MediaUploadBindings.fable(),
      identityRevision:()=>epoch,isSessionCurrent:()=>authenticated);
  });

  test('RC110 Other Backend requires a verified session epoch and active session',(){
    expect(()=>MediaUploadRepository(
      gateway:gateway,catalog:_contract(),
      bindings:const MediaUploadBindings.fable()),throwsArgumentError);
  });

  test('RC110 A to B during delayed prepare never saves checkpoint or starts chunks',()async{
    await _withFile((file)async{
      final pending=Completer<void>();
      gateway.waitBeforeReply=(id)=>id=='media.upload.prepare'
        ?pending.future:Future<void>.value();
      var persisted=false;
      final dispatched=Completer<void>();
      gateway.onDispatch=(id){if(id=='media.upload.prepare'&&!dispatched.isCompleted)dispatched.complete();};
      final start=repository.start(file,kind:'IMAGE',mimeType:'image/jpeg',
        saveCheckpoint:(_ )async{persisted=true;});
      await dispatched.future;
      expect(gateway.calls,contains('media.upload.prepare'));
      epoch++;pending.complete();
      await expectLater(start,throwsStateError);
      expect(persisted,false);
      expect(gateway.calls,hasLength(1));
    });
  });

  test('RC110 delayed status from A cannot emit progress or start a chunk for B',()async{
    await _withFile((file)async{
      final waiting=Completer<void>();
      gateway.waitBeforeReply=(id)=>id=='media.upload.status'
        ?waiting.future:Future<void>.value();
      final progress=<MediaUploadProgress>[];
      final prepare=repository.prepare(file,kind:'IMAGE',mimeType:'image/jpeg');
      await prepare;
      final dispatched=Completer<void>();
      gateway.onDispatch=(id){if(id=='media.upload.status'&&!dispatched.isCompleted)dispatched.complete();};
      final resume=repository.start(file,kind:'IMAGE',mimeType:'image/jpeg',
        saveCheckpoint:(_ )async{},onProgress:progress.add);
      await dispatched.future;
      expect(gateway.calls,contains('media.upload.status'));
      epoch++;waiting.complete();
      await expectLater(resume,throwsStateError);
      expect(progress,isEmpty);
      expect(gateway.calls.where((x)=>x=='media.upload.chunk'),isEmpty);
    });
  });

  test('RC110 late local chunk success cannot acknowledge progress or complete after switch',()async{
    await _withFile((file)async{
      final delayed=Completer<void>();
      gateway.waitBeforeReply=(id)=>id=='media.upload.chunk'
        ?delayed.future:Future<void>.value();
      final progress=<MediaUploadProgress>[];
      final dispatched=Completer<void>();
      gateway.onDispatch=(id){if(id=='media.upload.chunk'&&!dispatched.isCompleted)dispatched.complete();};
      final operation=repository.start(file,kind:'IMAGE',mimeType:'image/jpeg',
        saveCheckpoint:(_ )async{},onProgress:progress.add);
      await dispatched.future;
      expect(gateway.calls,contains('media.upload.chunk'));
      epoch++;delayed.complete();
      await expectLater(operation,throwsStateError);
      expect(progress.length,1); // Only initial SERVER-confirmed progress.
      expect(gateway.calls.where((x)=>x=='media.upload.complete'),isEmpty);
    });
  });

  test('RC110 cancellation after initial status blocks any chunk dispatch',()async{
    await _withFile((file)async{
      final token=CancelToken();
      final progress=<MediaUploadProgress>[];
      await expectLater(repository.start(file,kind:'IMAGE',mimeType:'image/jpeg',
        saveCheckpoint:(_ )async{},cancelToken:token,
        onProgress:(p){progress.add(p);token.cancel('pause');}),throwsStateError);
      expect(progress.length,1);
      expect(gateway.calls.where((x)=>x=='media.upload.chunk'),isEmpty);
    });
  });

  test('RC110 user switch while saving durable checkpoint blocks transfer',()async{
    await _withFile((file)async{
      final pending=Completer<void>();
      final checkpointEntered=Completer<void>();
      final operation=repository.start(file,kind:'IMAGE',mimeType:'image/jpeg',
        saveCheckpoint:(_ )async{
          checkpointEntered.complete();
          await pending.future;
        });
      await checkpointEntered.future;
      epoch++;pending.complete();
      await expectLater(operation,throwsStateError);
      expect(gateway.calls.where((x)=>x=='media.upload.status'),isEmpty);
    });
  });

  test('RC110 intent-to-cancel persists but old session cannot send DELETE as B',()async{
    final pending=Completer<void>();
    var saved=false;
    final cancellation=repository.cancel(_id,persistCancelIntent:(_ )async{
      saved=true;
      await pending.future;
    });
    await Future<void>.delayed(Duration.zero);
    epoch++;pending.complete();
    await expectLater(cancellation,throwsStateError);
    expect(saved,true);
    expect(gateway.calls.where((x)=>x=='media.upload.abort'),isEmpty);
  });

  test('RC110 R2 part completed after account switch does not send part ACK',()async{
    await _withFile((file)async{
      gateway.strategy='S3_MULTIPART';
      final r2=_DelayedR2();
      repository=MediaUploadRepository(gateway:gateway,catalog:_contract(),
        bindings:const MediaUploadBindings.fable(),
        partTransport:r2,
        identityRevision:()=>epoch,isSessionCurrent:()=>authenticated);
      final operation=repository.start(file,kind:'IMAGE',mimeType:'image/jpeg',
        saveCheckpoint:(_ )async{});
      await r2.started.future;
      expect(r2.puts,1);
      epoch++;r2.delay.complete('"etag"');
      await expectLater(operation,throwsStateError);
      expect(gateway.calls.where((x)=>x=='media.upload.partAck'),isEmpty);
      expect(gateway.calls.where((x)=>x=='media.upload.complete'),isEmpty);
    });
  });

  test('RC110 stable account still completes local upload using server-confirmed offsets',()async{
    await _withFile((file)async{
      final samples=<MediaUploadProgress>[];
      final result=await repository.start(file,kind:'IMAGE',mimeType:'image/jpeg',
        saveCheckpoint:(_ )async{},onProgress:samples.add);
      expect(result['id'],_id);
      expect(samples.last.uploadedBytes,8);
      expect(gateway.calls.where((x)=>x=='media.upload.chunk').length,2);
      expect(gateway.calls.last,'media.upload.complete');
    });
  });
}

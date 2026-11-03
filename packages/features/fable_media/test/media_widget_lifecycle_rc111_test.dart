import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fable_core/fable_core.dart';
import 'package:fable_media/fable_media.dart';

const _id='123e4567-e89b-42d3-a456-426614174000';
final _scopeA=List.filled(64,'a').join();
final _scopeB=List.filled(64,'b').join();

FableContract _catalog(){
  const names=MediaUploadBindings.fable();
  final methods={
    names.prepare:'POST',names.status:'GET',names.chunk:'POST',
    names.partUrl:'POST',names.partAck:'POST',names.complete:'POST',
    names.abort:'DELETE',
  };
  return FableContract(
    contractHash:List.filled(64,'a').join(),
    operations:{for(final e in methods.entries)e.key:FableOperation(
      e.key,e.value,'/verified/${e.key}',List.filled(64,'b').join(),
      requiresAuth:true,enforceAuth:true)},
    featureIds:const {'media'},projectName:'rc111-fixture',
    selectionMode:'explicit',
  );
}

class _Gateway implements BackendApiGateway {
  final calls=<String>[];
  final started=StreamController<String>.broadcast(sync:true);
  final prepareDispatched=Completer<void>();
  Completer<void>? blockPrepare;
  int total=8,bytes=0;

  @override Future<Response<dynamic>> execute(String id,{
    Map<String,dynamic>? path,Map<String,dynamic>? query,Object? body,
    CancelToken? cancelToken,String? ifMatch,
  })async{
    calls.add(id);
    started.add(id);
    if(id=='media.upload.prepare'&&!prepareDispatched.isCompleted){
      prepareDispatched.complete();
    }
    if(id=='media.upload.prepare' && blockPrepare!=null){
      await blockPrepare!.future;
    }
    if(id=='media.upload.chunk'&&body is FormData){
      final offset=int.parse(body.fields.firstWhere((v)=>v.key=='offset').value);
      bytes=offset+body.files.first.value.length;
    }
    final state=<String,dynamic>{
      'id':_id,'status':'UPLOADING','sizeBytes':total,
      'upload':{'strategy':'LOCAL_RESUMABLE','chunkSizeBytes':4},
      'progress':{'uploadedBytes':bytes,'totalBytes':total,
        'percentage':bytes*100/total},
      'nextOffsetBytes':bytes,
    };
    return Response<dynamic>(requestOptions:RequestOptions(path:'/fixture'),
      statusCode:200,data:state);
  }
  @override void dispose(){}
  Future<void> close()=>started.close();
}

class _Store extends MediaUploadCheckpointStore {
  _Store(String scope):super(scope);
  MediaUploadCheckpoint? value;
  Completer<MediaUploadCheckpoint?>? readWait;
  int clears=0,saves=0,reads=0;
  @override Future<MediaUploadCheckpoint?> read()async{
    reads++;
    if(readWait!=null)return readWait!.future;
    return value;
  }
  @override Future<void> save(MediaUploadCheckpoint checkpoint)async{
    saves++;
    value=checkpoint;
  }
  @override Future<void> clear()async{
    clears++;
    value=null;
  }
}

class _Context {
  _Context(String scope,{required this.gateway}):store=_Store(scope){
    repo=MediaUploadRepository(gateway:gateway,catalog:_catalog(),
      bindings:const MediaUploadBindings.fable(),
      identityRevision:()=>epoch,isSessionCurrent:()=>authenticated,
      identityEvents:events.stream);
  }
  final _Gateway gateway;
  final _Store store;
  final events=StreamController<FableIdentityEvent>.broadcast(sync:true);
  late final MediaUploadRepository repo;
  int epoch=1;
  bool authenticated=true;
  void changeIdentity(){
    epoch++;
    events.add(FableIdentityEvent(epoch,true));
  }
  Future<void> dispose()async{
    await events.close();
    await gateway.close();
  }
}

Future<List<File>> _files(WidgetTester tester)async{
  // WidgetTester is FakeAsync; native filesystem futures need a real async
  // zone or the test can stall before the upload widget is even mounted.
  final files=await tester.runAsync(()async{
    final root=await Directory.systemTemp.createTemp('rc111-media-ui-');
    addTearDown(()=>root.delete(recursive:true));
    final x=File('${root.path}/a.jpg');
    final y=File('${root.path}/b.jpg');
    await x.writeAsBytes(List<int>.filled(8,1));
    await y.writeAsBytes(List<int>.filled(8,2));
    return [x,y];
  });
  if(files==null)throw StateError('Real filesystem simulation unavailable');
  return files;
}

Widget _page(File file,_Context context,{void Function(Map<String,dynamic>)? onCompleted})=>
  MaterialApp(home:Scaffold(body:SingleChildScrollView(
    child:FableResumableUploadCard(file:file,repository:context.repo,
      checkpoints:context.store,kind:'IMAGE',mimeType:'image/jpeg',
      onCompleted:onCompleted))));

void main(){
  testWidgets('RC111 old prepare reply cannot complete after file and repository replacement',
    (tester)async{
    final files=await _files(tester);
    final a=_Context(_scopeA,gateway:_Gateway());
    final b=_Context(_scopeB,gateway:_Gateway());
    addTearDown(()async{await a.dispose();await b.dispose();});
    final pending=Completer<void>();
    a.gateway.blockPrepare=pending;
    var oldCompletions=0;
    var newCompletions=0;
    final newFinished=Completer<void>();
    await tester.pumpWidget(_page(files[0],a,
      onCompleted:(_)=>oldCompletions++));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Upload'));
    await tester.pump();
    await tester.runAsync(()=>a.gateway.prepareDispatched.future);
    expect(a.gateway.calls,contains('media.upload.prepare'));

    await tester.pumpWidget(_page(files[1],b,
      onCompleted:(_){
        newCompletions++;
        if(!newFinished.isCompleted)newFinished.complete();
      }));
    await tester.pumpAndSettle();
    pending.complete();
    await tester.pumpAndSettle();
    expect(oldCompletions,0);
    expect(newCompletions,0);
    expect(b.store.clears,0);
    expect(find.text('Upload complete'),findsNothing);
    expect(find.text('Upload'),findsOneWidget);

    await tester.tap(find.text('Upload'));
    await tester.pump();
    await tester.runAsync(()=>newFinished.future);
    await tester.pumpAndSettle();
    expect(newCompletions,1);
    expect(find.text('Upload complete'),findsOneWidget);
  });

  testWidgets('RC111 identity event revokes pending upload and blocks reuse of old account store',
    (tester)async{
    final files=await _files(tester);
    final a=_Context(_scopeA,gateway:_Gateway());
    addTearDown(a.dispose);
    a.gateway.blockPrepare=Completer<void>();
    var completions=0;
    await tester.pumpWidget(_page(files[0],a,
      onCompleted:(_)=>completions++));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Upload'));
    await tester.pump();
    await tester.runAsync(()=>a.gateway.prepareDispatched.future);
    expect(a.gateway.calls,contains('media.upload.prepare'));

    a.changeIdentity();
    await tester.pump();
    expect(find.text('Upload'),findsNothing);
    expect(find.textContaining('Account changed.'),findsOneWidget);
    a.gateway.blockPrepare!.complete();
    await tester.pumpAndSettle();
    expect(completions,0);
    expect(a.store.saves,0);
  });

  testWidgets('RC111 stale checkpoint restore cannot update a new file/store',
    (tester)async{
    final files=await _files(tester);
    final a=_Context(_scopeA,gateway:_Gateway());
    final b=_Context(_scopeB,gateway:_Gateway());
    addTearDown(()async{await a.dispose();await b.dispose();});
    a.store.readWait=Completer<MediaUploadCheckpoint?>();
    await tester.pumpWidget(_page(files[0],a));
    await tester.pump();
    expect(a.store.reads,1);
    await tester.pumpWidget(_page(files[1],b));
    await tester.pumpAndSettle();
    a.store.readWait!.complete(MediaUploadCheckpoint(
      sessionId:_id,sha256:List.filled(64,'a').join(),sizeBytes:8));
    await tester.pumpAndSettle();
    expect(find.text('Resume'),findsNothing);
    expect(find.text('Upload'),findsOneWidget);
    expect(b.store.clears,0);
  });

  testWidgets('RC111 old cancel never clears replacement account checkpoint',
    (tester)async{
    final files=await _files(tester);
    final a=_Context(_scopeA,gateway:_Gateway());
    final b=_Context(_scopeB,gateway:_Gateway());
    addTearDown(()async{await a.dispose();await b.dispose();});
    a.gateway.blockPrepare=Completer<void>();
    await tester.pumpWidget(_page(files[0],a));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Upload'));
    await tester.pump();
    await tester.runAsync(()=>a.gateway.prepareDispatched.future);
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    await tester.pumpWidget(_page(files[1],b));
    await tester.pumpAndSettle();
    a.gateway.blockPrepare!.complete();
    await tester.pumpAndSettle();
    expect(a.store.clears,greaterThanOrEqualTo(1));
    expect(b.store.clears,0);
    expect(find.text('Upload'),findsOneWidget);
  });

  testWidgets('RC111 Other Backend without Auth events must not show upload actions',
    (tester)async{
    final files=await _files(tester);
    final gateway=_Gateway();
    addTearDown(gateway.close);
    final store=_Store(_scopeA);
    final repo=MediaUploadRepository(gateway:gateway,catalog:_catalog(),
      bindings:const MediaUploadBindings.fable(),
      identityRevision:()=>1,isSessionCurrent:()=>true);
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:
      FableResumableUploadCard(file:files[0],repository:repo,
        checkpoints:store,kind:'IMAGE',mimeType:'image/jpeg'))));
    await tester.pumpAndSettle();
    expect(find.textContaining('Verified authentication change events'),findsOneWidget);
    expect(find.text('Upload'),findsNothing);
    expect(gateway.calls,isEmpty);
  });
}

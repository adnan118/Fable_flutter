import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fable_core/fable_core.dart';
import 'package:fable_media/fable_media.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

const _id='123e4567-e89b-42d3-a456-426614174000';
final _scopeA=List.filled(64,'a').join();
final _scopeB=List.filled(64,'b').join();

FableContract _catalog(){
  const ops=MediaUploadBindings.fable();
  final methods=<String,String>{
    ops.prepare:'POST',ops.status:'GET',ops.chunk:'POST',ops.partUrl:'POST',
    ops.partAck:'POST',ops.complete:'POST',ops.abort:'DELETE',
  };
  return FableContract(
    contractHash:List.filled(64,'a').join(),
    operations:{for(final e in methods.entries)e.key:FableOperation(
      e.key,e.value,'/verified/${e.key}',List.filled(64,'b').join(),
      requiresAuth:true,enforceAuth:true)},
    featureIds:const {'media'},projectName:'rc111-widget-simulation',
    selectionMode:'explicit',
  );
}

class _Gateway implements BackendApiGateway {
  final calls=<String>[];
  @override Future<Response<dynamic>> execute(String id,{
    Map<String,dynamic>? path,Map<String,dynamic>? query,Object? body,
    CancelToken? cancelToken,String? ifMatch,
  })async{
    calls.add(id);
    throw StateError('Widget tests must not perform HTTP');
  }
  @override void dispose(){}
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

/// No native filesystem/HTTP calls in WidgetTester. RC110 separately tests
/// real local File hashing and chunk/R2 transport using a fake gateway.
class _DelayedRepository extends MediaUploadRepository {
  _DelayedRepository({required super.gateway,required super.catalog,
    required super.bindings,required super.identityRevision,
    required super.isSessionCurrent,super.identityEvents});
  final result=Completer<Map<String,dynamic>>();
  int starts=0,resumes=0,cancels=0;
  void complete()=>result.complete({'id':_id,'status':'COMPLETED'});
  @override Future<Map<String,dynamic>> start(File file,{
    required String kind,required String mimeType,
    String? purpose,String visibility='PRIVATE',
    required Future<void> Function(MediaUploadCheckpoint) saveCheckpoint,
    void Function(MediaUploadProgress)? onProgress,
    CancelToken? cancelToken,
  })async{
    starts++;
    onProgress?.call(const MediaUploadProgress(0,8,0));
    return result.future;
  }
  @override Future<Map<String,dynamic>> resume(File file,
    MediaUploadCheckpoint checkpoint,{
    void Function(MediaUploadProgress)? onProgress,
    CancelToken? cancelToken,
  })async{
    resumes++;
    return result.future;
  }
  @override Future<Map<String,dynamic>> cancel(String id,{
    required Future<void> Function(String sessionId) persistCancelIntent,
  })async{
    cancels++;
    await persistCancelIntent(id);
    return {'id':id,'status':'ABORTED'};
  }
}

class _Context {
  _Context(String scope,{this.withEvents=true}):store=_Store(scope){
    repo=_DelayedRepository(gateway:gateway,catalog:_catalog(),
      bindings:const MediaUploadBindings.fable(),
      identityRevision:()=>epoch,isSessionCurrent:()=>authenticated,
      identityEvents:withEvents?events.stream:null);
  }
  final bool withEvents;
  final gateway=_Gateway();
  final _Store store;
  final events=StreamController<FableIdentityEvent>.broadcast(sync:true);
  late final _DelayedRepository repo;
  int epoch=1;
  bool authenticated=true;
  void changeIdentity(){
    epoch++;
    events.add(FableIdentityEvent(epoch,true));
  }
  Future<void> close()=>events.close();
}

Widget _page(String filename,_Context context,{
  void Function(Map<String,dynamic>)? onCompleted,
})=>MaterialApp(home:Scaffold(body:SingleChildScrollView(
  child:FableResumableUploadCard(file:File(filename),
    repository:context.repo,checkpoints:context.store,
    kind:'IMAGE',mimeType:'image/jpeg',onCompleted:onCompleted))));

void main(){
  setUp((){
    SharedPreferencesAsyncPlatform.instance=
      InMemorySharedPreferencesAsync.empty();
  });

  testWidgets('RC111 old prepare reply cannot complete after file and repository replacement',
    (tester)async{
    final a=_Context(_scopeA);
    final b=_Context(_scopeB);
    addTearDown(()async{await a.close();await b.close();});
    var oldCompletions=0,newCompletions=0;
    await tester.pumpWidget(_page('old.jpg',a,
      onCompleted:(_)=>oldCompletions++));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Upload'));
    await tester.pump();
    expect(a.repo.starts,1);

    await tester.pumpWidget(_page('new.jpg',b,
      onCompleted:(_)=>newCompletions++));
    await tester.pumpAndSettle();
    a.repo.complete();
    await tester.pumpAndSettle();
    expect(oldCompletions,0);
    expect(b.store.clears,0);
    expect(find.text('Upload complete'),findsNothing);
    expect(find.text('Upload'),findsOneWidget);

    await tester.tap(find.text('Upload'));
    await tester.pump();
    expect(b.repo.starts,1);
    b.repo.complete();
    await tester.pumpAndSettle();
    expect(newCompletions,1);
    expect(find.text('Upload complete'),findsOneWidget);
  });

  testWidgets('RC111 identity event revokes pending upload and blocks reuse of old account store',
    (tester)async{
    final a=_Context(_scopeA);
    addTearDown(a.close);
    var completions=0;
    await tester.pumpWidget(_page('old.jpg',a,
      onCompleted:(_)=>completions++));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Upload'));
    await tester.pump();
    expect(a.repo.starts,1);

    a.changeIdentity();
    await tester.pump();
    expect(find.text('Upload'),findsNothing);
    expect(find.textContaining('Account changed.'),findsOneWidget);
    a.repo.complete();
    await tester.pumpAndSettle();
    expect(completions,0);
    expect(a.store.saves,0);
  });

  testWidgets('RC111 stale checkpoint restore cannot update a new file/store',
    (tester)async{
    final a=_Context(_scopeA);
    final b=_Context(_scopeB);
    addTearDown(()async{await a.close();await b.close();});
    a.store.readWait=Completer<MediaUploadCheckpoint?>();
    await tester.pumpWidget(_page('old.jpg',a));
    await tester.pump();
    expect(a.store.reads,1);
    await tester.pumpWidget(_page('new.jpg',b));
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
    final a=_Context(_scopeA);
    final b=_Context(_scopeB);
    addTearDown(()async{await a.close();await b.close();});
    await tester.pumpWidget(_page('old.jpg',a));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Upload'));
    await tester.pump();
    expect(a.repo.starts,1);
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    await tester.pumpWidget(_page('new.jpg',b));
    await tester.pumpAndSettle();
    a.repo.complete();
    await tester.pumpAndSettle();
    expect(a.store.clears,greaterThanOrEqualTo(1));
    expect(b.store.clears,0);
    expect(find.text('Upload'),findsOneWidget);
  });

  testWidgets('RC111 Other Backend without Auth events must not show upload actions',
    (tester)async{
    final ctx=_Context(_scopeA,withEvents:false);
    addTearDown(ctx.close);
    await tester.pumpWidget(_page('old.jpg',ctx));
    await tester.pumpAndSettle();
    expect(find.textContaining('Verified authentication change events'),findsOneWidget);
    expect(find.text('Upload'),findsNothing);
    expect(ctx.gateway.calls,isEmpty);
  });
}

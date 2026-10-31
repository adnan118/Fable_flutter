import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:fable_core/fable_core.dart';
import 'package:fable_content/fable_content.dart';

class FakeGateway implements BackendApiGateway {
  String? lastId;
  Map<String, dynamic>? lastPath, lastQuery;
  Object? lastBody;
  int calls = 0;
  @override
  Future<Response<dynamic>> execute(String operationId, {
    Map<String, dynamic>? path, Map<String, dynamic>? query,
    Object? body, CancelToken? cancelToken, String? ifMatch,
  }) async {
    calls++;
    lastId = operationId; lastPath = path; lastQuery = query; lastBody = body;
    return Response(requestOptions: RequestOptions(path: '/verified'), data: {
      'page': {'id': 'page1', 'slug': 'privacy', 'requiresAcceptance': true},
      'version': {'id': 'v2'},
      'locale': {'resolved': 'ar'},
      'title': 'سياسة الخصوصية',
      'blocks': [
        {'id': 'b1', 'type': 'paragraph', 'data': {'content': 'نص معتمد'}},
        {'id': 'b2', 'type': 'unknown', 'data': {'anything': 'ignored'}},
      ]
    });
  }
  @override void dispose() {}
}

class _MutablePublishedGateway implements BackendApiGateway {
 String version='v1';
 bool failReads=false;
 final accepted=<String>[];
 int reads=0;
 @override Future<Response<dynamic>> execute(String operationId,{
  Map<String,dynamic>? path,Map<String,dynamic>? query,
  Object? body,CancelToken? cancelToken,String? ifMatch,
 }) async {
  if(operationId=='content.page.read'){
   reads++;
   if(failReads)throw StateError('Unverified published version');
   return Response(requestOptions:RequestOptions(path:'/verified'),data:{
    'page':{'id':'legal-page','slug':'privacy-policy',
      'requiresAcceptance':true},
    'version':{'id':version},
    'locale':{'resolved':'en'},
    'title':'Privacy policy',
    'blocks':[{'id':'b1','type':'paragraph',
      'data':{'content':'Version $version'}}],
   });
  }
  if(operationId=='content.page.accept'){
   final input=body;
   if(input is! Map||input['versionId']!=version)
    throw StateError('Current version mismatch');
   accepted.add(input['versionId'] as String);
   return Response(requestOptions:RequestOptions(path:'/verified'),data:{});
  }
  throw StateError('Unexported operation: $operationId');
 }
 @override void dispose(){}
}

class _PublishedIndexGateway implements BackendApiGateway {
 Object? reply;
 String? lastId;
 int calls=0;
 _PublishedIndexGateway(this.reply);
 @override Future<Response<dynamic>> execute(String operationId,{
  Map<String,dynamic>? path,Map<String,dynamic>? query,
  Object? body,CancelToken? cancelToken,String? ifMatch,
 })async{
  calls++;lastId=operationId;
  return Response(requestOptions:RequestOptions(path:'/verified'),data:reply);
 }
 @override void dispose(){}
}

void main() {
  test('read uses explicit operation ID and locale', () async {
    final fake = FakeGateway();
    final repo = FablePublishedContentRepository(fake, readOperationId: 'docs.read');
    await expectLater(repo.read('../admin'), throwsArgumentError);
    final doc = await repo.read('privacy', locale: 'ar');
    expect(fake.lastId, 'docs.read');
    expect(fake.lastPath, {'slug': 'privacy'});
    expect(fake.lastQuery, {'locale': 'ar'});
    expect(doc.title, 'سياسة الخصوصية');
    expect(doc.blocks.length, 2);
    expect(doc.requiresAcceptance, true);
    expect(fake.calls, 1);
  });
  test('explicit acceptance submits exact published version', () async {
    final fake = FakeGateway();
    final repo = FablePublishedContentRepository(fake, acceptOperationId: 'docs.accept');
    final doc = await repo.read('privacy');
    expect(fake.calls, 1);
    await repo.accept(doc);
    expect(fake.calls, 2);
    expect(fake.lastId, 'docs.accept');
    expect(fake.lastPath, {'pageId': 'page1'});
    expect(fake.lastBody, {'versionId': 'v2'});
  });
  test('bad response never silently rendered', () {
    expect(() => FablePublishedDocument.fromPayload({'blocks': []}), throwsFormatException);
  });
  testWidgets('published policy revalidates on signal and app resume; version acceptance never carries over',(tester)async{
    final api=_MutablePublishedGateway();
    final hints=StreamController<Object?>.broadcast();
    final identity=StreamController<Object?>.broadcast();
    addTearDown(hints.close);
    addTearDown(identity.close);
    final repo=FablePublishedContentRepository(api);
    await tester.pumpWidget(MaterialApp(home:FablePublishedContentPage(
      slug:'privacy-policy',repository:repo,
      refreshSignals:hints.stream,identitySignals:identity.stream,
    )));
    await tester.pumpAndSettle();
    expect(find.text('Version v1'),findsOneWidget);
    await tester.tap(find.text('Accept published version'));
    await tester.pumpAndSettle();
    expect(api.accepted,['v1']);
    expect(find.text('Accept published version'),findsNothing);

    api.version='v2';
    hints.add('backend-published');
    await tester.pumpAndSettle();
    expect(find.text('Version v2'),findsOneWidget);
    expect(find.text('A new published version is available. Review it before accepting.'),findsOneWidget);
    expect(find.text('Accept published version'),findsOneWidget);
    await tester.tap(find.text('Accept published version'));
    await tester.pumpAndSettle();
    expect(api.accepted,['v1','v2']);

    // Same published version but another account must confirm separately.
    identity.add('new-identity');
    await tester.pumpAndSettle();
    expect(find.text('Accept published version'),findsOneWidget);

    api.version='v3';
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('Version v3'),findsOneWidget);
    expect(find.text('Accept published version'),findsOneWidget);
    expect(api.reads,greaterThanOrEqualTo(4));
  });

  testWidgets('failed revalidation does not permit approving a stale policy',(tester)async{
    final api=_MutablePublishedGateway();
    final hints=StreamController<Object?>.broadcast();
    addTearDown(hints.close);
    final repo=FablePublishedContentRepository(api);
    await tester.pumpWidget(MaterialApp(home:FablePublishedContentPage(
      slug:'privacy-policy',repository:repo,refreshSignals:hints.stream,
    )));
    await tester.pumpAndSettle();
    expect(find.text('Version v1'),findsOneWidget);
    api.version='v2';api.failReads=true;
    hints.add('new-policy');
    await tester.pumpAndSettle();
    final button=tester.widget<FilledButton>(find.widgetWithText(
      FilledButton,'Accept published version'));
    expect(button.onPressed,isNull);
    expect(api.accepted,isEmpty);
    api.failReads=false;
    await tester.tap(find.text('Retry verification'));
    await tester.pumpAndSettle();
    expect(find.text('Version v2'),findsOneWidget);
    expect(tester.widget<FilledButton>(find.widgetWithText(
      FilledButton,'Accept published version')).onPressed,isNotNull);
  });

  test('published index is opt-in and preserves contract-bound operation ID',()async{
    final entry={'slug':'privacy-policy',
      'revision':'550e8400-e29b-41d4-a716-446655440001','version':2};
    final api=_PublishedIndexGateway({
      'revision':List.filled(64,'a').join(),
      'unchanged':false,'resetRequired':false,'entries':[entry],
    });
    final missing=FablePublishedContentRepository(api);
    await expectLater(missing.publishedIndex(),throwsStateError);
    expect(api.calls,0);
    final mapped=FablePublishedContentRepository(api,indexOperationId:'document.published');
    final entries=await mapped.publishedIndex();
    expect(api.lastId,'document.published');
    expect(entries.single.slug,'privacy-policy');
    expect(entries.single.version,2);
    expect(entries.single.versionId,entry['revision']);
  });
  test('published index rejects unrelated admin, duplicate and invalid manifests',()async{
    final api=_PublishedIndexGateway({'entries':[]});
    final repo=FablePublishedContentRepository(api,indexOperationId:'content.publicChanges');
    await expectLater(repo.publishedIndex(),throwsFormatException);
    final one={'slug':'privacy-policy',
      'revision':'550e8400-e29b-41d4-a716-446655440001','version':2};
    api.reply={'revision':List.filled(64,'a').join(),'unchanged':false,
      'resetRequired':false,'entries':[one,one]};
    await expectLater(repo.publishedIndex(),throwsFormatException);
    api.reply={'revision':List.filled(64,'a').join(),'unchanged':false,
      'resetRequired':false,'entries':[{'slug':'../admin',
       'revision':'550e8400-e29b-41d4-a716-446655440001','version':3}]};
    await expectLater(repo.publishedIndex(),throwsFormatException);
    api.reply={'revision':List.filled(64,'a').join(),'unchanged':true,
      'resetRequired':false};
    await expectLater(repo.publishedIndex(),throwsFormatException);
  });

}

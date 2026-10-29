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
}

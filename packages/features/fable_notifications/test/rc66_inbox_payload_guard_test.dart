import 'package:fable_notifications/fable_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('RC66 private inbox only accepts UUID items and allowlisted navigation fields', () {
    final item=FableInboxItem.fromPayload({
      'id':'29b22238-8d4e-4d0d-b6fa-cc2a1a390001',
      'title':'Session','body':'Updated',
      'data':{'target':'notifications','url':'https://example.org/safe',
        'secret':'do-not-expose','nested':{'private':true}},
      'publishedAt':'2026-10-29T00:00:00Z',
    });
    expect(item.title,'Session');
    expect(item.data.keys.toSet(),{'target','url'});
    expect(item.data.containsKey('secret'),isFalse);
    expect(() => FableInboxItem.fromPayload({
      'id':'../admin','title':'Wrong','body':'Unsafe',
    }),throwsFormatException);
    // Backend accepts a title exactly at its 400-character bound.
    final atLimit=FableInboxItem.fromPayload({
      'id':'29b22238-8d4e-4d0d-b6fa-cc2a1a390001',
      'title':'Too long'*50,'body':'Allowed',
    });
    expect(atLimit.title.length,400);
    expect(() => FableInboxItem.fromPayload({
      'id':'29b22238-8d4e-4d0d-b6fa-cc2a1a390001',
      'title':('Too long'*50)+'x','body':'Rejected',
    }),throwsFormatException);
  });
}

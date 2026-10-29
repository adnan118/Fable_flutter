import 'package:flutter_test/flutter_test.dart';
import 'package:fable_notifications/fable_notifications.dart';

void main() {
  test('external Inbox accepts bounded numeric IDs without weakening Fable UUID policy', () {
    final payload={'id':'123','title':'New item','body':'Read item'};
    expect(() => FableInboxItem.fromPayload(payload),throwsFormatException);
    final external=FableInboxItem.fromPayload(payload,requireUuidIds:false);
    expect(external.id,'123');
    for(final invalid in ['../admin','a/b','%2e%2e','', List.filled(129,'a').join()]) {
      expect(() => FableInboxItem.fromPayload({...payload,'id':invalid},requireUuidIds:false),throwsFormatException);
    }
  });
}

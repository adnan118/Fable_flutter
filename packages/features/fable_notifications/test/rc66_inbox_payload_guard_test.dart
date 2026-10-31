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
  test('privacy revision CTA is scoped to matching Fable event and published identity',(){
    const id='29b22238-8d4e-4d0d-b6fa-cc2a1a390001';
    final notice={'id':id,'title':'Updated privacy','body':'Review changes',
      'data':{'kind':'PRIVACY_POLICY_UPDATED','noticeId':id,
        'pageId':'550e8400-e29b-41d4-a716-446655440001',
        'versionId':'550e8400-e29b-41d4-a716-446655440002',
        'target':'https://untrusted.test'},
    };
    final fable=FableInboxItem.fromPayload(notice);
    expect(fable.isPublishedPrivacyUpdate,true);
    expect(FableInboxItem.fromPayload(notice,requireUuidIds:false)
      .isPublishedPrivacyUpdate,false);
    expect(FableInboxItem.fromPayload({...notice,'data':{
      ...notice['data'] as Map<String,Object?>,'noticeId':'different',
    }}).isPublishedPrivacyUpdate,false);
    expect(FableInboxItem.fromPayload({...notice,'data':{
      ...notice['data'] as Map<String,Object?>,'versionId':'../../../other',
    }}).isPublishedPrivacyUpdate,false);
  });

}

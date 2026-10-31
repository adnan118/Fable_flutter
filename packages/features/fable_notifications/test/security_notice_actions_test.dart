import 'package:flutter_test/flutter_test.dart';
import '../lib/src/security_notice_actions.dart';

void main(){
  const id='550e8400-e29b-41d4-a716-446655440000';
  Map<String,dynamic> notice({Object? route='/account/reset-password'})=> {
    'kind':'AUTH_FAILED_LIMIT','noticeId':id,
    'actions':[
      {'id':'THIS_WAS_ME','kind':'acknowledge-only'},
      {'id':'RESET_PASSWORD','kind':'internal-route','route':route},
    ]
  };
  test('Only the Fable notice tied to its actual ID can display security actions',(){
    final actions=readFableSecurityActions(notice(),notificationId:id,isFable:true);
    expect(actions.length,2);
    expect(actions[0].id,'THIS_WAS_ME');
    expect(actions[1].route,'/account/reset-password');
    expect(readFableSecurityActions(notice(),notificationId:id,isFable:false),isEmpty);
    expect(readFableSecurityActions(notice(),notificationId:'wrong',isFable:true),isEmpty);
  });
  test('Invalid, duplicate, external and arbitrary routes fail closed',(){
    for(final input in [
      'https://evil.test/account/password',
      '//evil.test/password',
      '/account/../password',
      '/account/password?token=evil',
      'javascript:password',
      '/settings',
    ]){
      expect(isSafeInternalPasswordRoute(input),false);
      expect(readFableSecurityActions(notice(route:input),
        notificationId:id,isFable:true),isEmpty);
    }
    final duplicated=notice();
    duplicated['actions']=[
      {'id':'THIS_WAS_ME','kind':'acknowledge-only'},
      {'id':'THIS_WAS_ME','kind':'acknowledge-only'},
    ];
    expect(readFableSecurityActions(duplicated,notificationId:id,isFable:true),isEmpty);
  });
  test('Acknowledge-only does not assert identity or unblock authentication',(){
    final data={'kind':'AUTH_FAILED_LIMIT','noticeId':id,
      'actions':[{'id':'THIS_WAS_ME','kind':'acknowledge-only'}]};
    final actions=readFableSecurityActions(data,notificationId:id,isFable:true);
    expect(actions.single.kind,'acknowledge-only');
    expect(actions.single.route,isNull);
  });
}

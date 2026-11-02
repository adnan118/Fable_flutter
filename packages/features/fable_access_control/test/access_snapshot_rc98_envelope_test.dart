import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fable_access_control/fable_access_control.dart';
import 'package:fable_core/fable_core.dart';

class _SnapshotGateway implements BackendApiGateway {
  _SnapshotGateway(this.data);
  final Object? data;
  String? called;
  @override
  Future<Response<dynamic>> execute(String operationId, {
    Map<String,dynamic>? path,
    Map<String,dynamic>? query,
    Object? body,
    CancelToken? cancelToken,
    String? ifMatch,
  }) async {
    called=operationId;
    return Response<dynamic>(requestOptions:RequestOptions(path:'/permissions/me'),
      statusCode:200,data:data);
  }
  @override void dispose(){}
}
Map<String,dynamic> _policy(String provider)=>{
  'kind':'fable.mobile-access-policy',
  'provider':provider,
  'snapshot':<String,dynamic>{
    'operationId':'permissions.me',
    'userIdField':'userId',
    'permissionsField':'keys',
    'rolesField':'roles',
  }
};

void main() {
  test('RC98 Fable reads permission keys only from Backend success/data envelope',()async{
    final gateway=_SnapshotGateway({
      'success':true,'requestId':'test','data':{
        'userId':'550e8400-e29b-41d4-a716-446655440012',
        'keys':['content.read'],'roles':['VIEWER'],
      }
    });
    final repo=FableAccessRepository.fromPolicy(gateway,_policy('fable'));
    final snapshot=await repo.current();
    expect(gateway.called,'permissions.me');
    expect(snapshot.can('content.read'),true);
    expect(snapshot.can('roles.update'),false);
    expect(snapshot.hasRole('VIEWER'),true);
    expect(snapshot.raw.containsKey('requestId'),false);
  });

  test('RC98 Fable rejects unconfirmed or forged top-level role payload',()async{
    final cases=<Object?>[
      {'userId':'someone','keys':['roles.update'],'roles':['ADMIN']},
      {'success':false,'data':{'userId':'someone','keys':['roles.update'],'roles':['ADMIN']}},
      {'success':true,'data':null},
      {'success':true,'data':['roles.update']},
      null,
    ];
    for(final body in cases){
      final gateway=_SnapshotGateway(body);
      await expectLater(FableAccessRepository.fromPolicy(gateway,_policy('fable'))
        .current(),throwsFormatException);
    }
  });

  test('RC98 Other Backend respects its independent direct response mapping',()async{
    final gateway=_SnapshotGateway({
      'account':{'identity':'user-other'},
      'permissions':['orders.read'],
      'groups':['staff'],
    });
    final config={
      'kind':'fable.mobile-access-policy','provider':'other',
      'snapshot':{
        'operationId':'other.permissions',
        'userIdField':'account.identity',
        'permissionsField':'permissions',
        'rolesField':'groups',
      }
    };
    final snapshot=await FableAccessRepository.fromPolicy(gateway,config).current();
    expect(gateway.called,'other.permissions');
    expect(snapshot.userId,'user-other');
    expect(snapshot.can('orders.read'),true);
    expect(snapshot.hasRole('staff'),true);
  });

  test('RC98 refuses a missing or incorrect policy provider',(){
    final gateway=_SnapshotGateway(null);
    for(final provider in <Object?>[null,'browser','admin']){
      final config=_policy('fable')..['provider']=provider;
      expect(()=>FableAccessRepository.fromPolicy(gateway,config),throwsFormatException);
    }
  });
}

import 'package:fable_core/fable_core.dart';
import 'package:fable_push_notifications/fable_push_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

FableContract _catalog(Map<String,FableOperation> operations) => FableContract(
  contractHash: List.filled(64,'a').join(), operations: operations, featureIds: const <String>{'notifications'},
  projectName: 'verified-rc66-test', selectionMode: 'explicit',
);

FableOperation _op(String id,String method,{bool auth=true,bool enforced=true}) =>
    FableOperation(id,method,'/verified/$id',List.filled(64,'b').join(),requiresAuth:auth,enforceAuth:enforced);

void main() {
  test('RC66 push requires protected POST/DELETE operations', () {
    const bindings=PushDeviceBindings.fable();
    final valid={
      bindings.register:_op(bindings.register,'POST'),
      bindings.unregister:_op(bindings.unregister,'DELETE'),
    };
    expect(() => bindings.verify(_catalog(valid)), returnsNormally);
    expect(() => bindings.verify(_catalog({...valid,
      bindings.register:_op(bindings.register,'POST',auth:false)})),throwsStateError);
    expect(() => bindings.verify(_catalog({...valid,
      bindings.unregister:_op(bindings.unregister,'GET')})),throwsStateError);
    expect(() => bindings.verify(_catalog({...valid,
      bindings.register:_op(bindings.register,'POST',enforced:false)})),throwsStateError);
    expect(() => bindings.verify(_catalog({bindings.register:valid[bindings.register]!})),
      throwsStateError);
  });

  test('push register/unregister cannot silently bind to one operation', () {
    const bindings=PushDeviceBindings(register:'same.operation',unregister:'same.operation');
    expect(() => bindings.verify(_catalog({'same.operation':_op('same.operation','POST')})),
      throwsStateError);
  });
}

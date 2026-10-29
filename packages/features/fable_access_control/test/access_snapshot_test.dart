import 'package:flutter_test/flutter_test.dart';
import 'package:fable_access_control/fable_access_control.dart';
void main() {
  test('preserves backend fields without losing unknown properties', () {
    final input = <String,dynamic>{'userId':'u1','keys':['content.read'],
      'roles':['admin'], 'revision':42,'flags':{'a':true}};
    final snapshot = FableAccessSnapshot.fromJson(input);
    expect(snapshot.toJson(), input);
    expect(snapshot.can('content.read'), true);
    expect(snapshot.hasRole('admin'), true);
  });
  test('other backend supports mapped fields', () {
    final snapshot = FableAccessSnapshot.fromJson(
      {'subject':'u1','permissions':['read'],'groups':['editor'],'version':3},
      userIdField:'subject',permissionsField:'permissions',rolesField:'groups');
    expect(snapshot.can('read'), true);
    expect(snapshot.additionalFields['version'], 3);
  });
}

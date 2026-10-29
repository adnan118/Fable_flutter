import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fable_access_control/fable_access_control.dart';

Map<String, dynamic> roleManifest(List<String> roles, {String mode = 'role-separated'}) => {
  'schemaVersion': 1,
  'kind': 'fable.mobile-role-layout',
  'generatedBy': 'fable-mobile',
  'mode': mode,
  'roles': roles,
};

FableAccessSnapshot profile(List<String> roles) => FableAccessSnapshot.fromJson({
  'userId': 'user-1', 'keys': <String>[], 'roles': roles,
});

void main() {
  test('roles are not grants; priority is stable and account-scoped', () {
    final config = FableRoleLayout.fromManifest(roleManifest(['admin', 'customer']));
    expect(config.selectRole(null), isNull);
    expect(config.selectRole(profile(['customer'])), 'customer');
    expect(config.selectRole(profile(['customer', 'admin'])), 'admin');
    expect(config.selectRole(profile(['customer', 'admin']), preferredRole: 'customer'), 'customer');
    expect(config.selectRole(profile(['customer']), preferredRole: 'admin'), 'customer');
    expect(config.selectRole(profile(['guest'])), isNull);
    expect(profile(['admin']).can('users.delete'), isFalse);
  });

  test('fail closed when role layout is malformed or unsafe', () {
    expect(() => FableRoleLayout.fromManifest(roleManifest(['admin', 'admin'])), throwsFormatException);
    expect(() => FableRoleLayout.fromManifest(roleManifest(['../admin'])), throwsFormatException);
    expect(() => FableRoleLayout.fromManifest(roleManifest([], mode: 'role-separated')), throwsFormatException);
    expect(() => FableRoleLayout.fromManifest(roleManifest(['admin'], mode: 'shared')), throwsFormatException);
    expect(() => FableRoleLayout.fromManifest({...roleManifest(['admin']), 'generatedBy': 'untrusted'}), throwsFormatException);
  });

  testWidgets('role view changes with snapshot, logout and role revocation', (tester) async {
    final snapshot = ValueNotifier<FableAccessSnapshot?>(null);
    final config = FableRoleLayout.fromManifest(roleManifest(['admin', 'customer']));
    final policy = FableAccessPolicy.fromManifest({
      'schemaVersion': 1, 'kind': 'fable.mobile-access-policy',
      'provider': 'fable', 'contractFingerprint': 'verified',
      'operations': {'users.delete': {'mode': 'permissions', 'keys': ['users.delete']}},
    });
    await tester.pumpWidget(FableAccessScope(policy: policy, snapshot: snapshot,
      child: Directionality(textDirection: TextDirection.ltr,
        child: Column(children: [
          FableRoleView(layout: config,
            views: const {'admin': Text('Admin View'), 'customer': Text('Customer View')},
            fallback: const Text('No Role')),
          const FableOperationVisibility(operationId: 'users.delete', child: Text('Delete')),
        ]))));
    expect(find.text('No Role'), findsOneWidget);
    snapshot.value = profile(['admin']);
    await tester.pump();
    expect(find.text('Admin View'), findsOneWidget);
    expect(find.text('Delete'), findsNothing); // A role cannot authorize an operation.
    snapshot.value = profile(['customer']);
    await tester.pump();
    expect(find.text('Customer View'), findsOneWidget);
    expect(find.text('Admin View'), findsNothing);
    snapshot.value = null;
    await tester.pump();
    expect(find.text('No Role'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    snapshot.dispose();
  });
}

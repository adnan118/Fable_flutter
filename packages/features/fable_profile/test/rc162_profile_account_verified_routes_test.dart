import 'package:fable_core/fable_core.dart';
import 'package:fable_profile/fable_profile.dart';
import 'package:flutter_test/flutter_test.dart';

const _fingerprint =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

FableContract _catalog({
  String readPath = '/auth/me/account',
  String readMethod = 'GET',
  bool readRequiresAuth = true,
  bool enforceAuth = true,
  String? readCredentialHeader,
  String operationHash = _fingerprint,
  bool selected = true,
  bool enabled = true,
  bool includeSetup = true,
  String? writePath = '/auth/me/account',
  String writeMethod = 'PATCH',
  bool writeRequiresAuth = true,
  bool writeEnforceAuth = true,
}) {
  final operations = <String, FableOperation>{
    'account.me': FableOperation(
      'account.me', readMethod, readPath, operationHash,
      requiresAuth: readRequiresAuth,
      enforceAuth: enforceAuth,
      credentialHeader: readCredentialHeader,
    ),
    if (writePath != null)
      'account.displayName.update': FableOperation(
        'account.displayName.update', writeMethod, writePath, _fingerprint,
        requiresAuth: writeRequiresAuth,
        enforceAuth: writeEnforceAuth,
      ),
  };
  return FableContract(
    contractHash: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    projectName: 'rc162-synthetic-source-only',
    selectionMode: 'explicit',
    featureIds: selected ? const {'profile'} : const <String>{},
    operations: operations,
    frontendSetup: includeSetup
        ? {
            'decisions': {
              'frontendFeatures': {
                'enabled': <String>[
                  'auth', 'access_control', if (enabled) 'profile',
                ],
              },
            },
          }
        : null,
  );
}

void main() {
  test('RC162 Profile read is authentic GET /auth/me/account only', () {
    final catalog = _catalog();
    expect(FableProfileAccountRoutePolicy.canRead(catalog), true);
    expect(profileFeature.canLaunchFable(catalog), true);
    expect(FableProfileAccountRoutePolicy.canUpdateDisplayName(catalog), true);
  });

  test('RC162 wrong GET paths and HTTP verbs never enable Profile', () {
    for (final c in [
      _catalog(readPath: '/auth/sessions'),
      _catalog(readPath: '/admin/users'),
      _catalog(readPath: '//external/account'),
      _catalog(readPath: '/auth/me/account?target=other'),
      _catalog(readMethod: 'POST'),
      _catalog(readMethod: 'HEAD'),
    ]) {
      expect(FableProfileAccountRoutePolicy.canRead(c), false);
      expect(profileFeature.canLaunchFable(c), false);
      expect(FableProfileAccountRoutePolicy.canUpdateDisplayName(c), false);
    }
  });

  test('RC162 protected bearer route cannot be advertised as public or weak', () {
    for (final c in [
      _catalog(readRequiresAuth: false),
      _catalog(enforceAuth: false),
      _catalog(readCredentialHeader: 'X-Provider-Key'),
      _catalog(operationHash: 'not-a-valid-hash'),
    ]) {
      expect(FableProfileAccountRoutePolicy.canRead(c), false);
      expect(profileFeature.canLaunchFable(c), false);
    }
  });

  test('RC162 unknown, unselected or backend-disabled Profile is denied', () {
    for (final c in [
      _catalog(selected: false),
      _catalog(enabled: false),
      _catalog(includeSetup: false),
    ]) {
      expect(FableProfileAccountRoutePolicy.canRead(c), false);
      expect(profileFeature.canLaunchFable(c), false);
    }
  });

  test('RC162 missing or misbound optional update is read-only', () {
    for (final c in [
      _catalog(writePath: null),
      _catalog(writePath: '/auth/sessions'),
      _catalog(writePath: '/auth/me/account/privileges'),
      _catalog(writeMethod: 'POST'),
      _catalog(writeMethod: 'GET'),
      _catalog(writeRequiresAuth: false),
      _catalog(writeEnforceAuth: false),
    ]) {
      expect(FableProfileAccountRoutePolicy.canRead(c), true);
      expect(profileFeature.canLaunchFable(c), true);
      expect(FableProfileAccountRoutePolicy.canUpdateDisplayName(c), false);
    }
  });
}

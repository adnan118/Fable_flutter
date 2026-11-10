import 'package:fable_core/fable_core.dart';
import 'package:fable_notifications/fable_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

const _sha = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

FableContract _contract({
  String listPath = '/notifications/inbox',
  String readPath = '/notifications/{id}/read',
  String listMethod = 'GET',
  String readMethod = 'POST',
  bool listAuthenticated = true,
  bool readAuthenticated = true,
  bool enforced = true,
  String? listCredentialHeader,
  bool enabled = true,
  bool selected = true,
  bool legacy = false,
}) {
  final operations = <String, FableOperation>{
    'notifications.inbox': FableOperation(
      'notifications.inbox', listMethod, listPath, _sha,
      requiresAuth: listAuthenticated,
      enforceAuth: enforced,
      credentialHeader: listCredentialHeader,
    ),
    'notifications.read': FableOperation(
      'notifications.read', readMethod, readPath, _sha,
      requiresAuth: readAuthenticated,
      enforceAuth: enforced,
    ),
  };
  return FableContract(
    contractHash: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    operations: operations,
    featureIds: selected ? const {'notifications'} : const <String>{},
    projectName: 'rc161-simulated-project',
    selectionMode: 'explicit',
    frontendSetup: legacy
        ? null
        : {
            'decisions': {
              'frontendFeatures': {
                'enabled': <String>[
                  'auth',
                  'access_control',
                  if (enabled) 'notifications',
                ],
              },
            },
          },
  );
}

void main() {
  test('RC161 Fable Notifications uses exact GET inbox and POST mark-read routes', () {
    final brace = _contract();
    final colon = _contract(readPath: '/notifications/:id/read');
    for (final contract in [brace, colon]) {
      expect(FableInboxRoutePolicy.verified(contract), isTrue);
      expect(notificationsFeature.canLaunchFable(contract), isTrue);
    }
  });

  test('RC161 op IDs alone do not license a mismatched destination', () {
    for (final contract in [
      _contract(listPath: '/users'),
      _contract(listPath: '//untrusted/inbox'),
      _contract(readPath: '/notifications/{id}/admin'),
      _contract(readPath: '/notifications/{id}/read?forged=1'),
      _contract(readPath: '/notifications/{userId}/read'),
      _contract(listMethod: 'POST'),
      _contract(readMethod: 'DELETE'),
      _contract(readMethod: 'PATCH'),
    ]) {
      expect(FableInboxRoutePolicy.verified(contract), isFalse);
      expect(notificationsFeature.canLaunchFable(contract), isFalse);
    }
  });

  test('RC161 all protected route metadata must be explicit and enforced', () {
    for (final contract in [
      _contract(listAuthenticated: false),
      _contract(readAuthenticated: false),
      _contract(enforced: false),
      _contract(listCredentialHeader: 'X-API-Key'),
    ]) {
      expect(FableInboxRoutePolicy.verified(contract), isFalse);
      expect(notificationsFeature.canLaunchFable(contract), isFalse);
    }
  });

  test('RC161 backend-disabled, locally omitted and unknown decisions deny activation', () {
    for (final contract in [
      _contract(enabled: false),
      _contract(selected: false),
      _contract(legacy: true),
    ]) {
      expect(FableInboxRoutePolicy.verified(contract), isFalse);
      expect(notificationsFeature.canLaunchFable(contract), isFalse);
    }
  });

  test('RC161 foreign operation aliases cannot inherit Fable inbox grants', () {
    final contract = _contract();
    expect(FableInboxRoutePolicy.verified(contract,
      listOperationId: 'auth.sessions'), isFalse);
    expect(FableInboxRoutePolicy.verified(contract,
      markReadOperationId: 'notifications.broadcast'), isFalse);
  });

  test('RC161 Other Backend payload still supports its independent IDs', () {
    const payload = {
      'id': '123',
      'title': 'External inbox entry',
      'body': 'Delivered by independent provider',
    };
    expect(() => FableInboxItem.fromPayload(payload), throwsFormatException);
    final external = FableInboxItem.fromPayload(
      payload, requireUuidIds: false,
    );
    expect(external.id, '123');
    // Never infer Fable's verified routes from an external payload.
    expect(FableInboxRoutePolicy.verified(_contract(enabled: false)), isFalse);
  });
}

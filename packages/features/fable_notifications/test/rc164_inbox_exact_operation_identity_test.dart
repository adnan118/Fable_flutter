import 'package:fable_core/fable_core.dart';
import 'package:fable_notifications/fable_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

const _hash = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const _contractHash = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

FableContract _catalog({
  String listId = 'notifications.inbox',
  String readId = 'notifications.read',
  String listKey = 'notifications.inbox',
  String readKey = 'notifications.read',
  bool extraList = false,
  String? extraReadPath,
  bool enforced = true,
}) => FableContract(
  contractHash: _contractHash,
  projectName: 'rc164-synthetic-not-a-real-project',
  selectionMode: 'explicit',
  featureIds: const {'notifications'},
  frontendSetup: const {
    'decisions': {
      'frontendFeatures': {'enabled': ['auth', 'access_control', 'notifications']}
    }
  },
  operations: {
    listKey: FableOperation(listId, 'GET', '/notifications/inbox', _hash,
      enforceAuth: enforced),
    readKey: FableOperation(readId, 'POST', '/notifications/{id}/read', _hash,
      enforceAuth: enforced),
    if (extraList)
      'notification.forger': const FableOperation('notification.forger',
        'GET', '/notifications/inbox', _hash, enforceAuth: true),
    if (extraReadPath != null)
      'notification.duplicate': FableOperation('notification.duplicate',
        'POST', extraReadPath, _hash, enforceAuth: true),
  },
);

void main() {
  test('RC164 canonical Fable inbox and mark-read IDs remain enabled', () {
    expect(FableInboxRoutePolicy.verified(_catalog()), isTrue);
    expect(notificationsFeature.canLaunchFable(_catalog()), isTrue);
  });

  test('RC164 forged internal operation ID with canonical map key is denied', () {
    for (final c in [
      _catalog(listId: 'user.inbox'),
      _catalog(readId: 'admin.read'),
    ]) {
      expect(FableInboxRoutePolicy.verified(c), isFalse);
      expect(notificationsFeature.canLaunchFable(c), isFalse);
    }
  });

  test('RC164 impersonated Fable operation names under custom keys are denied', () {
    final aliased = _catalog(listKey: 'shadow.inbox', readKey: 'shadow.read');
    expect(FableInboxRoutePolicy.verified(aliased,
      listOperationId: 'shadow.inbox',
      markReadOperationId: 'shadow.read'), isFalse);
    expect(notificationsFeature.canLaunchFable(aliased), isFalse);
  });

  test('RC164 duplicated protected routes fail closed, including brace/colon', () {
    for (final c in [
      _catalog(extraList: true),
      _catalog(extraReadPath: '/notifications/{id}/read'),
      _catalog(extraReadPath: '/notifications/:id/read'),
    ]) {
      expect(FableInboxRoutePolicy.verified(c), isFalse);
      expect(notificationsFeature.canLaunchFable(c), isFalse);
    }
  });

  test('RC164 trust rule still rejects non-enforced route metadata', () {
    expect(FableInboxRoutePolicy.verified(_catalog(enforced: false)), isFalse);
  });
}

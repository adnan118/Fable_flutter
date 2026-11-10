import 'package:fable_core/fable_core.dart';

/// RC162 — Fable's core Auth account is not a project-specific profile.
/// Only the verified /auth/me/account contract can expose account fields or
/// enable the optional display-name edit. Other Backend is independently bound.
class FableProfileAccountRoutePolicy {
  const FableProfileAccountRoutePolicy._();

  static bool _matches(
    FableOperation? operation, {
    required String id,
    required String method,
  }) =>
      operation != null &&
      operation.id == id &&
      operation.method == method &&
      operation.path == '/auth/me/account' &&
      operation.requiresAuth &&
      operation.enforceAuth &&
      operation.credentialHeader == null &&
      RegExp(r'^[a-f0-9]{64}$').hasMatch(operation.contractHash);

  static bool canRead(FableContract contract) =>
      contract.isFeatureAvailable('profile') &&
      _matches(
        contract.operations['account.me'],
        id: 'account.me',
        method: 'GET',
      );

  /// Editing is optional; a malformed or omitted PATCH must never be sent.
  /// An authenticated GET can still be used for a read-only profile.
  static bool canUpdateDisplayName(FableContract contract) =>
      canRead(contract) &&
      _matches(
        contract.operations['account.displayName.update'],
        id: 'account.displayName.update',
        method: 'PATCH',
      );
}

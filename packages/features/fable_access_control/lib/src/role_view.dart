import 'dart:convert';

import 'package:flutter/services.dart' show AssetBundle, rootBundle;
import 'package:flutter/widgets.dart';

import 'access_policy.dart';
import 'access_snapshot.dart';

/// Wizard-created role presentation layout. This is NEVER an authorization grant.
/// A server permission check is still required for every protected operation.
class FableRoleLayout {
  const FableRoleLayout({required this.mode, required this.rolePriority});

  final String mode;
  /// Wizard role ordering is explicit and deterministic when a user has many roles.
  final List<String> rolePriority;

  factory FableRoleLayout.fromManifest(Map<String, dynamic> manifest) {
    if (manifest['schemaVersion'] != 1 ||
        manifest['kind'] != 'fable.mobile-role-layout' ||
        manifest['generatedBy'] != 'fable-mobile' ||
        !['shared', 'role-separated'].contains(manifest['mode']) ||
        manifest['roles'] is! List) {
      throw const FormatException('Invalid generated role layout');
    }
    final raw = manifest['roles'] as List;
    final roles = <String>[];
    final identifier = RegExp(r'^[a-z][a-z0-9_]{0,39}$');
    for (final item in raw) {
      if (item is! String || !identifier.hasMatch(item) || roles.contains(item)) {
        throw const FormatException('Invalid or duplicated role key');
      }
      roles.add(item);
    }
    if (roles.length > 24 ||
        (manifest['mode'] == 'shared' && roles.isNotEmpty) ||
        (manifest['mode'] == 'role-separated' && roles.isEmpty)) {
      throw const FormatException('Inconsistent role layout');
    }
    return FableRoleLayout(mode: manifest['mode'] as String,
        rolePriority: List<String>.unmodifiable(roles));
  }

  static Future<FableRoleLayout> loadFromAssets({
    AssetBundle? bundle,
    String path = 'assets/contracts/role-layout.json',
  }) async {
    final data = jsonDecode(await (bundle ?? rootBundle).loadString(path));
    if (data is! Map<String, dynamic>) {
      throw const FormatException('Role layout must be an object');
    }
    return FableRoleLayout.fromManifest(data);
  }

  /// Role switching only selects a view; it cannot add any permission keys.
  String? selectRole(FableAccessSnapshot? snapshot, {String? preferredRole}) {
    if (mode != 'role-separated' || snapshot == null) return null;
    if (preferredRole != null && rolePriority.contains(preferredRole) &&
        snapshot.hasRole(preferredRole)) return preferredRole;
    for (final role in rolePriority) {
      if (snapshot.hasRole(role)) return role;
    }
    return null;
  }
}

/// Selects a declared role view automatically based on active backend roles.
/// The programmer maps role keys to screens, not `if (role)` conditions.
/// Unknown/revoked roles fail closed to [fallback].
class FableRoleView extends StatelessWidget {
  const FableRoleView({super.key, required this.layout,
    required this.views, this.preferredRole,
    this.fallback = const SizedBox.shrink()});

  final FableRoleLayout layout;
  final Map<String, Widget> views;
  final String? preferredRole;
  final Widget fallback;

  @override
  Widget build(BuildContext context) {
    final snapshot = FableAccessScope.maybeOf(context)?.notifier?.value;
    final role = layout.selectRole(snapshot, preferredRole: preferredRole);
    return role == null ? fallback : (views[role] ?? fallback);
  }
}

import 'dart:convert';
import 'package:flutter/services.dart' show AssetBundle, rootBundle;
import 'package:flutter/widgets.dart';
import 'access_snapshot.dart';

/// Presentation-only operation policy. Server authorization remains mandatory.
/// Each UI component names an operationId; no per-widget permission conditions.
class FableAccessPolicy {
  final Map<String, List<String>> requirements;
  final Map<String, String> operationModes;
  final String? contractFingerprint;
  final String? provider;

  const FableAccessPolicy(this.requirements)
      : operationModes = const {}, contractFingerprint = null, provider = null;

  FableAccessPolicy._(this.requirements, this.operationModes,
      this.contractFingerprint, this.provider);

  factory FableAccessPolicy.fromManifest(Map<String, dynamic> manifest,
      {String? expectedFingerprint}) {
    if (expectedFingerprint != null && manifest['contractFingerprint'] != expectedFingerprint) {
      throw const FormatException('Access policy does not match current backend contract');
    }
    if (manifest['schemaVersion'] != 1 ||
        manifest['kind'] != 'fable.mobile-access-policy' ||
        !['fable', 'other'].contains(manifest['provider']) ||
        manifest['contractFingerprint'] is! String ||
        (manifest['contractFingerprint'] as String).isEmpty ||
        manifest['operations'] is! Map) {
      throw const FormatException('Invalid access policy manifest');
    }
    final modes = <String, String>{};
    final required = <String, List<String>>{};
    for (final entry in (manifest['operations'] as Map).entries) {
      if (entry.key is! String || entry.value is! Map) {
        throw const FormatException('Invalid access operation');
      }
      final rule = entry.value as Map;
      final mode = rule['mode'];
      if (!['public', 'authenticated', 'permissions'].contains(mode)) {
        throw const FormatException('Unsupported access operation mode');
      }
      final key = entry.key as String;
      modes[key] = mode as String;
      if (mode == 'permissions') {
        final keys = rule['keys'];
        if (keys is! List || keys.isEmpty ||
            keys.any((value) => value is! String || value.isEmpty)) {
          throw const FormatException('Missing access permission keys');
        }
        required[key] = List<String>.unmodifiable(keys.cast<String>());
      }
    }
    return FableAccessPolicy._(Map.unmodifiable(required),
        Map.unmodifiable(modes), manifest['contractFingerprint'] as String,
        manifest['provider'] as String);
  }

  /// The generated JSON is included in Flutter assets. A stale hash is rejected.
  static Future<FableAccessPolicy> loadFromAssets({
    AssetBundle? bundle,
    String path = 'assets/contracts/access-policy.json',
    required String expectedFingerprint,
  }) async {
    final raw = await (bundle ?? rootBundle).loadString(path);
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Access policy asset is not an object');
    }
    return FableAccessPolicy.fromManifest(decoded,
        expectedFingerprint: expectedFingerprint);
  }

  bool allows(String identifier, FableAccessSnapshot? snapshot) {
    final mode = operationModes[identifier];
    if (mode == 'public') return true;
    if (mode == 'authenticated') return snapshot != null;
    final needed = requirements[identifier];
    if (snapshot == null || needed == null || needed.isEmpty) return false;
    return snapshot.canAll(needed);
  }
}

/// Shared access state in all backends. Missing provider fails closed.
class FableAccessScope
    extends InheritedNotifier<ValueNotifier<FableAccessSnapshot?>> {
  final FableAccessPolicy policy;
  const FableAccessScope({super.key, required this.policy,
      required ValueNotifier<FableAccessSnapshot?> snapshot, required super.child})
      : super(notifier: snapshot);

  static FableAccessScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<FableAccessScope>();

  static FableAccessScope of(BuildContext context) {
    final scope = maybeOf(context);
    if (scope == null) throw StateError('FableAccessScope is missing');
    return scope;
  }

  bool allows(String operationId) => policy.allows(operationId, notifier?.value);

  @override
  bool updateShouldNotify(covariant FableAccessScope oldWidget) =>
      !identical(policy, oldWidget.policy) ||
      !identical(notifier, oldWidget.notifier);
}

/// Declarative gate driven by the operation catalog, not inline if statements.
class FablePolicyVisibility extends StatelessWidget {
  final String identifier;
  final Widget child;
  final Widget fallback;
  const FablePolicyVisibility({super.key, required this.identifier,
      required this.child, this.fallback = const SizedBox.shrink()});

  @override
  Widget build(BuildContext context) =>
      (FableAccessScope.maybeOf(context)?.allows(identifier) ?? false) ? child : fallback;
}

/// Alias whose meaning is explicit when attaching a button/screen to an API operation.
class FableOperationVisibility extends StatelessWidget {
  final String operationId;
  final Widget child;
  final Widget fallback;
  const FableOperationVisibility({super.key, required this.operationId,
      required this.child, this.fallback = const SizedBox.shrink()});

  @override
  Widget build(BuildContext context) => FablePolicyVisibility(
      identifier: operationId, fallback: fallback, child: child);
}

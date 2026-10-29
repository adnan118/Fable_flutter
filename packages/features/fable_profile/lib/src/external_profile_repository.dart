import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:fable_core/fable_core.dart';

/// A verified, explicit projection of another backend's response into a small
/// profile view. Paths are JSON object keys only; no script / JSONPath execution.
class ExternalProfileFields {
  const ExternalProfileFields._(this.operationId, this.paths);
  final String operationId;
  final Map<String, String> paths;
  static final RegExp _safePath = RegExp(r'^[A-Za-z][A-Za-z0-9_]*(?:\.[A-Za-z][A-Za-z0-9_]*){0,7}$');
  static const _reserved = <String>{'__proto__', 'constructor', 'prototype'};
  static final RegExp _secretField = RegExp(r'^(?:password|passwd|access_?token|refresh_?token|id_?token|api_?key|secret|private_?key|authorization|otp|verification_?code|session_?token)$', caseSensitive: false);

  static ExternalProfileFields fromMap(Map<String, dynamic> value,
      ExternalOperationCatalog catalog, ExternalFeatureBindings bindings) {
    if (value['schemaVersion'] != 1 || value['kind'] != 'fable.external-profile-fields' ||
        value['adapter'] != catalog.adapter || value['sourceHash'] != catalog.sourceHash ||
        value['operationsHash'] != catalog.operationsHash ||
        value['readOperationId'] != bindings.operation('profile', 'read')) {
      throw const FormatException('Stale or mismatched profile projection');
    }
    final operationId = value['readOperationId'];
    if (operationId is! String || !catalog.supports(operationId)) {
      throw const FormatException('Unbound profile read operation');
    }
    final operation = catalog.require(operationId);
    if (operation.method != 'GET' || operation.path.contains('{')) {
      throw const FormatException('Profile read requires GET without path parameters');
    }
    final source = value['fields'];
    if (source is! Map || source['displayName'] is! String) {
      throw const FormatException('Profile displayName path required');
    }
    final fields = <String, String>{};
    for (final entry in source.entries) {
      if (entry.key is! String || !const {'displayName', 'email', 'avatarUrl'}.contains(entry.key) ||
          entry.value is! String || !_safePath.hasMatch(entry.value as String) ||
          (entry.value as String).split('.').any((key) => _reserved.contains(key) || _secretField.hasMatch(key))) {
        throw const FormatException('Unsafe profile field selector');
      }
      fields[entry.key as String] = entry.value as String;
    }
    return ExternalProfileFields._(operationId, Map.unmodifiable(fields));
  }

  static Future<ExternalProfileFields> fromAssets(AssetBundle assets,
      ExternalOperationCatalog catalog, ExternalFeatureBindings bindings) async {
    final text = await assets.loadString('assets/config/profile-fields.json');
    return fromMap(jsonDecode(text) as Map<String, dynamic>, catalog, bindings);
  }

  Object? _value(Map<String, dynamic> json, String? selector) {
    if (selector == null) return null;
    Object? cursor = json;
    for (final part in selector.split('.')) {
      if (cursor is! Map || !cursor.containsKey(part)) return null;
      cursor = cursor[part];
    }
    return cursor;
  }

  ExternalProfile project(Object? data) {
    if (data is! Map) throw const FormatException('Profile API must return an object');
    final object = Map<String, dynamic>.from(data);
    final display = _value(object, paths['displayName']);
    if (display is! String || display.trim().isEmpty || display.length > 250) {
      throw const FormatException('Expected mapped display name');
    }
    final emailValue = _value(object, paths['email']);
    final email = emailValue is String && emailValue.length <= 254 ? emailValue : null;
    // Deliberately do not auto-download avatar URLs: third-party image hosts
    // may track users, so rendering requires a separately approved media policy.
    return ExternalProfile(displayName: display.trim(), email: email,
      raw: FableImmutablePayload.object(data));
  }
}

class ExternalProfile {
  const ExternalProfile({required this.displayName, this.email, required this.raw});
  final String displayName;
  final String? email;
  /// All contract response fields, including unknown extensions, retained
  /// immutably in memory. The UI only displays explicitly mapped fields.
  final Map<String, dynamic> raw;
}

class ExternalProfileRepository {
  const ExternalProfileRepository({required this.gateway, required this.bindings, required this.fields});
  final ExternalApiGateway gateway;
  final ExternalFeatureBindings bindings;
  final ExternalProfileFields fields;

  Future<ExternalProfile> read() async {
    final response = await gateway.executeFeature(bindings: bindings, feature: 'profile', role: 'read');
    return fields.project(response.data);
  }
}

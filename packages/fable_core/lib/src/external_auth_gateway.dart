import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'external_api_gateway.dart';
import 'external_operation_catalog.dart';
import 'fable_api.dart';
import 'fable_session.dart';
import 'backend_transport_adapter.dart';
import 'backend_credential_provider.dart';

/// Configured by the CLI, pinned to exact external API contract fingerprints.
/// No assumption about JSON property names, paths, or refresh rotation.
class ExternalAuthBinding {
  const ExternalAuthBinding._(this.login,this.refresh,this.logout);
  final Map<String, dynamic> login;
  final Map<String, dynamic>? refresh;
  final Map<String, dynamic>? logout;

  static ExternalAuthBinding fromMap(Map<String, dynamic> value, ExternalOperationCatalog catalog) {
    if (value['schemaVersion'] != 1 || value['kind'] != 'fable.external-auth-binding' ||
        value['adapter'] != catalog.adapter || value['sourceHash'] != catalog.sourceHash ||
        value['operationsHash'] != catalog.operationsHash) {
      throw const FormatException('Authentication mapping does not match backend contract');
    }
    if (value['login'] is! Map) throw const FormatException('Missing explicit login mapping');
    final login = Map<String, dynamic>.from(value['login'] as Map);
    final refresh = value['refresh'] == null ? null : Map<String, dynamic>.from(value['refresh'] as Map);
    final logout = value['logout'] == null ? null : Map<String, dynamic>.from(value['logout'] as Map);
    _operation(catalog, login['operationId'], const {'POST'}, false);
    final request = _fields(login['request']);
    final response = _fields(login['response']);
    final identifier = _selector(request['identifier']);
    final password = _selector(request['password']);
    _selector(response['accessToken']);
    final loginRefresh = _selector(response['refreshToken'], optional: true);
    if (identifier == password || identifier!.startsWith('$password.') || password!.startsWith('$identifier.')) {
      throw const FormatException('Credential paths must not overlap');
    }
    if (response['accessToken'] == response['refreshToken']) {
      throw const FormatException('Token response paths must differ');
    }
    if (refresh != null) {
      if (loginRefresh == null) throw const FormatException('Refresh cannot work without login refresh token');
      _operation(catalog, refresh['operationId'], const {'POST'}, false);
      _selector(_fields(refresh['request'])['refreshToken']);
      final fields = _fields(refresh['response']);
      _selector(fields['accessToken']);
      _selector(fields['refreshToken'], optional: true);
    }
    if (logout != null) _operation(catalog, logout['operationId'], const {'POST', 'DELETE'}, true);
    return ExternalAuthBinding._(login, refresh, logout);
  }

  static Future<ExternalAuthBinding?> loadOptional(AssetBundle assets, ExternalOperationCatalog catalog) async {
    late final String raw;
    try { raw = await assets.loadString('assets/config/external-auth.json'); }
    on FlutterError { return null; }
    return fromMap(jsonDecode(raw) as Map<String, dynamic>, catalog);
  }

  static void _operation(ExternalOperationCatalog catalog, Object? id, Set<String> methods, bool bearer) {
    if (id is! String || !catalog.supports(id)) throw const FormatException('Auth operation unavailable');
    final op = catalog.require(id);
    if (!methods.contains(op.method) || op.requiresAuth != bearer || op.path.contains('{')) {
      throw const FormatException('Auth operation method, authorization, or route is incompatible');
    }
  }

  static Map<String, dynamic> _fields(Object? value) {
    if (value is! Map) throw const FormatException('Missing auth field projection');
    return Map<String, dynamic>.from(value);
  }

  static String? _selector(Object? value, {bool optional = false}) {
    if (optional && value == null) return null;
    if (value is! String || value.length > 160 ||
        !RegExp(r'^[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*){0,7}$').hasMatch(value) ||
        value.split('.').any((part) => const {'__proto__', 'constructor', 'prototype'}.contains(part))) {
      throw const FormatException('Unsafe/missing auth JSON selector');
    }
    return value;
  }

  static Object? _get(Object? body, String selector) {
    Object? value = body;
    for (final key in selector.split('.')) {
      if (value is! Map || !value.containsKey(key)) return null;
      value = value[key];
    }
    return value;
  }

  static Map<String, dynamic> _body(Map<String, String> paths) {
    final output = <String, dynamic>{};
    for (final item in paths.entries) {
      final parts = item.key.split('.');
      Map<String, dynamic> node = output;
      for (final part in parts.take(parts.length - 1)) {
        if (node[part] == null) node[part] = <String, dynamic>{};
        if (node[part] is! Map<String, dynamic>) throw const FormatException('Overlapping JSON paths');
        node = node[part] as Map<String, dynamic>;
      }
      final last = parts.last;
      if (node.containsKey(last)) throw const FormatException('Conflicting JSON fields');
      node[last] = item.value;
    }
    return output;
  }
}

class ExternalAuthGateway implements BackendApiGateway {
  ExternalAuthGateway({required this.catalog, required this.mapping, FableSecureSession? secureSession,
    Dio? client, bool allowHttpForLocalDevelopment = false,
    BackendCredentialProvider? credentialProvider}) :
    session = secureSession ?? secureSessionFor(catalog) {
    _gateway = ExternalApiGateway(catalog: catalog, session: session, client: client,
      refreshSession: mapping.refresh == null ? null : refresh,
      publicHeaders: catalog.publicHeaders, credentialProvider: credentialProvider,
      sessionMode: mapping.refresh == null
          ? BackendSessionMode.singleBearer : BackendSessionMode.rotatingBearer,
      allowHttpForLocalDevelopment: allowHttpForLocalDevelopment);
  }
  final ExternalOperationCatalog catalog;
  final ExternalAuthBinding mapping;
  final FableSecureSession session;
  late final ExternalApiGateway _gateway;

  /// Tokens for distinct URLs/contracts never share keys (even inside one app).
  static FableSecureSession secureSessionFor(ExternalOperationCatalog catalog) {
    final scope = sha256.convert(utf8.encode('${catalog.baseUri.origin}|${catalog.adapter}')).toString().substring(0, 32);
    return FableSecureSession(namespace: 'external.$scope');
  }

  static String _requiredToken(Object? json, String selector) {
    final value = ExternalAuthBinding._get(json, selector);
    if (value is! String || value.isEmpty || value.length > 8192 || value.contains(RegExp(r'[\r\n\x00-\x1f\x7f]'))) {
      throw const FormatException('Authentication response lacks a valid token');
    }
    return value;
  }

  Future<void> login({required String identifier, required String password}) async {
    if (identifier.trim().isEmpty || password.isEmpty) throw ArgumentError('Credentials required');
    final identityAtStart = session.identityRevision;
    final request = ExternalAuthBinding._fields(mapping.login['request']);
    final response = ExternalAuthBinding._fields(mapping.login['response']);
    final body = ExternalAuthBinding._body({
      ExternalAuthBinding._selector(request['identifier'])!: identifier.trim(),
      ExternalAuthBinding._selector(request['password'])!: password,
    });
    final result = await _gateway.execute(mapping.login['operationId'] as String, body: body);
    final access = _requiredToken(result.data, response['accessToken'] as String);
    final refreshPath = response['refreshToken'] as String?;
    final refreshToken = refreshPath == null ? null : _requiredToken(result.data, refreshPath);
    // Save only after BOTH credential fields were fully validated.
    final committed = await session.replaceTokensIfIdentity(expectedIdentity: identityAtStart,
      accessToken: access, refreshToken: refreshToken);
    if (!committed) throw FableApiException(409, 'session_changed_discard_response');
  }

  /// Authorization failures permanently invalidate a refresh session, but
  /// timeouts and 5xx errors do NOT clear credentials.
  Future<bool> refresh() async {
    final spec = mapping.refresh;
    if (spec == null) return false;
    final identityAtStart = session.identityRevision;
    final old = await session.refreshToken;
    if (old == null || old.isEmpty) return false;
    try {
      final request = ExternalAuthBinding._fields(spec['request']);
      final response = ExternalAuthBinding._fields(spec['response']);
      final result = await _gateway.execute(spec['operationId'] as String, body: ExternalAuthBinding._body({
        ExternalAuthBinding._selector(request['refreshToken'])!: old,
      }));
      final access = _requiredToken(result.data, response['accessToken'] as String);
      final rotationPath = response['refreshToken'] as String?;
      final rotated = rotationPath == null ? null : _requiredToken(result.data, rotationPath);
      if (session.identityRevision != identityAtStart) {
        // An account switch or sign-out invalidated this refresh attempt.
        return false;
      }
      return session.saveTokensIfIdentity(expectedIdentity: identityAtStart,
        accessToken: access, refreshToken: rotated, expectedRefreshToken: old);
    } on FableApiException catch (e) {
      if (e.status == 401 || e.status == 403) {
        await session.clearSessionIfIdentity(identityAtStart, expectedRefreshToken: old);
        return false;
      }
      rethrow;
    }
  }

  /// Always remove local credentials. false means remote revocation unconfirmed.
  Future<bool> logout() async {
    final identityAtStart = session.identityRevision;
    var revoked = false;
    try {
      final spec = mapping.logout;
      if (spec != null && await session.accessToken != null) {
        await _gateway.execute(spec['operationId'] as String);
        revoked = true;
      }
    } catch (_) { /* no false remote-success claim */ }
    finally { await session.clearSessionIfIdentity(identityAtStart); }
    return revoked;
  }
  @override
  Future<Response<dynamic>> execute(String operationId, {
    Map<String, dynamic>? path, Map<String, dynamic>? query, Object? body,
    CancelToken? cancelToken, String? ifMatch,
  }) => _gateway.execute(operationId, path:path, query:query, body:body,
      cancelToken:cancelToken, ifMatch:ifMatch);
  @override
  void dispose() => _gateway.dispose();
}

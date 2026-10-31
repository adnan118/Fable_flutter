import 'package:flutter/foundation.dart' show FlutterError;
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

abstract class OperationCatalog {
  bool get sendsInstallationId;
  bool supports(String operationId);
  FableOperation require(String operationId);
}

class FableOperation {
  const FableOperation(this.id, this.method, this.path, this.contractHash, {this.requiresAuth=true, this.enforceAuth=false, this.credentialHeader});
  final String id;
  final String method;
  final String path;
  final String contractHash;
  final bool requiresAuth;
  final bool enforceAuth;
  /// Set only for contract-declared non-Bearer credentials. The actual secret
  /// is provided at runtime and must never be serialized in assets.
  final String? credentialHeader;
}

/// Validated backend session policy. The exported value is a wizard/build-time hint;
/// GET /auth/session-policy is the authoritative deployed runtime setting.
class FableSessionPolicy {
  const FableSessionPolicy({required this.mode,required this.maxActive,
    required this.overflow,this.onePerInstallation,this.runtimeEndpoint});
  final String mode;
  final int maxActive;
  final String overflow;
  final bool? onePerInstallation;
  final String? runtimeEndpoint;

  bool get allowsMultipleSessions => mode=='multi' && (maxActive==0 || maxActive>1);

  factory FableSessionPolicy.fromMap(Map<String,dynamic> source) {
    final mode=source['mode'],max=source['maxActive'],overflow=source['overflow'];
    final installation=source['onePerInstallation'],endpoint=source['runtimeEndpoint'];
    if(mode is! String || !const {'single','multi'}.contains(mode) ||
       max is! int || max<0 || max>100 ||
       (mode=='single' && max!=1) ||
       overflow is! String || !const {'revoke-oldest','reject-new'}.contains(overflow) ||
       (installation!=null && installation is! bool) ||
       (endpoint!=null && endpoint!='/auth/session-policy')) {
      throw const FormatException('Invalid backend session policy contract');
    }
    return FableSessionPolicy(mode:mode,maxActive:max,overflow:overflow,
      onePerInstallation:installation as bool?,runtimeEndpoint:endpoint as String?);
  }
}

/// Never guess routes. Every request must be found in the backend's actual export.
class FableContract implements OperationCatalog {
  @override bool get sendsInstallationId => true;
  const FableContract({required this.contractHash, required this.operations,
    required this.featureIds, required this.projectName, required this.selectionMode,
    this.sessionPolicy,this.frontendSetup});
  final String contractHash;
  final Map<String, FableOperation> operations;
  final Set<String> featureIds;
  final String projectName;
  final String selectionMode;
  /// Null on legacy exports: never interpret missing policy as multi-device.
  final FableSessionPolicy? sessionPolicy;
  /// Read-only, signed frontend-setup decisions from Fable Backend.
  final Map<String,dynamic>? frontendSetup;
  /// Null denotes a legacy export. A new Backend contract must explicitly say
  /// which client features are enabled; disabled features never appear as tiles.
  Set<String>? get backendVisibleFeatureIds {
    final setup=frontendSetup;
    if(setup==null)return null;
    final choices=setup['decisions'];
    if(choices is! Map)return null;
    final features=choices['frontendFeatures'];
    if(features is! Map)return null;
    final ids=features['enabled'];
    if(ids is! List)return null;
    return Set<String>.unmodifiable(ids.whereType<String>());
  }
  bool isFeatureAvailable(String featureId) =>
    backendVisibleFeatureIds?.contains(featureId) ?? true;


  static FableContract fromMaps(Map<String, dynamic> handoff,
      Map<String, dynamic> contract,
      Map<String, dynamic> openApi, {Map<String, dynamic>? mobileCore}) {
    if (handoff['kind'] != 'fable.flutter-handoff' || handoff['client'] != 'flutter' || handoff['schemaVersion'] != 1) {
      throw const FormatException('Unsupported Flutter handoff');
    }
    final integrity = handoff['manifestHash'];
    final unsigned = Map<String, dynamic>.of(handoff)..remove('manifestHash');
    if (integrity is! String || sha256.convert(utf8.encode(jsonEncode(unsigned))).toString() != integrity) {
      throw const FormatException('Handoff integrity mismatch');
    }
    final backend = handoff['backend'] as Map<String, dynamic>;
    final digest = backend['contractHash'];
    if (digest is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(digest) || contract['contractHash'] != digest) {
      throw const FormatException('Backend contract hash mismatch');
    }
    final ops = <String, FableOperation>{};
    final paths = openApi['paths'];
    if (paths is Map) {
      for (final pair in paths.entries) {
        if (pair.key is! String || pair.value is! Map) continue;
        for (final route in (pair.value as Map).entries) {
          if (!const {'get','post','put','delete','patch','head'}.contains(route.key)) continue;
          if (route.value is! Map) continue;
          final info = route.value as Map;
          final id = info['operationId'];
          if (id is! String || id.isEmpty || ops.containsKey(id)) throw const FormatException('Duplicate/missing operation ID');
          final isPublic=info['x-fable-public'];
          final actualHash=info['x-fable-contract-hash'];
          if (isPublic is! bool || actualHash is! String || actualHash.isEmpty ||
              (info['security'] is List &&
               ((isPublic && (info['security'] as List).isNotEmpty) ||
                (!isPublic && (info['security'] as List).isEmpty)))) {
            throw const FormatException('Fable operation authorization metadata is missing or inconsistent');
          }
          ops[id] = FableOperation(id, (route.key as String).toUpperCase(), pair.key as String,
            actualHash, requiresAuth:!isPublic,enforceAuth:true);
        }
      }
    }

    if (mobileCore != null) {
      if(mobileCore['kind'] != 'fable.mobile-core-operations' || mobileCore['schemaVersion'] != 1 || mobileCore['backendContractHash'] != digest) {
        throw const FormatException('Mobile core contract mismatch');
      }
      final extra = mobileCore['operations'];
      if(extra is! List || sha256.convert(utf8.encode(jsonEncode(extra))).toString() != mobileCore['operationsHash']){
        throw const FormatException('Mobile core operations integrity mismatch');
      }
      final seenCoreOperations=<String>{};
      for(final operation in extra){
        if(operation is! Map)throw const FormatException('Malformed mobile core operation');
        final id=operation['operationId'],method=operation['method'],path=operation['path'];
        final isPublic=operation['public'];
        if(id is! String || id.isEmpty || !seenCoreOperations.add(id) ||
          method is! String || path is! String || isPublic is! bool ||
          !path.startsWith('/') || path.startsWith('//') ||
          !const {'GET','POST','PATCH','DELETE','PUT','HEAD'}.contains(method)){
          throw const FormatException('Invalid or duplicate mobile core operation');
        }
        final existing=ops[id];
        if(existing!=null){
          // RC66 can export core Auth routes in both OpenAPI and mobile-core.
          // Accept the same operation only when verb, URL and auth policy agree.
          // Never replace the signed OpenAPI operation with conflicting metadata.
          if(existing.method!=method || existing.path!=path ||
              existing.requiresAuth==isPublic || !existing.enforceAuth){
            throw const FormatException('Conflicting OpenAPI / mobile-core operation');
          }
          continue;
        }
        ops[id]=FableOperation(id,method,path,mobileCore['operationsHash'] as String,
          requiresAuth:!isPublic,enforceAuth:true);
      }
    }
    final exportedSetup=(contract['core'] is Map)
      ? (contract['core'] as Map)['frontendSetup']:null;
    final handoffSetup=handoff['frontendSetup'];
    if((exportedSetup==null)!=(handoffSetup==null)) {
      throw const FormatException('Frontend decisions handoff missing or stale');
    }
    Map<String,dynamic>? frontendSetup;
    if(exportedSetup!=null){
      if(exportedSetup is! Map || handoffSetup is! Map ||
        jsonEncode(exportedSetup)!=jsonEncode(handoffSetup)) {
        throw const FormatException('Frontend decisions conflict with backend contract');
      }
      final parsed=Map<String,dynamic>.from(exportedSetup);
      final project=contract['project'] as Map?;
      if(parsed['kind']!='fable.frontend-setup-decisions' ||
        parsed['schemaVersion']!=1 || parsed['projectId']!=project?['id'] ||
        parsed['steps'] is! List || parsed['decisions'] is! Map){
        throw const FormatException('Invalid backend frontend-setup decisions');
      }
      final choices=parsed['decisions'];
      if(choices is! Map)throw const FormatException('Invalid frontend decisions');
      final featurePolicy=choices['frontendFeatures'];
      if(featurePolicy!=null){
        if(featurePolicy is! Map || featurePolicy['schemaVersion']!=1 ||
          featurePolicy['source']!='backend-installed-capabilities' ||
          featurePolicy['enabled'] is! List ||
          !(featurePolicy['enabled'] as List).every((item)=>item is String && item.isNotEmpty) ||
          featurePolicy['disabled'] is! List ||
          !(featurePolicy['disabled'] as List).every((item)=>item is String && item.isNotEmpty)) {
          throw const FormatException('Invalid backend feature visibility');
        }
        final enabled=(featurePolicy['enabled'] as List).cast<String>().toSet();
        final disabled=(featurePolicy['disabled'] as List).cast<String>().toSet();
        if(enabled.length!=(featurePolicy['enabled'] as List).length ||
          disabled.length!=(featurePolicy['disabled'] as List).length ||
          enabled.intersection(disabled).isNotEmpty ||
          !enabled.contains('auth') || !enabled.contains('access_control')){
          throw const FormatException('Backend feature visibility policy conflicts');
        }
      }
      frontendSetup=Map<String,dynamic>.unmodifiable(parsed);
    }
    final coreConfig=contract['core'];
    final authConfig=coreConfig is Map ? coreConfig['auth'] : null;
    final declaredPolicy=authConfig is Map ? authConfig['sessionPolicy'] : null;
    if(declaredPolicy!=null && declaredPolicy is! Map) {
      throw const FormatException('Malformed backend session policy contract');
    }
    final sessionPolicy=declaredPolicy is Map
      ? FableSessionPolicy.fromMap(Map<String,dynamic>.from(declaredPolicy)) : null;
    final mode = (handoff['selection'] as Map)['mode'] as String? ?? 'advisory';
    final selection = (handoff['selection'] as Map)['features'];
    return FableContract(contractHash:digest, operations:ops,
      featureIds: selection is List ? selection.whereType<String>().toSet() : <String>{},
      projectName: (backend['project'] as Map?)?['name']?.toString() ?? 'Fable',
      selectionMode:mode,sessionPolicy:sessionPolicy,
      frontendSetup:frontendSetup);
  }

  static Future<FableContract> fromAssets(AssetBundle bundle) async {
    final parts = await Future.wait([
      bundle.loadString('assets/contracts/flutter-handoff.json'),
      bundle.loadString('assets/contracts/contract.json'),
      bundle.loadString('assets/contracts/openapi.json'),
    ]);
    Map<String,dynamic>? core;
    try {core=jsonDecode(await bundle.loadString('assets/contracts/mobile-core-operations.json')) as Map<String,dynamic>;}
    on FlutterError {core=null;}
    return fromMaps(jsonDecode(parts[0]) as Map<String,dynamic>,
      jsonDecode(parts[1]) as Map<String,dynamic>, jsonDecode(parts[2]) as Map<String,dynamic>,mobileCore:core);
  }

  bool supports(String operationId) => operations.containsKey(operationId);
  FableOperation require(String operationId) {
    final op = operations[operationId];
    if (op == null) throw StateError('Operation not in backend contract: $operationId');
    return op;
  }
}

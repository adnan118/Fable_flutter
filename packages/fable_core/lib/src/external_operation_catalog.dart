import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'fable_contract.dart';

/// Import only catalogs produced and validated by `fable mobile backend import`.
/// Custom backend semantics (including login/refresh payload formats) are not guessed.
class ExternalOperationCatalog implements OperationCatalog {
  @override bool get sendsInstallationId => false;
  ExternalOperationCatalog._(this.adapter,this.baseUri,this.sourceHash,this.operationsHash,this.operations,
    this.publicHeaders);
  final String adapter;
  final Uri baseUri;
  final String sourceHash;
  final String operationsHash;
  final Map<String,FableOperation> operations;
  final Map<String,String> publicHeaders;

  static bool _validCredentialHeader(Object? value) {
    if (value is! String || !RegExp(r'^[A-Za-z][A-Za-z0-9-]{0,63}$').hasMatch(value)) return false;
    return !const {'host','cookie','set-cookie','connection','content-length','transfer-encoding','origin','referer','proxy-authorization','x-forwarded-for','x-forwarded-host','forwarded','x-installation-id'}.contains(value.toLowerCase());
  }

  factory ExternalOperationCatalog.fromMap(Map<String,dynamic> value) {
    if(value['schemaVersion']!=1 || value['kind']!='fable.external-operation-catalog' ||
      !const {'openapi','custom'}.contains(value['adapter'])) {
      throw const FormatException('Unsupported external backend catalog');
    }
    final adapter=value['adapter'] as String;
    final url=value['baseUrl'];
    if(url is! String)throw const FormatException('Missing backend URL');
    final baseUri=Uri.tryParse(url);
    if(baseUri==null || !baseUri.hasAuthority || baseUri.userInfo.isNotEmpty ||
      baseUri.path.isNotEmpty || baseUri.hasQuery || baseUri.hasFragment ||
      !(baseUri.scheme=='https' || (baseUri.scheme=='http' &&
        const {'localhost','127.0.0.1','10.0.2.2','::1'}.contains(baseUri.host)))) {
      throw const FormatException('Unsafe backend base URL');
    }
    final source=value['sourceHash'];
    if(source is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(source)) {
      throw const FormatException('Missing source fingerprint');
    }
    final list=value['operations'];
    if(list is! List || list.isEmpty || list.length>2000)throw const FormatException('Missing operations');
    if(value['operationsHash']!=sha256.convert(utf8.encode(jsonEncode(list))).toString()) {
      throw const FormatException('External operations integrity mismatch');
    }
    final found=<String,FableOperation>{};
    final routes=<String>{};
    for(final item in list){
      if(item is! Map)throw const FormatException('Malformed operation');
      final id=item['operationId'],method=item['method'],path=item['path'],auth=item['auth'];
      if(id is! String || !RegExp(r'^[A-Za-z][A-Za-z0-9._-]{1,127}$').hasMatch(id) ||
        method is! String || !const {'GET','POST','PUT','PATCH','DELETE','HEAD'}.contains(method) ||
        path is! String || !path.startsWith('/') || path.startsWith('//') ||
        path.contains('..') || path.contains('\\') || path.contains('?') || path.contains('#') || path.contains('%') ||
        RegExp(r'\s|%2f|%5c|%2e|%00',caseSensitive:false).hasMatch(path) ||
        !const {'bearer','none','provider'}.contains(auth) || found.containsKey(id) ||
        !routes.add('$method $path') ||
        (auth=='provider' && !_validCredentialHeader(item['credentialHeader'])) ||
        (auth!='provider' && item.containsKey('credentialHeader')))throw const FormatException('Unsafe/duplicate external operation');
      found[id]=FableOperation(id,method,path,value['operationsHash'] as String,
        requiresAuth:auth!='none',enforceAuth:true,
        credentialHeader:auth=='provider' ? item['credentialHeader'] as String : null);
    }
    return ExternalOperationCatalog._(adapter,baseUri,source,value['operationsHash'] as String,Map.unmodifiable(found),const {});
  }

  static Future<ExternalOperationCatalog> fromAssets(AssetBundle bundle) async {
    final data=await bundle.loadString('assets/contracts/external-operations.json');
    final catalog=ExternalOperationCatalog.fromMap(jsonDecode(data) as Map<String,dynamic>);
    late final String settings;
    try { settings=await bundle.loadString('assets/config/external-transport.json'); }
    on FlutterError { return catalog; }
    final raw=jsonDecode(settings);
    if(raw is! Map<String,dynamic> || raw['schemaVersion']!=1 ||
      raw['kind']!='fable.external-transport' || raw['adapter']!=catalog.adapter ||
      raw['baseUrl']!=catalog.baseUri.toString() || raw['publicHeaders'] is! Map) {
      throw const FormatException('Transport settings do not match selected backend');
    }
    final headers=Map<String,String>.from(raw['publicHeaders'] as Map);
    return ExternalOperationCatalog._(catalog.adapter,catalog.baseUri,catalog.sourceHash,
      catalog.operationsHash,catalog.operations,headers);
  }

  @override bool supports(String operationId)=>operations.containsKey(operationId);
  @override FableOperation require(String operationId) {
    final op=operations[operationId];
    if(op==null)throw StateError('Unknown external backend operation: $operationId');
    return op;
  }
}

import 'package:flutter/foundation.dart' show FlutterError;
import 'dart:convert';
import 'package:flutter/services.dart';
import 'external_operation_catalog.dart';

/// Named domain roles explicitly bound by the CLI to a verified API contract.
/// A semantic role without a binding is unavailable, not guessed.
class ExternalFeatureBindings {
  ExternalFeatureBindings._(this.bindings);
  factory ExternalFeatureBindings.empty() => ExternalFeatureBindings._(const {});
  final Map<String, Map<String, String>> bindings;

  static ExternalFeatureBindings fromMap(Map<String,dynamic> manifest,ExternalOperationCatalog catalog) {
    if(manifest['schemaVersion']!=1||manifest['kind']!='fable.feature-operation-bindings'||
      manifest['adapter']!=catalog.adapter||manifest['sourceHash']!=catalog.sourceHash||
      manifest['operationsHash']!=catalog.operationsHash) {
      throw const FormatException('Feature bindings do not match the imported API catalog');
    }
    const methods=<String,List<String>>{
      'read':['GET','HEAD'],'list':['GET'],'create':['POST'],'update':['PUT','PATCH'],'remove':['DELETE'],
      'markRead':['POST','PUT','PATCH'],
    };
    final raw=manifest['bindings'];
    if(raw is! Map)throw const FormatException('Feature operation mappings are invalid');
    final result=<String,Map<String,String>>{};
    for(final entry in raw.entries){
      if(entry.key is! String||entry.value is! Map)throw const FormatException('Invalid feature operation mapping');
      final actions=<String,String>{};
      for(final action in (entry.value as Map).entries){
        if(action.key is! String||action.value is! String||!methods.containsKey(action.key) ||
            (action.key=='markRead' && entry.key!='notifications')) {
          throw const FormatException('Unknown feature operation role');
        }
        final op=catalog.require(action.value as String);
        if(!methods[action.key]!.contains(op.method))throw const FormatException('Feature operation verb mismatch');
        final params=RegExp(r'\{([a-zA-Z_][a-zA-Z0-9_]*)\}').allMatches(op.path).map((m)=>m.group(1)).toList();
        if(entry.key=='notifications' && (!op.requiresAuth || op.credentialHeader!=null ||
            (action.key=='list' && params.isNotEmpty) ||
            (action.key=='markRead' && (params.length!=1 || params.single!='id')))) {
          throw const FormatException('Notification operation requires auth; markRead requires an id path');
        }
        actions[action.key as String]=op.id;
      }
      result[entry.key as String]=Map.unmodifiable(actions);
    }
    return ExternalFeatureBindings._(Map.unmodifiable(result));
  }

  static Future<ExternalFeatureBindings?> loadOptional(AssetBundle assets,ExternalOperationCatalog catalog) async {
    late final String text;
    try {text=await assets.loadString('assets/config/feature-operations.json');}
    on FlutterError {return null;}
    return fromMap(jsonDecode(text) as Map<String,dynamic>,catalog);
  }
  String? operation(String feature,String role)=>bindings[feature]?[role];
}

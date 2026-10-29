import 'dart:convert';
import 'package:flutter/services.dart';

/// The backend is an explicit per-app decision. This class never auto-detects
/// Fable, and no sample backend contract is a valid substitute for selection.
class BackendSelection {
  const BackendSelection({required this.kind,required this.adapter,required this.status,required this.contractImported});
  final String kind;
  final String adapter;
  final String status;
  final bool contractImported;

  bool get canUseExternalCatalog => kind=='other' && contractImported && status=='ready';
  bool get isFable => kind=='fable';
  bool get canUseFableContract => isFable && contractImported && status=='ready';

  factory BackendSelection.fromMap(Map<String,dynamic> json) {
    if(json['schemaVersion']!=1 || json['kind']!='fable.mobile-backend-configuration'){
      throw const FormatException('Unsupported backend configuration format');
    }
    final backend=json['backend'];
    if(backend is! Map<String,dynamic>)throw const FormatException('Invalid backend configuration');
    final kind=backend['kind'],adapter=backend['adapter'],status=backend['status'];
    final fable=kind=='fable' && adapter=='fable-contract';
    final other=kind=='other' && (adapter=='openapi'||adapter=='custom');
    if(!fable&&!other)throw const FormatException('Unsupported backend type or adapter');
    if(status is! String || status.isEmpty || json['contractImported'] is! bool){
      throw const FormatException('Incomplete backend configuration');
    }
    if(status=='ready' && !json['contractImported'])throw const FormatException('Backend cannot be ready without contract');
    return BackendSelection(kind:kind as String,adapter:adapter as String,
      status:status,contractImported:json['contractImported'] as bool);
  }
  static Future<BackendSelection> fromAssets(AssetBundle bundle) async {
    final content=await bundle.loadString('assets/config/backend.json');
    return BackendSelection.fromMap(jsonDecode(content) as Map<String,dynamic>);
  }
}

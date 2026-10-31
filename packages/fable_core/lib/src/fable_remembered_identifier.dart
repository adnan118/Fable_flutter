import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Opt-in non-secret identifier memory, separately scoped per backend contract.
/// Never stores a password, an OTP, cookies or a bearer token.
class FableRememberedIdentifier {
  FableRememberedIdentifier({required String backendScope, FlutterSecureStorage? storage})
    : _key='fable.login.identifier.${sha256.convert(utf8.encode(backendScope)).toString().substring(0,40)}',
      _storage=storage??const FlutterSecureStorage(){
    final scope=Uri.tryParse(backendScope);
    if(scope==null || !scope.hasAuthority || scope.userInfo.isNotEmpty ||
       !(scope.scheme=='https'||(scope.scheme=='http' &&
         const {'localhost','127.0.0.1','10.0.2.2','::1'}.contains(scope.host)))) {
      throw ArgumentError('A trusted backend URL is required to scope remembered identifiers');
    }
  }
  final String _key;
  final FlutterSecureStorage _storage;

  Future<String?> load() async {
    final value=await _storage.read(key:_key);
    if(value==null||value.length>191 || value.trim().isEmpty ||
       value.contains(RegExp(r'[\x00-\x1F\x7F]')))return null;
    return value;
  }

  Future<void> save({required String identifier,required bool remember}) async {
    if(!remember){await _storage.delete(key:_key);return;}
    final clean=identifier.trim();
    if(clean.isEmpty||clean.length>191||clean.contains(RegExp(r'[\x00-\x1F\x7F]')))
      throw ArgumentError('Invalid identifier for secure storage');
    await _storage.write(key:_key,value:clean);
  }
  Future<void> clear()=>_storage.delete(key:_key);
}

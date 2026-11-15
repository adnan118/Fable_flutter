import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'biometrics_repository.dart';
import 'passkey_registration.dart';

/// Native WebAuthn platform adapter for an explicitly invoked user gesture.
/// The OS stores private credentials. Dart receives only the public WebAuthn
/// result JSON required by the Fable server's cryptographic verifier.
///
/// Project setup MUST separately bind the server RP ID to the Android signing
/// certificate via Digital Asset Links and to iOS Associated Domains.
/// This class never guesses an RP or downgrades to a software credential.
final class FableNativePasskeys
    implements FablePasskeyAuthenticator, FablePasskeyCreator {
  FableNativePasskeys({MethodChannel? channel})
      : _channel=channel ?? const MethodChannel('fable/passkeys_native_v1');

  final MethodChannel _channel;
  static const _limit=131072;

  Future<Map<String,dynamic>?> _invoke(
      String method,Map<String,dynamic> serverOptions) async {
    if(kIsWeb || (defaultTargetPlatform!=TargetPlatform.android &&
        defaultTargetPlatform!=TargetPlatform.iOS)){
      throw UnsupportedError('Native platform passkeys require Android or iOS');
    }
    // Use only server-provided public WebAuthn options. No key material,
    // attestation secret, auth token, or private credential goes to the OS
    // channel. The platform performs a real system-owned user gesture.
    if(serverOptions['challenge'] is! String ||
        (serverOptions['challenge'] as String).length<16 ||
        jsonEncode(serverOptions).length>_limit){
      throw const FormatException('Invalid server-issued passkey options');
    }
    try{
      final raw=await _channel.invokeMethod<String>(method,{
        'options':serverOptions,
      });
      if(raw==null)return null;
      if(raw.length<24||raw.length>_limit){
        throw const FormatException('Native passkey result is out of bounds');
      }
      final value=jsonDecode(raw);
      if(value is! Map || value['id'] is! String ||
          value['rawId'] is! String || value['type']!='public-key' ||
          value['response'] is! Map){
        throw const FormatException('Malformed platform WebAuthn credential');
      }
      return Map<String,dynamic>.from(value);
    }on PlatformException catch(error){
      if(error.code=='USER_CANCELLED')return null;
      rethrow;
    }
  }

  @override
  Future<Map<String,dynamic>?> getAssertion(
      Map<String,dynamic> publicKeyOptions)=>
      _invoke('authenticate',publicKeyOptions);

  @override
  Future<Map<String,dynamic>?> createCredential(
      Map<String,dynamic> publicKeyOptions)=>
      _invoke('register',publicKeyOptions);
}

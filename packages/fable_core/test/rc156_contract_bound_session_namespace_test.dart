import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fable_core/fable_core.dart';

/// RC156: regression for accidental sharing of Keychain/Keystore tokens across
/// separate imported API contracts on the same origin and display name.
FableContract _fable(String fingerprint,{String displayName='Shared Name'}) =>
    FableContract(
      contractHash:fingerprint,
      projectName:displayName,
      selectionMode:'explicit',
      featureIds: const <String>{},
      operations:const <String,FableOperation>{},
    );

ExternalOperationCatalog _other(String sourceFingerprint,{
    String suffix='',String host='https://shared.example.test'}) {
  final operations=<Map<String,String>>[
    {'operationId':'public.ping','method':'GET',
      'path':'/ping$suffix','auth':'none'},
  ];
  final opHash=sha256.convert(utf8.encode(jsonEncode(operations))).toString();
  return ExternalOperationCatalog.fromMap({
    'schemaVersion':1,
    'kind':'fable.external-operation-catalog',
    'adapter':'openapi',
    'baseUrl':host,
    'sourceHash':sourceFingerprint,
    'operationsHash':opHash,
    'operations':operations,
  });
}

void main() {
  final a=List<String>.filled(64,'a').join();
  final b=List<String>.filled(64,'b').join();
  final origin=Uri.parse('https://shared.example.test');

  test('RC156 Fable two projects with same host/name but different contract cannot share tokens',(){
    final first=FableAuthGateway.sessionNamespaceFor(origin,_fable(a));
    final second=FableAuthGateway.sessionNamespaceFor(origin,_fable(b));
    expect(first,startsWith('fable.'));
    expect(second,startsWith('fable.'));
    expect(first,isNot(second));
    final oldNameOnly='fable.${sha256.convert(utf8.encode('${origin.origin}|Shared Name')).toString().substring(0,32)}';
    expect(first,isNot(oldNameOnly),'legacy name-only token key must not be reused');
    expect(second,isNot(oldNameOnly));
    final firstSession=FableSecureSession(namespace:first);
    final secondSession=FableSecureSession(namespace:second);
    expect(firstSession.sharesIdentityNamespaceWith(secondSession),false);
  });

  test('RC156 Fable same verified export and origin do share one identity scope',(){
    final first=FableAuthGateway.sessionNamespaceFor(origin,_fable(a));
    final second=FableAuthGateway.sessionNamespaceFor(origin,_fable(a));
    expect(first,second);
    expect(FableSecureSession(namespace:first).sharesIdentityNamespaceWith(
      FableSecureSession(namespace:second)),true);
    expect(FableAuthGateway.sessionNamespaceFor(
      Uri.parse('https://second.example.test'),_fable(a)),isNot(first));
    expect(FableAuthGateway.sessionNamespaceFor(origin,_fable(a,displayName:'Other Name')),isNot(first));
  });

  test('RC156 Other Backend isolates same-origin different imported source/operation hashes',(){
    final original=ExternalAuthGateway.secureSessionFor(_other(a));
    final anotherSource=ExternalAuthGateway.secureSessionFor(_other(b));
    final anotherOperations=ExternalAuthGateway.secureSessionFor(_other(a,suffix:'-v2'));
    final same=ExternalAuthGateway.secureSessionFor(_other(a));
    expect(original.sharesIdentityNamespaceWith(anotherSource),false);
    expect(original.sharesIdentityNamespaceWith(anotherOperations),false);
    expect(original.sharesIdentityNamespaceWith(same),true);
    expect(original.sharesIdentityNamespaceWith(
      ExternalAuthGateway.secureSessionFor(_other(a,host:'https://other.example.test'))),false);
  });

  test('RC156 Fable and Other never share session identity even on same origin',(){
    final fableSession=FableSecureSession(namespace:
      FableAuthGateway.sessionNamespaceFor(origin,_fable(a)));
    final external=ExternalAuthGateway.secureSessionFor(_other(a));
    expect(fableSession.sharesIdentityNamespaceWith(external),false);
  });
}

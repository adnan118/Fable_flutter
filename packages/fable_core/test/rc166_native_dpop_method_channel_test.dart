import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fable_core/fable_core.dart';

const _native = MethodChannel('fable/dpop_native_v1');

String _proof() => [
  List<String>.filled(110,'a').join(),
  List<String>.filled(110,'b').join(),
  List<String>.filled(110,'c').join(),
].join('.');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_native, null);
  });

  test('RC166 native bridge sends exact method, htu, origin and ath token input', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_native,(call) async {
      calls.add(call);
      return _proof();
    });
    final signer = FableNativeDpopProofSigner(
      serverOrigin: Uri.parse('https://api.example.test'),
    );
    final actual = await signer.signProof(
      method:'GET',htu:Uri.parse('https://api.example.test/auth/me/account'),
      accessToken:List<String>.filled(96,'t').join(),
    );
    expect(actual,_proof());
    expect(calls.length,1);
    expect(calls.single.method,'sign');
    final sent = Map<String,dynamic>.from(calls.single.arguments as Map);
    expect(sent['method'],'GET');
    expect(sent['htu'],'https://api.example.test/auth/me/account');
    expect(sent['origin'],'https://api.example.test');
    expect(sent['accessToken'],List<String>.filled(96,'t').join());
  });

  test('RC166 public login proof never adds accessToken or fake ath', () async {
    Map<dynamic,dynamic>? params;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_native,(call) async {
      params=call.arguments as Map;
      return _proof();
    });
    final signer=FableNativeDpopProofSigner(
      serverOrigin:Uri.parse('https://api.example.test'));
    await signer.signProof(method:'POST',
      htu:Uri.parse('https://api.example.test/auth/login'));
    expect(params?.containsKey('accessToken'),false);
  });

  test('RC166 rejects different host, HTTP, query or fragment before native call', () async {
    var calls=0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_native,(call) async {
      calls++;return _proof();
    });
    final signer=FableNativeDpopProofSigner(
      serverOrigin:Uri.parse('https://api.example.test'));
    for(final bad in [
      'https://evil.example.test/account',
      'http://api.example.test/account',
      'https://api.example.test/account?token=1',
      'https://api.example.test/account#fragment',
    ]) {
      await expectLater(
        signer.signProof(method:'GET',htu:Uri.parse(bad)),
        throwsArgumentError,
      );
    }
    expect(calls,0);
  });

  test('RC166 forbids malformed origin and credentials', () async {
    expect(()=>FableNativeDpopProofSigner(
      serverOrigin:Uri.parse('http://api.example.test')),throwsArgumentError);
    expect(()=>FableNativeDpopProofSigner(
      serverOrigin:Uri.parse('https://api.example.test:443/path')),throwsArgumentError);
    final signer=FableNativeDpopProofSigner(
      serverOrigin:Uri.parse('https://api.example.test'));
    await expectLater(signer.signProof(method:'GET',
      htu:Uri.parse('https://api.example.test/account'),
      accessToken:'short'),throwsArgumentError);
  });

  test('RC166 device signer fails closed on missing hardware channel', () async {
    final signer=FableNativeDpopProofSigner(
      serverOrigin:Uri.parse('https://api.example.test'));
    await expectLater(
      signer.signProof(method:'GET',htu:Uri.parse('https://api.example.test/me')),
      throwsA(isA<MissingPluginException>()),
    );
  });

  test('RC166 malformed signed JWS never returns to API client', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_native,(call) async => 'not.a.jwt');
    final signer=FableNativeDpopProofSigner(
      serverOrigin:Uri.parse('https://api.example.test'));
    await expectLater(signer.signProof(
      method:'GET',htu:Uri.parse('https://api.example.test/me')),
      throwsStateError);
  });
}

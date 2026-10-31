import 'package:flutter_test/flutter_test.dart';
import 'package:fable_core/fable_core.dart';

void main(){
  test('Backend-specific remembered identifiers require trusted HTTPS scopes',(){
    expect(()=>FableRememberedIdentifier(backendScope:'https://api.example.test'),returnsNormally);
    expect(()=>FableRememberedIdentifier(backendScope:'http://localhost:3120'),returnsNormally);
    for(final bad in [
      'http://api.example.test','https://name:pass@api.example.test',
      'javascript:alert(1)','file:///tmp/saved-password',
      'https://','ftp://api.example.test',
    ])expect(()=>FableRememberedIdentifier(backendScope:bad),throwsArgumentError);
  });
}

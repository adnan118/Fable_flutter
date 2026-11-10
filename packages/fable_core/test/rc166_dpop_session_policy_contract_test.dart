import 'package:flutter_test/flutter_test.dart';
import 'package:fable_core/fable_core.dart';

Map<String,dynamic> policy([Object? dpop]) => <String,dynamic>{
  'mode':'multi',
  'maxActive':5,
  'overflow':'revoke-oldest',
  'onePerInstallation':true,
  'runtimeEndpoint':'/auth/session-policy',
  if(dpop!=null)'dpop':dpop,
};

void main(){
  test('RC166 legacy session policy does not assume DPoP is supported',(){
    final parsed=FableSessionPolicy.fromMap(policy());
    expect(parsed.dpopFlutterMode,isNull);
    expect(parsed.requiresNativeDpop,false);
  });
  test('RC166 explicit required DPoP is recognized from Backend policy',(){
    final parsed=FableSessionPolicy.fromMap(policy({
      'flutter':'required','proofType':'dpop+jwt','algorithm':'ES256',
    }));
    expect(parsed.dpopFlutterMode,'required');
    expect(parsed.requiresNativeDpop,true);
  });
  test('RC166 explicit off preserves existing Bearer session behavior',(){
    final parsed=FableSessionPolicy.fromMap(policy({
      'flutter':'off','proofType':'dpop+jwt','algorithm':'ES256',
    }));
    expect(parsed.dpopFlutterMode,'off');
    expect(parsed.requiresNativeDpop,false);
  });
  test('RC166 invalid modes fail closed instead of being downgraded',(){
    for(final mode in ['optional','true','enabled','broken','']){
      expect(()=>FableSessionPolicy.fromMap(policy({
        'flutter':mode,'proofType':'dpop+jwt','algorithm':'ES256',
      })),throwsFormatException);
    }
  });
  test('RC166 unexpected proofType or cryptographic algorithm fails closed',(){
    for(final dpop in [
      {'flutter':'required','proofType':'JWT','algorithm':'ES256'},
      {'flutter':'required','proofType':'dpop+jwt','algorithm':'none'},
      {'flutter':'required','proofType':'dpop+jwt'},
      {'flutter':'required','algorithm':'ES256'},
      <String,dynamic>{},
      'required',
    ]){
      expect(()=>FableSessionPolicy.fromMap(policy(dpop)),throwsFormatException);
    }
  });
}

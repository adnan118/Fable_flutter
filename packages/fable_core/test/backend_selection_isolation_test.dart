import 'package:flutter_test/flutter_test.dart';
import 'package:fable_core/fable_core.dart';

Map<String,dynamic> selection(String kind,String adapter,String status,bool imported)=> {
  'schemaVersion':1,
  'kind':'fable.mobile-backend-configuration',
  'backend':{'kind':kind,'adapter':adapter,'status':status},
  'contractImported':imported,
};

void main(){
  test('An external Backend pending a verified contract cannot load any Fable operation',(){
    final other=BackendSelection.fromMap(selection('other','openapi','pending',false));
    expect(other.isFable,false);
    expect(other.canUseFableContract,false);
    expect(other.canUseExternalCatalog,false);
  });
  test('Imported external Backend uses only its own OpenAPI/custom adapter',(){
    for(final adapter in ['openapi','custom']){
      final other=BackendSelection.fromMap(selection('other',adapter,'ready',true));
      expect(other.canUseExternalCatalog,true);
      expect(other.canUseFableContract,false);
    }
  });
  test('Selecting Fable never falls back to a coincidentally present external contract',(){
    final fable=BackendSelection.fromMap(selection('fable','fable-contract','ready',true));
    expect(fable.canUseFableContract,true);
    expect(fable.canUseExternalCatalog,false);
  });
  test('Other backend cannot impersonate Fable adapter or claim ready without contract',(){
    expect(()=>BackendSelection.fromMap(selection('other','fable-contract','ready',true)),throwsFormatException);
    expect(()=>BackendSelection.fromMap(selection('fable','openapi','ready',true)),throwsFormatException);
    expect(()=>BackendSelection.fromMap(selection('other','openapi','ready',false)),throwsFormatException);
  });
}

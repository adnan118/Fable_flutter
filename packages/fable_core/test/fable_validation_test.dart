import 'package:flutter_test/flutter_test.dart';
import 'package:fable_core/fable_core.dart';
void main(){
  test('validates inputs',(){
    expect(FableValidation.email('hello@example.com'),isNull);
    expect(FableValidation.email('invalid'),isNotNull);
    expect(FableValidation.requiredText(' '),'required');
    expect(FableValidation.number('4',min:3,max:5),isNull);
  });
  test('validation codes are localized safely',(){
    expect(FableValidation.message('required',languageCode:'ar'),'هذا الحقل مطلوب');
    expect(FableValidation.message('invalid_email',languageCode:'en'),'Enter a valid email address');
    expect(FableValidation.message('SENSITIVE_API_PAYLOAD',languageCode:'en'),'Invalid value');
  });
  test('supports cache load and stale read',()async{
    final cache=FableMemoryCache(maximumEntries:2);
    var count=0;
    final x=await cache.load<int>('x',fetch:()async=>++count);
    final y=await cache.load<int>('x',fetch:()async=>++count);
    expect(x,1);expect(y,1);expect(count,1);
  });
}

// Additional locale coverage: stable error codes are never presented raw.
// The server remains authoritative for authorization and business constraints.

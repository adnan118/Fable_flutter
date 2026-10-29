import 'package:fable_localization/fable_localization.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('RC66 language catalog accepts explicit public supported languages only', () {
    final ar=FableLanguage.parse({'code':'ar','name':'Arabic',
      'nativeName':'العربية','isDefault':true});
    expect(ar.code,'ar');
    expect(ar.name,'العربية');
    expect(ar.isDefault,isTrue);
    final en=FableLanguage.parse({'code':'en','name':'English','isDefault':false});
    expect(en.name,'English');
    for(final code in ['../ar','ar?token','ar/en','','a'*36]){
      expect(() => FableLanguage.parse({'code':code,'name':'Invalid'}),throwsFormatException);
    }
    expect(() => FableLanguage.parse({'code':'ar','name':''}),throwsFormatException);
  });
}

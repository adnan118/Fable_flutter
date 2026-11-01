import 'package:flutter_test/flutter_test.dart';
import 'package:fable_core/fable_core.dart';

void main(){
 test('explicit UI language survives app-store recreation; device resets it',()async{
  String? saved;
  Future<String?> read()async=>saved;
  Future<void> write(String? value)async{saved=value;}
  final first=FableLocalePreferenceStore(
    readForTest:read,writeForTest:write);
  final second=FableLocalePreferenceStore(
    readForTest:read,writeForTest:write);
  const allowed=['ar','en','fr-CA'];
  expect(await first.load(allowed),isNull);
  await first.save('ar',allowed);
  expect(await second.load(allowed),'ar');
  await second.save('fr-CA',allowed);
  expect(await first.load(allowed),'fr-CA');
  await first.save(null,allowed);
  expect(await second.load(allowed),isNull);
 });
 test('removed and unverified locale is never auto-activated on an app upgrade',()async{
  String? stored='ru';
  final prefs=FableLocalePreferenceStore(
    readForTest:()async=>stored,
    writeForTest:(v)async{stored=v;},
  );
  expect(await prefs.load(['ar','en']),isNull);
  expect(stored,'ru'); // Do not mutate unknown durable state by guessing.
  await expectLater(prefs.save('ru',['ar','en']),throwsArgumentError);
  await expectLater(prefs.save('../admin',['ar','en']),throwsArgumentError);
  expect(stored,'ru');
  await prefs.save('en',['ar','en']);
  expect(await prefs.load(['ar','en']),'en');
 });
 test('corrupt generated language policies fail before reading or writing',()async{
  var reads=0,writes=0;
  final prefs=FableLocalePreferenceStore(
    readForTest:()async{reads++;return null;},
    writeForTest:(_)async{writes++;},
  );
  await expectLater(prefs.load([]),throwsArgumentError);
  await expectLater(prefs.save('en',['en','/evil']),throwsArgumentError);
  expect(reads,0);
  expect(writes,0);
 });
 test('failed storage write does not give an apparent persisted language',()async{
  String? stored='ar';
  final prefs=FableLocalePreferenceStore(
    readForTest:()async=>stored,
    writeForTest:(_)=>Future<void>.error(StateError('Keychain unavailable')),
  );
  await expectLater(prefs.save('en',['ar','en']),throwsStateError);
  expect(await prefs.load(['ar','en']),'ar');
 });
}

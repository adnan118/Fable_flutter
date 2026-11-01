import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Application-owned language preference, not a Backend capability or an
/// indication that the server supports any translation operation.
/// The saved tag is validated against this app's generated language policy
/// every time it is read (including after an app upgrade).
class FableLocalePreferenceStore {
 FableLocalePreferenceStore({
  FlutterSecureStorage? storage,
  Future<String?> Function()? readForTest,
  Future<void> Function(String?)? writeForTest,
 }) : _storage=storage??const FlutterSecureStorage(),
      _readForTest=readForTest,_writeForTest=writeForTest;
 final FlutterSecureStorage _storage;
 final Future<String?> Function()? _readForTest;
 final Future<void> Function(String?)? _writeForTest;
 static const _key='fable.ui.locale.preference.v1';
 static final _tag=RegExp(r'^[a-z]{2,3}(?:-[A-Za-z0-9]{2,8}){0,3}$');
 static Set<String> _approved(Iterable<String> allowed){
  final values=allowed.toSet();
  if(values.isEmpty || values.length>100 ||
     values.any((v)=>v.length>35||!_tag.hasMatch(v)))
   throw ArgumentError('Invalid generated UI locale policy');
  return values;
 }
 Future<String?> load(Iterable<String> allowed) async {
  final supported=_approved(allowed);
  final stored=_readForTest!=null
    ?await _readForTest!():await _storage.read(key:_key);
  // Invalid/removed locales fall back to the platform preference. Do not
  // erase unknown data silently when project language settings change.
  return stored!=null&&supported.contains(stored)?stored:null;
 }
 Future<void> save(String? locale,Iterable<String> allowed) async {
  final supported=_approved(allowed);
  if(locale!=null&&!supported.contains(locale))
   throw ArgumentError.value(locale,'locale','Not in generated UI languages');
  if(_writeForTest!=null){await _writeForTest!(locale);return;}
  if(locale==null)await _storage.delete(key:_key);
  else await _storage.write(key:_key,value:locale);
 }
}

/// RC28: optional published UI-copy updates, never a replacement for bundled
/// ARB/AppLocalizations. A server revision avoids repeat downloads/translations.
/// No Google key or Redis access is ever present in Flutter.
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fable_core/fable_core.dart';

class FableClientCopySnapshot {
 const FableClientCopySnapshot({required this.locale,required this.revision,
  required this.entries,required this.checkedAt,required this.fromCache,
  required this.offlineFallback});
 final String locale,revision;
 final Map<String,String> entries;
 final DateTime checkedAt;
 final bool fromCache,offlineFallback;
 String text(String key,String bundledFallback)=>entries[key]??bundledFallback;
}

/// Only call when the declared contract supports `languages.clientCopy`.
/// `namespace` MUST identify the selected backend origin. Public curated copy
/// can be cached across account sign-outs, but never across backend origins.
class FableClientCopySync {
 FableClientCopySync(this.gateway,{required this.namespace,
  SharedPreferencesAsync? storage,this.minCheckInterval=Duration.zero,
  DateTime Function()? clock}):_storage=storage??SharedPreferencesAsync(),_clock=clock??DateTime.now {
  final origin=Uri.tryParse(namespace);
  final allowedHttp=origin?.scheme=='http' && const <String>{'localhost','127.0.0.1','10.0.2.2','::1'}.contains(origin?.host);
  if(origin==null||!origin.hasAuthority||origin.host.isEmpty||
     !(origin.scheme=='https'||allowedHttp)||origin.userInfo.isNotEmpty||
     origin.hasQuery||origin.hasFragment||(origin.path.isNotEmpty&&origin.path!='/')){
   throw ArgumentError('Public copy cache must be scoped to a bare trusted HTTPS origin');
  }
 }
 final BackendApiGateway gateway;
 final String namespace;
 final SharedPreferencesAsync _storage;
 final Duration minCheckInterval;
 final DateTime Function() _clock;
 static const _maxEntries=600;
 static final _keyPattern=RegExp(r'^[A-Za-z][A-Za-z0-9_.-]{0,95}$');
 static final _localePattern=RegExp(r'^[a-z]{2,3}(?:-[a-zA-Z0-9]{2,8}){0,3}$');
 static final _revisionPattern=RegExp(r'^[a-f0-9]{64}$');
 String _key(String locale)=>'fable.copy.v1.${Uri.encodeComponent(namespace)}.$locale';

 Future<FableClientCopySnapshot?> _cached(String locale)async{
  try{
   final raw=await _storage.getString(_key(locale));if(raw==null||raw.length>600000)return null;
   final parsed=jsonDecode(raw);if(parsed is! Map||parsed['requestedLocale']!=locale)return null;
   final revision=parsed['revision'],entries=parsed['entries'],checked=parsed['checkedAt'];
   if(revision is! String||!_revisionPattern.hasMatch(revision)||entries is! Map||entries.length>_maxEntries||checked is! String||parsed['locale'] is! String||!_localePattern.hasMatch(parsed['locale'] as String))return null;
   final copy=_validatedEntries(entries);
   return FableClientCopySnapshot(locale:parsed['locale'] as String,revision:revision,entries:copy,
    checkedAt:DateTime.parse(checked).toUtc(),fromCache:true,offlineFallback:false);
  }catch(_){return null;}
 }
 static Map<String,String> _validatedEntries(Map input){
  if(input.length>_maxEntries)throw const FormatException('Remote catalog too large');
  final result=<String,String>{};
  for(final entry in input.entries){
   if(entry.key is! String||!_keyPattern.hasMatch(entry.key as String)||entry.value is! String||
    (entry.value as String).isEmpty||(entry.value as String).length>5000){
    throw const FormatException('Invalid public text update');
   }
   result[entry.key as String]=entry.value as String;
  }
  return Map.unmodifiable(result);
 }
 Future<FableClientCopySnapshot> sync(String locale,{bool force=false})async{
  final normalized=locale.replaceAll('_','-').toLowerCase();
  if(!_localePattern.hasMatch(normalized)||normalized.length>35)throw ArgumentError('Invalid locale');
  final old=await _cached(normalized);final now=_clock().toUtc();
  if(!force&&old!=null&&now.difference(old.checkedAt)>=Duration.zero&&now.difference(old.checkedAt)<minCheckInterval)return old;
  try{
   // A conditional *operation query*, not a guessed endpoint or a secret.
   // 200 unchanged:true is compatible with all contract-based gateways.
   final response=await gateway.execute('languages.clientCopy',query:{'locale':normalized,
    if(old!=null)'revision':old.revision});
   final data=response.data;
   if(data is! Map||data['locale'] is! String||!_localePattern.hasMatch(data['locale'] as String))throw const FormatException('Invalid catalog response');
   final effectiveLocale=data['locale'] as String;
   final revision=data['revision'];if(revision is! String||!_revisionPattern.hasMatch(revision))throw const FormatException('Invalid revision');
   final unchanged=data['unchanged']==true;
   if(old!=null && unchanged && effectiveLocale!=old.locale)throw const FormatException('Locale fallback changed without catalog refresh');
   if(unchanged&&(old==null||revision!=old.revision||data['entries']!=null))throw const FormatException('Inconsistent unchanged revision');
   final entries=unchanged?old!.entries:_validatedEntries(data['entries'] is Map?data['entries'] as Map:<String,String>{});
   if(!unchanged&&data['entries'] is! Map)throw const FormatException('Missing updated catalog');
   final next=FableClientCopySnapshot(locale:effectiveLocale,revision:revision,
    entries:entries,checkedAt:now,fromCache:unchanged,offlineFallback:false);
   final serialized=jsonEncode({'requestedLocale':normalized,'locale':effectiveLocale,'revision':revision,'entries':entries,'checkedAt':now.toIso8601String()});
   if(serialized.length>600000)throw const FormatException('Remote catalog exceeds cache limit');
   await _storage.setString(_key(normalized),serialized);
   return next;
  }catch(_){
   // Old *validated public copy* is still useful offline; do not erase it.
   if(old!=null)return FableClientCopySnapshot(locale:old.locale,revision:old.revision,
    entries:old.entries,checkedAt:old.checkedAt,fromCache:true,offlineFallback:true);
   rethrow;
  }
 }
}

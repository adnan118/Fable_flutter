import 'dart:async';
import 'dart:convert';
import 'package:fable_core/fable_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A public revision is an invalidation hint, NOT a quote or a payment amount.
/// This component intentionally has no finance cache and performs no writes.
class PublicChangeDelta {
  const PublicChangeDelta({required this.revision,required this.changed,
    required this.removed,required this.initialLoad,required this.offline});
  final String revision;
  final Set<String> changed, removed;
  final bool initialLoad, offline;
  bool get needsRefetch => changed.isNotEmpty || removed.isNotEmpty || initialLoad;
}

/// Selected backend must explicitly declare a public, GET-only change manifest.
/// For Other Backend the app developer maps an equivalent operation; no Fable
/// route is inferred. A complete snapshot repairs any missed SSE hints.
class PublicChangeSync {
  PublicChangeSync({required this.gateway,required this.catalog,
    required this.operationId,required this.namespace,
    SharedPreferencesAsync? storage,
    this.checkInterval=const Duration(seconds:15),
  }) {
    final uri=Uri.tryParse(namespace);
    final local=uri?.scheme=='http'&&const {'localhost','127.0.0.1','10.0.2.2','::1'}.contains(uri?.host);
    if(uri==null||!uri.hasAuthority||uri.host.isEmpty||
      !(uri.scheme=='https'||local)||uri.userInfo.isNotEmpty||
      uri.hasQuery||uri.hasFragment||(uri.path.isNotEmpty&&uri.path!='/')){
      throw ArgumentError('A trusted backend origin is required for change snapshots');
    }
    final op=catalog.require(operationId);
    if(op.method.toUpperCase()!='GET'||op.requiresAuth||op.path.contains('{')){
      throw ArgumentError('Change feed must be a declared public GET snapshot');
    }
    if(checkInterval<const Duration(seconds:5)){
      throw ArgumentError('Bound change polling to at least 5 seconds');
    }
    // Trust and operation checks must succeed before touching platform storage.
    _storage = storage ?? SharedPreferencesAsync();
  }
  final BackendApiGateway gateway;
  final OperationCatalog catalog;
  final String operationId,namespace;
  final Duration checkInterval;
  late final SharedPreferencesAsync _storage;
  static final _hex=RegExp(r'^[a-f0-9]{64}$');
  // Other Backend may use opaque, URL-safe stable revision IDs instead of UUIDs.
  static final _entryRevision=RegExp(r'^[A-Za-z0-9][A-Za-z0-9_.:-]{0,127}$');
  final _changes=StreamController<PublicChangeDelta>.broadcast();
  Timer? _timer;
  bool _working=false;
  bool _disposed=false;
  Stream<PublicChangeDelta> get updates=>_changes.stream;
  String get _storageKey=>'fable.public-changes.v1.${Uri.encodeComponent(namespace)}';
  String? _revision;
  Map<String,String> _entries={};

  Map<String,String> _parseEntries(dynamic raw){
    if(raw is! List||raw.length>500)throw const FormatException('Invalid public revision manifest');
    final out=<String,String>{};
    for(final item in raw){
      if(item is! Map||item['slug'] is! String||item['revision'] is! String){
        throw const FormatException('Invalid public entry');
      }
      final slug=item['slug'] as String, revision=item['revision'] as String;
      if(slug.isEmpty||slug.length>190||slug.contains(RegExp(r'[\x00-\x1f\x7f]'))||
        !_entryRevision.hasMatch(revision)||out.containsKey(slug)){
        throw const FormatException('Invalid or duplicate published slug');
      }
      out[slug]=revision;
    }
    return out;
  }
  Future<void> loadLocal() async {
    if(_disposed)throw StateError('Change watcher already disposed');
    try{
      final raw=await _storage.getString(_storageKey);
      if(raw==null||raw.length>120000)return;
      final record=jsonDecode(raw);
      if(record is! Map||record['revision'] is! String||
         !_hex.hasMatch(record['revision'] as String)||record['entries'] is! List)return;
      final parsed=_parseEntries(record['entries']);
      _entries=parsed;_revision=record['revision'] as String;
      _changes.add(PublicChangeDelta(revision:_revision!,changed:parsed.keys.toSet(),
        removed:const {},initialLoad:true,offline:true));
    }catch(_){/* Damaged public-only cache is discarded; next sync repairs it. */}
  }
  Future<PublicChangeDelta?> check({bool force=false})async{
    if(_disposed||_working)return null;
    _working=true;
    try{
      final response=await gateway.execute(operationId,query:{
        if(_revision!=null)'revision':_revision,
      });
      final body=response.data;
      if(body is! Map||body['revision'] is! String||
        !_hex.hasMatch(body['revision'] as String))throw const FormatException('Invalid revision response');
      final revision=body['revision'] as String;
      if(body['unchanged']==true){
        if(_revision==null||revision!=_revision||body['entries']!=null){
          throw const FormatException('Inconsistent unchanged revision');
        }
        return null;
      }
      if(body['unchanged']!=false||body['resetRequired']==true){
        throw const FormatException('Backend requires explicit catalog reset');
      }
      final latest=_parseEntries(body['entries']);
      // A changed published entry is only a request to reload its domain GET.
      final changed=latest.keys.where((k)=>_entries[k]!=latest[k]).toSet();
      final removed=_entries.keys.where((k)=>!latest.containsKey(k)).toSet();
      final initial=_revision==null;
      final safe=jsonEncode({'revision':revision,'entries':latest.entries.map(
        (e)=>{'slug':e.key,'revision':e.value}).toList()});
      if(safe.length>120000)throw const FormatException('Change snapshot too large');
      // Lack of local storage must not suppress a valid online UI refresh.
      try{await _storage.setString(_storageKey,safe);}catch(_){/* in-memory only */}
      _revision=revision;_entries=latest;
      final delta=PublicChangeDelta(revision:revision,changed:changed,
        removed:removed,initialLoad:initial,offline:false);
      if(!_disposed)_changes.add(delta);
      return delta;
    } finally {_working=false;}
  }
  /// Call when the app returns to foreground, regains network or receives SSE
  /// hint. A failed request NEVER validates a cached price or removes data.
  Future<PublicChangeDelta?> onResume() => check(force:true);
  void start(){
    if(_disposed||_timer!=null)return;
    _timer=Timer.periodic(checkInterval,(_){unawaited(check().catchError((Object _)=>null));});
    unawaited(check().catchError((Object _)=>null));
  }
  void pause(){_timer?.cancel();_timer=null;}
  Future<void> dispose()async{pause();_disposed=true;await _changes.close();}
}

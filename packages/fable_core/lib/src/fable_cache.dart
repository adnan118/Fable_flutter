import 'dart:async';
import 'dart:collection';

class _Item<T> { _Item(this.value,this.expiresAt); final T value; final DateTime expiresAt; }
/// Bounded in-memory cache with SWR. Do not cache sensitive responses by default.
class FableMemoryCache {
  FableMemoryCache({this.maximumEntries=120});
  final int maximumEntries;
  final LinkedHashMap<String,_Item<dynamic>> _items=LinkedHashMap();
  final Map<String, Future<dynamic>> _pending={};
  T? peek<T>(String key, {bool allowStale=true}) {
    final item=_items.remove(key);
    if(item==null)return null;
    _items[key]=item;
    if(!allowStale && DateTime.now().isAfter(item.expiresAt))return null;
    return item.value as T?;
  }
  Future<T> load<T>(String key,{required Future<T> Function() fetch,
    Duration ttl=const Duration(minutes:2),bool allowStale=true}) async {
    final fresh=peek<T>(key,allowStale:false);
    if(fresh!=null)return fresh;
    final stale=peek<T>(key,allowStale:allowStale);
    if(stale!=null){unawaited(_refresh<T>(key,fetch,ttl).catchError((Object _) => stale));return stale;}
    return _refresh<T>(key,fetch,ttl);
  }
  Future<T> _refresh<T>(String key,Future<T> Function() fetch,Duration ttl) {
    final inProgress=_pending[key];if(inProgress!=null)return inProgress as Future<T>;
    // The in-flight future itself is our cache-generation token. Logout/clear
    // and explicit invalidations revoke it; an older request may finish for
    // its own caller but MUST NOT repopulate the cache afterward.
    late final Future<T> future;
    future=Future<T>.sync(fetch).then((value){
      if(identical(_pending[key],future)){
        _items.remove(key);_items[key]=_Item(value,DateTime.now().add(ttl));
        while(_items.length>maximumEntries)_items.remove(_items.keys.first);
      }
      return value;
    });
    _pending[key]=future;
    future.whenComplete((){
      if(identical(_pending[key],future))_pending.remove(key);
    }).ignore();
    return future;
  }
  void clear(){_items.clear();_pending.clear();}
  void remove(String key){_items.remove(key);_pending.remove(key);}
}

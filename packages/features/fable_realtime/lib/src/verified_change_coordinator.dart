import 'dart:async';
import 'package:material_ui/material_ui.dart';

/// Feature-neutral invalidation topics. These are signals to REFETCH (never
/// authoritative content, stock quantities, quotes, balances or reservations).
/// Domain adapters decide how to interpret version changes from their own
/// verified Backend contracts. No product/order/booking API is invented.
enum FableChangeArea { content, prices, inventory, availability }

class FableChangeHint {
  const FableChangeHint(this.area,{this.revision});
  final FableChangeArea area;
  final String? revision;
}

/// Receives trusted SSE/FCM/foreground-resume HINTS. Coalesces duplicate work,
/// serializes domain-specific re-fetch and marks money/availability stale until
/// an authoritative server GET and server-side conditional mutation validates it.
class FableVerifiedRefreshCoordinator {
  FableVerifiedRefreshCoordinator({required this.refetch,
    this.onSensitiveDataInvalidated});
  final Future<void> Function(FableChangeArea area) refetch;
  final void Function(FableChangeArea area)? onSensitiveDataInvalidated;
  final _changes=StreamController<FableChangeArea>.broadcast();
  final _running=<FableChangeArea>{};
  final _pending=<FableChangeArea>{};
  bool _disposed=false;
  Stream<FableChangeArea> get changes=>_changes.stream;
  static bool _sensitive(FableChangeArea area)=>
      area==FableChangeArea.prices||area==FableChangeArea.inventory||
      area==FableChangeArea.availability;

  Future<void> invalidate(FableChangeHint hint) async {
    if(_disposed)return;
    final area=hint.area;
    // Fail closed on any financial/availability invalidation BEFORE refetch.
    if(_sensitive(area))onSensitiveDataInvalidated?.call(area);
    if(_running.contains(area)){_pending.add(area);return;}
    _running.add(area);
    try{
      do{
        _pending.remove(area);
        // The refetch callback MUST use the selected Backend's VERIFIED GET
        // operation. A quote or permission never comes from this hint.
        await refetch(area);
        if(!_disposed)_changes.add(area);
      }while(!_disposed&&_pending.contains(area));
    }finally{_running.remove(area);}
  }
  Future<void> onConnectivityRestored()async{
    // SSE/FCM is lossy: force independent authoritative refresh for all
    // enabled domain adapters on foreground and reconnection.
    Object? firstError;
    for(final area in FableChangeArea.values){
      try{await invalidate(FableChangeHint(area));}catch(e){firstError??=e;}
    }
    if(firstError!=null)throw StateError('One or more domain refreshes failed; keep prior data stale');
  }
  Future<void> dispose()async{_disposed=true;await _changes.close();}
}

/// Optional common UX: show that a displayed quote is NOT a valid payment
/// authorization. The host must disable checkout until a fresh quote was
/// checked by the domain's Backend transaction (e.g. via If-Match).
class FableSensitiveDataBanner extends StatelessWidget {
  const FableSensitiveDataBanner({super.key,required this.isStale,
    required this.onRequestRefresh,this.loading=false});
  final bool isStale,loading;
  final VoidCallback? onRequestRefresh;
  @override Widget build(BuildContext context){
    if(!isStale)return const SizedBox.shrink();
    final ar=Localizations.localeOf(context).languageCode=='ar';
    return Card(child:Padding(padding:const EdgeInsets.all(12),child:Row(children:[
      const Icon(Icons.warning_amber_rounded),const SizedBox(width:8),
      Expanded(child:Text(ar?'ربما تغير السعر أو التوافر. يلزم جلب البيانات الحالية قبل التأكيد.':
        'Price or availability may have changed. Fetch the latest data before confirming.')),
      TextButton(onPressed:loading?null:onRequestRefresh,
        child:Text(ar?'تحديث':'Refresh')),
    ])));
  }
}

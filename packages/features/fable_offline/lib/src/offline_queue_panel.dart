import 'package:material_ui/material_ui.dart';
import 'offline_reaction_queue.dart';

/// Optional reusable domain-neutral UI: never invents deferred actions.
/// The host supplies an authenticated, contract-verified executor; financial
/// operations remain forbidden by OfflineReactionQueue even when passed here.
class FableOfflineQueuePanel extends StatefulWidget {
  const FableOfflineQueuePanel({super.key,required this.queue,
    required this.executor,this.connectionVerified=false});
  final OfflineReactionQueue queue;
  final OfflineReactionExecutor? executor;
  final bool connectionVerified;
  @override State<FableOfflineQueuePanel> createState()=>_FableOfflineQueuePanelState();
}
class _FableOfflineQueuePanelState extends State<FableOfflineQueuePanel> {
  bool _busy=false;
  String? _error;
  int _refresh=0;
  bool get _ar=>Localizations.localeOf(context).languageCode=='ar';
  Future<void> _sync()async{
    if(_busy||!widget.connectionVerified||widget.executor==null)return;
    setState((){_busy=true;_error=null;});
    try{await widget.queue.flush(widget.executor!);}
    catch(_){if(mounted)setState(()=>_error=_ar?'تعذرت المزامنة. البيانات المحلية محفوظة.':'Sync failed. Pending actions were retained.');}
    finally{if(mounted)setState((){_busy=false;_refresh++;});}
  }
  Future<void> _discard(String id)async{
    if(_busy)return;
    setState(()=>_busy=true);
    try{await widget.queue.discard(id);}
    catch(_){if(mounted)setState(()=>_error=_ar?'تعذر حذف العملية المؤجلة.':'Could not discard the pending action.');}
    finally{if(mounted)setState((){_busy=false;_refresh++;});}
  }
  @override Widget build(BuildContext context){
    final locale=_ar;
    return Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(
      crossAxisAlignment:CrossAxisAlignment.start,mainAxisSize:MainAxisSize.min,children:[
      Text(locale?'العمليات المحفوظة دون إنترنت':'Offline actions',style:Theme.of(context).textTheme.titleMedium),
      Text(locale?'التفاعلات الآمنة فقط؛ لا دفعات أو حجوزات أو أرصدة.':'Safe interactions only. No payments, orders, bookings or balances.'),
      if(_error!=null)Text(_error!),
      FutureBuilder<List<DeferredReaction>>(
        key:ValueKey(_refresh),future:widget.queue.pending(),builder:(context,snapshot){
          if(snapshot.hasError)return Text(locale?'تعذر قراءة الطابور؛ لا تُمسح البيانات تلقائيًا.':'Queue unavailable; no automatic deletion.');
          if(!snapshot.hasData)return const LinearProgressIndicator();
          final pending=snapshot.data!;
          return Column(mainAxisSize:MainAxisSize.min,children:[
            Text(locale?'عمليات بانتظار الاتصال: ${pending.length}':'Pending actions: ${pending.length}'),
            for(final item in pending.take(30))ListTile(
              title:Text(item.resourceId,maxLines:1,overflow:TextOverflow.ellipsis),
              subtitle:Text(item.needsReview?(locale?'تعارض: يحتاج مراجعة':'Conflict: review required'):
                (locale?'بانتظار المزامنة':'Waiting for sync')),
              trailing:IconButton(onPressed:_busy?null:()=>_discard(item.id),
                tooltip:locale?'تجاهل العملية':'Discard action',icon:const Icon(Icons.delete_outline))),
          ]);
        }),
      FilledButton(onPressed:_busy||!widget.connectionVerified||widget.executor==null?null:_sync,
        child:Text(locale?'مزامنة الآن':'Sync now')),
      if(!widget.connectionVerified)Text(locale?'اتصل بالإنترنت وتحقق من الحساب أولًا.':'Reconnect and verify the account first.'),
    ])));
  }
}

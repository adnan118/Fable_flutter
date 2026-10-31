import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fable_core/fable_core.dart';
import 'inbox_repository.dart';
import 'notification_navigation.dart';
import 'inbox_refresh_signal.dart';

/// Optional inbox screen. Fable and Other backends share UI, but never routes,
/// session namespaces, or operation IDs. Other must bind both roles explicitly.
class FableInboxPage extends StatefulWidget {
 const FableInboxPage({super.key,required FableContract contract}) :
   fableContract=contract,externalCatalog=null,
   listOperationId='notifications.inbox',markReadOperationId='notifications.read';
 const FableInboxPage.external({super.key,required ExternalOperationCatalog catalog,
   required this.listOperationId,required this.markReadOperationId}) :
   fableContract=null,externalCatalog=catalog;
 final FableContract? fableContract;
 final ExternalOperationCatalog? externalCatalog;
 final String listOperationId,markReadOperationId;
 @override State<FableInboxPage> createState()=>_FableInboxPageState();
}
class _FableInboxPageState extends State<FableInboxPage> {
 static const _origin=String.fromEnvironment('FABLE_API_BASE_URL');
 StreamSubscription<FableIdentityEvent>? _identityChanges;
 StreamSubscription<int>? _inboxChanges;
 bool _refreshQueued=false;
 BackendApiGateway? _connection;
 FableSecureSession? _session;
 List<FableInboxItem>? _items;
 bool _loading=false;
 int _generation=0;
 String? _error;
 bool get _supported {
   final fable=widget.fableContract;
   if(fable!=null)return _origin.isNotEmpty&&
     fable.supports(widget.listOperationId)&&fable.supports(widget.markReadOperationId);
   final external=widget.externalCatalog;
   if(external==null)return false;
   final list=external.operations[widget.listOperationId];
   final update=external.operations[widget.markReadOperationId];
   return list?.method=='GET' && list!.requiresAuth && list.credentialHeader==null &&
     update!=null && update.requiresAuth && update.credentialHeader==null &&
     RegExp(r'\{([^{}]*)\}').allMatches(update.path).map((m)=>m.group(1)).join(',')=='id' &&
     !RegExp(r'\{([^{}]*)\}').hasMatch(list.path) &&
     const {'POST','PATCH','PUT'}.contains(update.method);
 }
 bool get _ar=>Localizations.localeOf(context).languageCode=='ar';
 bool get _privacyContentAvailable {
   final contract=widget.fableContract;
   if(contract==null||!contract.isFeatureAvailable('content'))return false;
   final read=contract.operations['content.page.read'],
     index=contract.operations['content.publicChanges'],
     accept=contract.operations['content.page.accept'];
   return read?.method=='GET'&&read?.path=='/content/pages/{slug}'&&
     read?.requiresAuth==false&&index?.method=='GET'&&
     index?.path=='/content/pages/changes'&&index?.requiresAuth==false&&
     accept?.method=='POST'&&accept?.path=='/content/pages/{pageId}/accept'&&
     accept?.requiresAuth==true;
 }
 void _openItem(FableInboxItem item){
   // A verified privacy notice opens the installed published-content feature,
   // never a URL, raw pageId route, or external Backend's guessed endpoint.
   final target=item.isPublishedPrivacyUpdate&&_privacyContentAvailable
     ?const <String,String>{'target':'content'}:item.data;
   unawaited(FableNotificationNavigation.instance.open(target));
   if(item.readAt==null)unawaited(_read(item));
 }
 void _requestRefresh(){
   if(!mounted)return;
   if(_loading){_refreshQueued=true;return;}
   unawaited(_load());
 }
 @override void didUpdateWidget(covariant FableInboxPage oldWidget){
   super.didUpdateWidget(oldWidget);
   if(!identical(oldWidget.fableContract,widget.fableContract) ||
      !identical(oldWidget.externalCatalog,widget.externalCatalog) ||
      oldWidget.listOperationId!=widget.listOperationId ||
      oldWidget.markReadOperationId!=widget.markReadOperationId){
     _generation++;
     // The contract and account namespace are a trust boundary. Never retain
     // the previous provider's client or visible inbox after a contract switch.
     unawaited(_identityChanges?.cancel());
     _identityChanges=null;
     _connection?.dispose();
     _connection=null;
     _session=null;
     _items=null;
     _error=null;
     _refreshQueued=true;
     WidgetsBinding.instance.addPostFrameCallback((_){if(mounted)_requestRefresh();});
   }
 }
 @override void initState(){
   super.initState();
   _inboxChanges=FableInboxRefreshSignal.instance.changes.listen((_)=>_requestRefresh());
   WidgetsBinding.instance.addPostFrameCallback((_){if(mounted)unawaited(_load());});
 }
 BackendApiGateway _client() {
   final existing=_connection;
   if(existing!=null)return existing;
   final fable=widget.fableContract;
   if(fable!=null){
     final connection=FableAuthGateway(baseUri:Uri.parse(_origin),contract:fable,
       allowHttpForLocalDevelopment:kDebugMode);
     _session=connection.session;
     return _connection=connection;
   }
   final catalog=widget.externalCatalog!;
   // The imported external catalog is authoritative for the base URI and
   // OAuth/Bearer namespace. FABLE_API_BASE_URL must not leak into Other.
   final session=ExternalAuthGateway.secureSessionFor(catalog);
   final connection=ExternalApiGateway(catalog:catalog,session:session,
     allowHttpForLocalDevelopment:kDebugMode);
   _session=session;
   return _connection=connection;
 }
 FableInboxRepository _repository(BackendApiGateway api)=>FableInboxRepository(api,
   listOperationId:widget.listOperationId,markReadOperationId:widget.markReadOperationId,
   requireUuidIds:widget.externalCatalog==null);
 Future<void> _load() async {
   if(_loading||!_supported)return;
   setState((){_loading=true;_error=null;});
   int? epoch;
   final generation=_generation;
   final provider=widget.externalCatalog ?? widget.fableContract;
   try{
     final api=_client();
     _identityChanges ??= _session!.identityEvents.listen((event){
       if(!mounted)return;
       setState(()=>_items=null);
       if(event.authenticated)_requestRefresh();
     });
     epoch=_session!.identityRevision;
     final items=await _repository(api).list();
     if(mounted && generation==_generation && _session!.identityRevision==epoch &&
       identical(provider,widget.externalCatalog ?? widget.fableContract))setState(()=>_items=items);
   }catch(_){if(mounted && generation==_generation && epoch==_session?.identityRevision &&
     identical(provider,widget.externalCatalog ?? widget.fableContract))setState(()=>_error=_ar?'تعذر تحميل الإشعارات. تحقق من الجلسة والاتصال.':'Could not load notifications. Check session and connection.');}
   finally{
     if(mounted){
       setState(()=>_loading=false);
       if(_refreshQueued){
         _refreshQueued=false;
         WidgetsBinding.instance.addPostFrameCallback((_){if(mounted)_requestRefresh();});
       }
     }
   }
 }
 Future<void> _read(FableInboxItem item) async {
   final api=_connection,session=_session;
   if(api==null||session==null||_loading)return;
   setState(()=>_loading=true);
   final epoch=session.identityRevision;
   final generation=_generation;
   try{
     await _repository(api).markRead(item.id);
     if(mounted && generation==_generation && identical(session,_session) && epoch==session.identityRevision)setState(()=>_items=null);
   }catch(_){if(mounted && generation==_generation && identical(session,_session) && epoch==session.identityRevision)setState(()=>_error=_ar?'تعذر تعيين الإشعار كمقروء.':'Could not mark as read.');}
   finally{if(mounted)setState(()=>_loading=false);}
   if(mounted&&generation==_generation&&identical(session,_session)&&epoch==session.identityRevision&&_error==null)await _load();
 }
 @override void dispose(){
   unawaited(_identityChanges?.cancel());
   unawaited(_inboxChanges?.cancel());
   _connection?.dispose();
   super.dispose();
 }
 @override Widget build(BuildContext context)=>Scaffold(
   appBar:AppBar(title:Text(_ar?'الإشعارات':'Notifications')),
   body:SafeArea(child:ListView(padding:const EdgeInsets.all(16),children:[
    if(!_supported)Text(_ar?'عمليات الإشعارات غير متاحة في عقد الباك المستورد.':'Notification operations are missing from the imported Backend contract.'),
    if(_loading)const LinearProgressIndicator(),
    if(_error!=null)Text(_error!),
    if(_items!=null&&_items!.isEmpty)Text(_ar?'لا توجد إشعارات حاليًا':'No notifications yet'),
    for(final item in _items??<FableInboxItem>[])ListTile(
     onTap:()=>_openItem(item),
     title:Text(item.title,maxLines:2,overflow:TextOverflow.ellipsis),
     subtitle:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
       Text(item.body,maxLines:5,overflow:TextOverflow.ellipsis),
       if(widget.fableContract!=null &&
          (item.securityActions.isNotEmpty ||
            item.isPublishedPrivacyUpdate&&_privacyContentAvailable))
         Wrap(spacing:8,runSpacing:4,children:[
           if(item.isPublishedPrivacyUpdate&&_privacyContentAvailable)
             TextButton(onPressed:_loading?null:()=>_openItem(item),
               child:Text(_ar?'عرض سياسة الخصوصية':'Review privacy policy')),
           for(final action in item.securityActions)
             if(action.id=='THIS_WAS_ME')
               TextButton(onPressed:_loading?null:(){
                 // Acknowledgement is a read action, NEVER an auth/security override.
                 unawaited(_read(item));
                 ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(
                   _ar?'تمت قراءة التنبيه فقط؛ لم يُلغَ أي قفل أمني.'
                       :'Notice acknowledged; no security protection was disabled.')));
               },child:Text(_ar?'هذه محاولتي':'This was me')),
           for(final action in item.securityActions)
             if(action.id=='RESET_PASSWORD')
               TextButton(
                 onPressed:action.route==null||
                     FableNotificationNavigation.instance.navigateVerifiedAppRoute==null
                   ?null:()=>unawaited(
                     FableNotificationNavigation.instance.openVerifiedInternalRoute(action.route!)),
                 child:Text(_ar?'استعادة كلمة المرور':'Reset password')),
         ]),
     ]),
     trailing:item.readAt!=null?const Icon(Icons.done_all):IconButton(
       tooltip:_ar?'تحديد كمقروء':'Mark as read',icon:const Icon(Icons.mark_email_read_outlined),
       onPressed:_loading?null:()=>_read(item))),
    const SizedBox(height:12),
    if(_supported)FilledButton(onPressed:_loading?null:_load,child:Text(_ar?'تحديث':'Refresh')),
   ])),
 );
}

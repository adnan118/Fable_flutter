import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'published_content_repository.dart';
import 'published_content_widgets.dart';

/// Public, effective-only index provided by a verified Backend manifest.
/// No admin drafts, guessed URL, or project-specific content slug is assumed.
class FablePublishedContentIndexPage extends StatefulWidget {
 const FablePublishedContentIndexPage({
  super.key,required this.repository,this.onDispose,
  this.refreshSignals,this.identitySignals,
 });
 final FablePublishedContentRepository repository;
 final VoidCallback? onDispose;
 final Stream<Object?>? refreshSignals,identitySignals;
 @override State<FablePublishedContentIndexPage> createState()=>_FablePublishedContentIndexPageState();
}
class _FablePublishedContentIndexPageState extends State<FablePublishedContentIndexPage>
    with WidgetsBindingObserver {
 List<FablePublishedIndexEntry>? _entries;
 bool _loading=false,_retryQueued=false;
 int _epoch=0;
 String? _error;
 @override void initState(){
  super.initState();
  WidgetsBinding.instance.addObserver(this);
  WidgetsBinding.instance.addPostFrameCallback((_){if(mounted)_refresh();});
 }
 @override void didChangeAppLifecycleState(AppLifecycleState state){
  if(state==AppLifecycleState.resumed)_refresh();
 }
 @override void didUpdateWidget(covariant FablePublishedContentIndexPage oldWidget){
  super.didUpdateWidget(oldWidget);
  if(!identical(oldWidget.repository,widget.repository)){
   _epoch++;_loading=false;_entries=null;_error=null;
   WidgetsBinding.instance.addPostFrameCallback((_){if(mounted)_refresh();});
  }
 }
 void _refresh(){
  if(!mounted)return;
  if(_loading){_retryQueued=true;return;}
  unawaited(_load());
 }
 Future<void> _load()async{
  if(_loading)return;
  final epoch=++_epoch,repository=widget.repository;
  setState((){_loading=true;_error=null;});
  try{
   final entries=await repository.publishedIndex();
   if(mounted&&epoch==_epoch&&identical(repository,widget.repository)){
    setState(()=>_entries=entries);
   }
  }catch(_){
   if(mounted&&epoch==_epoch&&identical(repository,widget.repository))
    setState(()=>_error='Unable to verify published pages.');
  }finally{
   if(mounted&&epoch==_epoch){
    setState(()=>_loading=false);
    if(_retryQueued){
     _retryQueued=false;
     WidgetsBinding.instance.addPostFrameCallback((_){if(mounted)_refresh();});
    }
   }
  }
 }
 void _open(FablePublishedIndexEntry item){
  Navigator.of(context).push(MaterialPageRoute<void>(builder:(_)=>
   FablePublishedContentPage(
    slug:item.slug,repository:widget.repository,
    refreshSignals:widget.refreshSignals,
    identitySignals:widget.identitySignals,
   )));
 }
 @override void dispose(){
  WidgetsBinding.instance.removeObserver(this);
  _epoch++;
  widget.onDispose?.call();
  super.dispose();
 }
 @override Widget build(BuildContext context){
  final ar=Localizations.maybeLocaleOf(context)?.languageCode=='ar';
  return Scaffold(
   appBar:AppBar(title:Text(ar?'الصفحات المنشورة':'Published pages')),
   body:SafeArea(child:ListView(padding:const EdgeInsets.all(16),children:[
    if(_loading)const LinearProgressIndicator(),
    if(_error!=null)Text(ar?'تعذر التحقق من الصفحات المنشورة.':_error!),
    if(_entries?.isEmpty==true)Text(ar?'لا توجد صفحات منشورة حالياً.':'No published pages yet.'),
    for(final item in _entries??<FablePublishedIndexEntry>[])
     ListTile(
      title:Text(item.slug.replaceAll('-', ' ')),
      subtitle:Text(ar?'الإصدار ${item.version}':'Version ${item.version}'),
      trailing:const Icon(Icons.chevron_right),
      onTap:_loading||_error!=null?null:()=>_open(item),
     ),
    const SizedBox(height:12),
    FilledButton(onPressed:_loading?null:_refresh,
     child:Text(ar?'تحديث القائمة':'Refresh pages')),
   ])),
  );
 }
}

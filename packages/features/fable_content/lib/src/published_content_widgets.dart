import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'package:fable_design_system/fable_design_system.dart';
import 'published_content_repository.dart';
import 'structured_content_text.dart';

/// Safe, backend-neutral content block renderer. It NEVER interprets HTML or
/// opens untrusted URLs, and never invents image/media endpoints. Projects can
/// explicitly register vetted renderers for approved block types.
typedef FableCustomBlockRenderer=Widget? Function(BuildContext context,FableContentBlock block);
class FablePublishedContentView extends StatelessWidget {
 const FablePublishedContentView({super.key,required this.document,this.customRenderer});
 final FablePublishedDocument document;
 final FableCustomBlockRenderer? customRenderer;
 @override Widget build(BuildContext context)=>ListView(padding:const EdgeInsets.all(16),children:[
  Semantics(header:true,child:Text(document.title,style:Theme.of(context).textTheme.headlineSmall)),
  if(document.summary!=null)Padding(padding:const EdgeInsets.symmetric(vertical:8),child:Text(document.summary!)),
  for(final block in document.blocks)Padding(padding:const EdgeInsets.symmetric(vertical:6),
    child:FablePublishedBlockView(block:block,customRenderer:customRenderer)),
 ]);
}

class FablePublishedBlockView extends StatelessWidget {
 const FablePublishedBlockView({super.key,required this.block,this.customRenderer});
 final FableContentBlock block;
 final FableCustomBlockRenderer? customRenderer;
 String? text(String key,{int max=10000}){
  final v=block.data[key];
  return v is String&&v.length<=max?v:null;
 }
 Widget rich(String key)=>FableStructuredTextView(payload:block.data[key]);
 Widget fallback(BuildContext context,{String? reason}){
  final ar=Localizations.maybeLocaleOf(context)?.languageCode=='ar';
  return Semantics(
   label:ar?'عنصر محتوى يحتاج تكاملاً موثقاً: ${block.type}':
     'Published content needs verified integration: ${block.type}',
   child:Text(reason??(ar?'العنصر ${block.type} يحتاج ربطاً موثّقاً قبل العرض.':
       'Content block ${block.type} requires verified integration.'),
    style:Theme.of(context).textTheme.bodySmall));
 }
 @override Widget build(BuildContext context){
  final typography=Theme.of(context).textTheme;
  // Media, downloads, links and custom blocks must be bound to project
  // capabilities explicitly. A raw mediaId or URL is never an image or action.
  if(const {'image','gallery','video','file-download','button','custom'}
       .contains(block.type)){
   final vetted=customRenderer?.call(context,block);
   if(vetted!=null)return vetted;
   if(block.type=='button'){
    return OutlinedButton(onPressed:null,
      child:Text(text('label',max:200)??'Action unavailable'));
   }
   return fallback(context);
  }
  switch(block.type){
   case 'heading':
    final level=block.data['level'].toString();
    final style=level=='1'?typography.headlineMedium:
      level=='2'?typography.headlineSmall:typography.titleMedium;
    return Semantics(header:true,child:Text(text('text')??'',style:style));
   case 'paragraph':return rich('content');
   case 'rich-text':return rich('document');
   case 'quote':return Padding(padding:const EdgeInsets.symmetric(horizontal:12),
     child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Text(text('text')??'',style:typography.bodyLarge),
      if(text('author')!=null)Text(text('author')!,style:typography.labelMedium),
     ]));
   case 'notice':return Card(child:Padding(padding:const EdgeInsets.all(12),
     child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      if(text('title')!=null)Text(text('title')!,style:typography.titleMedium),
      rich('content'),
     ])));
   case 'divider':return const Divider();
   case 'spacer':return SizedBox(height:switch(block.data['size']){
     'sm'=>8.0,'lg'=>32.0,_=>16.0});
   case 'image-text':
    // Text remains available to users without inventing a media URL. A
    // project's verified media renderer may implement the entire combined block.
    final vetted=customRenderer?.call(context,block);
    if(vetted!=null)return vetted;
    return Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
     if(text('title')!=null)Text(text('title')!,style:typography.titleMedium),
     rich('content'),
     fallback(context),
    ]);
   case 'list':
    final items=block.data['items'];
    if(items is List&&items.length<=100&&
       items.every((x)=>x is String&&x.length<=3000)){
     return Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      for(var i=0;i<items.length;i++)
       Padding(padding:const EdgeInsets.symmetric(vertical:3),
        child:Text("${block.data['style']=='numbered'?'${i+1}.':'•'} ${items[i]}")),
     ]);
    }
    return fallback(context);
   case 'faq':
    final items=block.data['items'];
    if(items is List&&items.length<=60&&items.every((x)=>x is Map&&
       x['question'] is String&&x['answer'] is String&&
       (x['question'] as String).length<=500&&
       (x['answer'] as String).length<=5000)){
     return Column(children:[for(final entry in items)
      ExpansionTile(title:Text(entry['question'] as String),children:[
       Padding(padding:const EdgeInsets.all(12),
        child:Text(entry['answer'] as String)),
      ])]);
    }
    return fallback(context);
   case 'table':
    final cols=block.data['columns'],rows=block.data['rows'];
    if(cols is List&&cols.isNotEmpty&&cols.length<=12&&
       cols.every((x)=>x is String&&x.length<=120)&&rows is List&&
       rows.length<=80&&rows.every((r)=>r is List&&
         r.length==cols.length&&r.every((cell)=>cell is String&&cell.length<=1000))){
     return SingleChildScrollView(scrollDirection:Axis.horizontal,
      child:DataTable(
       columns:[for(final c in cols)DataColumn(label:Text(c as String))],
       rows:[for(final row in rows)
        DataRow(cells:[for(final cell in row as List)
         DataCell(Text(cell as String))])]));
    }
    return fallback(context);
   case 'columns':
    final columns=block.data['columns'];
    if(columns is List&&columns.isNotEmpty&&columns.length<=6&&
       columns.every((c)=>c is Map&&
         (c['title']==null||c['title'] is String)&&
         (c['content']==null||c['content'] is String||c['content'] is Map))){
     return Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      for(final c in columns)
       Padding(padding:const EdgeInsets.symmetric(vertical:8),child:
        Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
         if(c['title'] is String)Text(c['title'] as String,
           style:typography.titleMedium),
         if(c['content']!=null)FableStructuredTextView(payload:c['content']),
        ])),
     ]);
    }
    return fallback(context);
  }
  final optional=customRenderer?.call(context,block);
  if(optional!=null)return optional;
  return fallback(context);
 }
}

/// Optional complete screen *built from shared widgets*. It is not forced
/// into generated routes. The parent supplies a verified Backend repository.
///
/// Content and account events can be connected through [refreshSignals] and
/// [identitySignals]. No Firebase or Fable-only route is assumed.
class FablePublishedContentPage extends StatefulWidget {
 const FablePublishedContentPage({super.key,required this.slug,required this.repository,
  this.locale,this.customRenderer,this.onAccepted,this.refreshSignals,
  this.identitySignals});
 final String slug;
 final FablePublishedContentRepository repository;
 final String? locale;
 final FableCustomBlockRenderer? customRenderer;
 final VoidCallback? onAccepted;
 /// Optional published-content hint stream. Resume also revalidates the page.
 final Stream<Object?>? refreshSignals;
 /// Optional account/session change stream; prior acceptance is never reused
 /// across identities. Backend still validates every version acceptance.
 final Stream<Object?>? identitySignals;
 @override State<FablePublishedContentPage> createState()=>_FablePublishedContentPageState();
}
class _FablePublishedContentPageState extends State<FablePublishedContentPage>
    with WidgetsBindingObserver {
 FablePublishedDocument? _document;
 StreamSubscription<Object?>? _refreshSubscription,_identitySubscription;
 bool _loading=false,_accepted=false,_accepting=false,_refreshQueued=false,_updated=false;
 int _requestEpoch=0;
 String? _error;

 @override void initState(){
  super.initState();
  WidgetsBinding.instance.addObserver(this);
  _subscribe();
  _requestRefresh();
 }
 void _subscribe(){
  _refreshSubscription=widget.refreshSignals?.listen((_){
   if(mounted)_requestRefresh();
  });
  _identitySubscription=widget.identitySignals?.listen((_){
   if(!mounted)return;
   // Do not reuse approval obtained under another user/session.
   setState(()=>_accepted=false);
   _requestRefresh();
  });
 }
 @override void didChangeAppLifecycleState(AppLifecycleState state){
  if(state==AppLifecycleState.resumed)_requestRefresh();
 }
 @override void didUpdateWidget(covariant FablePublishedContentPage old){
  super.didUpdateWidget(old);
  if(!identical(old.refreshSignals,widget.refreshSignals)||
     !identical(old.identitySignals,widget.identitySignals)){
   unawaited(_refreshSubscription?.cancel());
   unawaited(_identitySubscription?.cancel());
   _subscribe();
  }
  if(old.slug!=widget.slug||old.locale!=widget.locale||
     !identical(old.repository,widget.repository)){
   _requestEpoch++;
   _loading=false;_refreshQueued=false;_document=null;
   _accepted=false;_updated=false;_error=null;
   _requestRefresh();
  }
 }
 void _requestRefresh(){
  if(!mounted)return;
  if(_loading){_refreshQueued=true;return;}
  unawaited(_load());
 }
 Future<void> _load()async{
  if(_loading)return;
  final epoch=++_requestEpoch;
  setState((){_loading=true;_error=null;});
  final slug=widget.slug,locale=widget.locale,repository=widget.repository;
  try{
   final document=await repository.read(slug,locale:locale);
   if(!mounted||epoch!=_requestEpoch||slug!=widget.slug||
      locale!=widget.locale||!identical(repository,widget.repository))return;
   setState((){
    final old=_document;
    final changed=old!=null &&
      (old.id!=document.id||old.versionId!=document.versionId);
    if(changed){_accepted=false;_updated=true;}
    _document=document;
   });
  }catch(_){
   if(mounted&&epoch==_requestEpoch&&slug==widget.slug&&
      identical(repository,widget.repository)){
    setState(()=>_error='Could not verify the latest published version.');
   }
  }finally{
   if(mounted&&epoch==_requestEpoch){
    setState(()=>_loading=false);
    if(_refreshQueued){
     _refreshQueued=false;
     WidgetsBinding.instance.addPostFrameCallback((_){
      if(mounted)_requestRefresh();
     });
    }
   }
  }
 }
 Future<void> _accept()async{
  final document=_document;
  if(_accepting||_loading||_error!=null||document==null||
     !document.requiresAcceptance)return;
  final epoch=_requestEpoch,repository=widget.repository;
  setState(()=>_accepting=true);
  try{
   await repository.accept(document);
   if(mounted&&epoch==_requestEpoch&&
      identical(repository,widget.repository)&&identical(_document,document)){
    setState((){_accepted=true;_updated=false;});
    widget.onAccepted?.call();
   }
  }catch(_){
   if(mounted&&epoch==_requestEpoch)
    setState(()=>_error='Could not record acceptance. Sign in and retry.');
  }finally{if(mounted)setState(()=>_accepting=false);}
 }
 @override void dispose(){
  WidgetsBinding.instance.removeObserver(this);
  unawaited(_refreshSubscription?.cancel());
  unawaited(_identitySubscription?.cancel());
  _requestEpoch++;
  super.dispose();
 }
 @override Widget build(BuildContext context){
  final ar=Localizations.maybeLocaleOf(context)?.languageCode=='ar';
  return Scaffold(
   appBar:AppBar(title:Text(_document?.title??(ar?'محتوى منشور':'Published content'))),
   body:SafeArea(child:Column(children:[
    if(_loading)const LinearProgressIndicator(),
    if(_updated)Padding(padding:const EdgeInsets.all(12),
      child:Text(ar?'نُشرت نسخة جديدة. يرجى مراجعتها قبل الموافقة.':
        'A new published version is available. Review it before accepting.')),
    if(_error!=null)Padding(padding:const EdgeInsets.all(8),
      child:Text(ar?'تعذر التحقق من النسخة المنشورة. حاول التحديث.':_error!)),
    Expanded(child:_document!=null
      ?FablePublishedContentView(document:_document!,customRenderer:widget.customRenderer)
      :FableStateView(state:_loading?FableContentState.loading:FableContentState.empty,
        onRetry:_loading?null:_requestRefresh)),
    if(_document?.requiresAcceptance==true&&!_accepted)
      Padding(padding:const EdgeInsets.all(12),
       child:FilledButton(
        onPressed:_accepting||_loading||_error!=null?null:_accept,
        child:Text(ar?'أوافق على النسخة المنشورة':'Accept published version'))),
    if(_error!=null)TextButton(
      onPressed:_loading?null:_requestRefresh,
      child:Text(ar?'إعادة التحقق':'Retry verification')),
   ])),
  );
 }
}

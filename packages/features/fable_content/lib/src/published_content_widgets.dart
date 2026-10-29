import 'package:material_ui/material_ui.dart';
import 'package:fable_design_system/fable_design_system.dart';
import 'published_content_repository.dart';

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
  final v=block.data[key];return v is String&&v.length<=max?v:null;
 }
 @override Widget build(BuildContext context){
  final typography=Theme.of(context).textTheme;
  switch(block.type){
   case 'heading':
     final level=block.data['level'].toString();
     final style=level=='1'?typography.headlineMedium:level=='2'?typography.headlineSmall:typography.titleMedium;
     return Semantics(header:true,child:Text(text('text')??'',style:style));
   case 'paragraph':return Text(text('content')??'');
   case 'quote':return Padding(padding:const EdgeInsets.symmetric(horizontal:12),child:Column(
     crossAxisAlignment:CrossAxisAlignment.start,children:[Text(text('text')??'',style:typography.bodyLarge),
       if(text('author')!=null)Text(text('author')!,style:typography.labelMedium)]));
   case 'notice':return Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(
     crossAxisAlignment:CrossAxisAlignment.start,children:[if(text('title')!=null)Text(text('title')!,style:typography.titleMedium),
     Text(text('content')??'')])));
   case 'divider':return const Divider();
   case 'spacer':return SizedBox(height:switch(block.data['size']){'sm'=>8.0,'lg'=>32.0,_=>16.0});
   case 'list':
     final items=block.data['items'];
     if(items is List && items.length<=100 && items.every((x)=>x is String&&x.length<=3000)){
       return Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
         for(var i=0;i<items.length;i++)Padding(padding:const EdgeInsets.symmetric(vertical:3),
          child:Text('${block.data['style']=='numbered'?'${i+1}.':'•'} ${items[i]}'))]);
     }
     break;
   case 'faq':
     final items=block.data['items'];
     if(items is List && items.length<=60 && items.every((x)=>x is Map&&x['question'] is String&&x['answer'] is String)){
       return Column(children:[for(final entry in items)ExpansionTile(title:Text(entry['question'] as String),
         children:[Padding(padding:const EdgeInsets.all(12),child:Text(entry['answer'] as String))])]);
     }
     break;
  }
  final optional=customRenderer?.call(context,block);
  if(optional!=null)return optional;
  final isAr=Localizations.maybeLocaleOf(context)?.languageCode=='ar';
  return Semantics(label:isAr?'عنصر محتوى غير مدعوم: ${block.type}':'Unsupported content block: ${block.type}',
    child:Text(isAr?'عنصر محتوى غير مدعوم (${block.type})':'Unsupported content block (${block.type})',
    style:typography.bodySmall));
 }
}

/// Optional complete screen *built from shared widgets*. It is not forced into
/// generated routes; parent chooses slug and a backend-verified repository.
class FablePublishedContentPage extends StatefulWidget {
 const FablePublishedContentPage({super.key,required this.slug,required this.repository,
  this.locale,this.customRenderer,this.onAccepted});
 final String slug;
 final FablePublishedContentRepository repository;
 final String? locale;
 final FableCustomBlockRenderer? customRenderer;
 final VoidCallback? onAccepted;
 @override State<FablePublishedContentPage> createState()=>_FablePublishedContentPageState();
}
class _FablePublishedContentPageState extends State<FablePublishedContentPage>{
 FablePublishedDocument? _document;
 bool _loading=false,_accepted=false,_accepting=false;
 int _requestEpoch=0;
 String? _error;
 @override void initState(){super.initState();_load();}
 @override void didUpdateWidget(covariant FablePublishedContentPage old){
  super.didUpdateWidget(old);
  if(old.slug!=widget.slug||old.locale!=widget.locale||!identical(old.repository,widget.repository)){
   _requestEpoch++;_loading=false;_document=null;_accepted=false;_load();
  }
 }
 Future<void> _load()async{
  if(_loading)return;
  final epoch=++_requestEpoch;
  setState((){_loading=true;_error=null;});
  final slug=widget.slug,locale=widget.locale;
  try{
   final document=await widget.repository.read(slug,locale:locale);
   if(mounted && epoch==_requestEpoch && slug==widget.slug&&locale==widget.locale)setState(()=>_document=document);
  }catch(_){if(mounted&&epoch==_requestEpoch&&slug==widget.slug)setState(()=>_error='Content unavailable. Check connection and contract.');}
  finally{if(mounted&&epoch==_requestEpoch)setState(()=>_loading=false);}
 }
 Future<void> _accept()async{
  final document=_document;if(_accepting||document==null||!document.requiresAcceptance)return;
  setState(()=>_accepting=true);
  try{await widget.repository.accept(document);
   if(mounted && identical(_document,document)){setState(()=>_accepted=true);widget.onAccepted?.call();}
  }catch(_){if(mounted)setState(()=>_error='Could not record acceptance. Sign in and retry.');}
  finally{if(mounted)setState(()=>_accepting=false);}
 }
 @override Widget build(BuildContext context){
  final ar=Localizations.maybeLocaleOf(context)?.languageCode=='ar';
  return Scaffold(appBar:AppBar(title:Text(_document?.title??(ar?'محتوى منشور':'Published content'))),
   body:SafeArea(child:Column(children:[
    if(_loading)const LinearProgressIndicator(),
    if(_error!=null)Text(_error!),
    Expanded(child:_document!=null?FablePublishedContentView(document:_document!,customRenderer:widget.customRenderer)
     :FableStateView(state:_loading?FableContentState.loading:FableContentState.empty,
       onRetry:_loading?null:_load)),
    if(_document?.requiresAcceptance==true && !_accepted)Padding(padding:const EdgeInsets.all(12),
      child:FilledButton(onPressed:_accepting||_loading?null:_accept,
        child:Text(ar?'أوافق على النسخة المنشورة':'Accept published version'))),
   ])));
 }
}

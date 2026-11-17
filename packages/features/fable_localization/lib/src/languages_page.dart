import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fable_core/fable_core.dart';
import 'languages_repository.dart';
import 'client_copy_sync.dart';
/// The catalog is informational. Changing app locale must use the app-level
/// locale controller and persist explicit user preference, not force network.
class FableLanguagesPage extends StatefulWidget {
 const FableLanguagesPage({super.key,required this.contract,this.injectedGateway,this.backendOrigin});
 final FableContract contract;
 /// External backends may supply their contract-verified adapter explicitly.
 final BackendApiGateway? injectedGateway;
 final Uri? backendOrigin;
 @override State<FableLanguagesPage> createState()=>_FableLanguagesPageState();
}
class _FableLanguagesPageState extends State<FableLanguagesPage> {
 static const origin=String.fromEnvironment('FABLE_API_BASE_URL');
 FableAuthGateway? _client;
 List<FableLanguage>? _languages;
 FableClientCopySnapshot? _copy;
 bool _checkingCopy=false;
 String? _lastCopyLocale;
 String? _copyError;
 bool _busy=false;String? _error;
 int _sourceEpoch=0;
 int _copyEpoch=0;
 // A contract, transport or origin change invalidates every prior GET result.
 @override void didUpdateWidget(covariant FableLanguagesPage old){
  super.didUpdateWidget(old);
  if(!identical(old.contract,widget.contract) ||
     !identical(old.injectedGateway,widget.injectedGateway) ||
     old.backendOrigin!=widget.backendOrigin){
   _sourceEpoch++;
   _copyEpoch++;
   _client?.dispose();
   _client=null;
   _languages=null;_copy=null;
   _busy=false;_checkingCopy=false;
   _lastCopyLocale=null;_copyError=null;_error=null;
  }
 }
 String get chosenOrigin=>widget.backendOrigin?.origin??origin;
 BackendApiGateway get transport => widget.injectedGateway??(_client??=FableAuthGateway(
   baseUri:Uri.parse(chosenOrigin),contract:widget.contract,
   allowHttpForLocalDevelopment:kDebugMode));
 // An externally authenticated gateway can read without a guessed URL.
 bool get supported=>(widget.injectedGateway!=null||chosenOrigin.isNotEmpty)&&
   widget.contract.supports('languages.list');
 bool get copySupported=>chosenOrigin.isNotEmpty&&widget.contract.supports('languages.clientCopy');
 Future<void> checkCopy({bool force=false})async{
  if(_checkingCopy||!copySupported)return;
  final epoch=_sourceEpoch;
  final copyEpoch=_copyEpoch;
  final namespace=chosenOrigin;
  final locale=Localizations.localeOf(context).toLanguageTag().toLowerCase();
  bool sameRequest()=>mounted && epoch==_sourceEpoch &&
    copyEpoch==_copyEpoch &&
    namespace==chosenOrigin &&
    Localizations.localeOf(context).toLanguageTag().toLowerCase()==locale;
  setState((){_checkingCopy=true;_copyError=null;});
  try{
   final client=transport;
   final updated=await FableClientCopySync(client,namespace:namespace).sync(locale,force:force);
   if(sameRequest())setState(()=>_copy=updated);
  }catch(_){
   if(sameRequest())setState(()=>_copyError=
     'Published text updates are temporarily unavailable. Bundled translations are unchanged.');
  }finally{if(sameRequest())setState(()=>_checkingCopy=false);}
 }
 Future<void> load() async{
  if(_busy||!supported)return;
  final epoch=_sourceEpoch;
  final namespace=chosenOrigin;
  bool sameRequest()=>mounted && epoch==_sourceEpoch &&
    namespace==chosenOrigin;
  setState((){_busy=true;_error=null;});
  try{
   final client=transport;
   final entries=await FableLanguagesRepository(client).list();
   if(sameRequest())setState(()=>_languages=entries);
  }catch(_){
   if(sameRequest())setState(()=>_error='Could not load supported languages.');
  }finally{if(sameRequest())setState(()=>_busy=false);}
 }
 @override void didChangeDependencies(){
  super.didChangeDependencies();
  if(copySupported){
   final locale=Localizations.localeOf(context).toLanguageTag().toLowerCase();
   if(_lastCopyLocale!=locale){
    // An earlier locale's request must not strand _checkingCopy=true.
    // Invalidate only copy, not an unrelated language list GET.
    _copyEpoch++;
    _checkingCopy=false;
    _copy=null;
    _copyError=null;
    _lastCopyLocale=locale;
    WidgetsBinding.instance.addPostFrameCallback((_){
      if(mounted && _lastCopyLocale==locale)checkCopy();
    });
   }
  }
 }
 @override void dispose(){
  _sourceEpoch++;
  _client?.dispose();
  super.dispose();
 }
 @override Widget build(BuildContext context){
  final ar=Localizations.localeOf(context).languageCode=='ar';
  final uiLocale=FableAppLocaleScope.maybeOf(context);
  return Scaffold(appBar:AppBar(title:Text(_copy?.text('languages.title',ar?'اللغات المدعومة':'Supported languages')??(ar?'اللغات المدعومة':'Supported languages'))),
   body:SafeArea(child:ListView(padding:const EdgeInsets.all(16),children:[
    if(!supported)Text(ar?'كتالوج اللغات غير متاح في عقد هذا الخادم.':'Language catalog is not in the imported contract.'),
    if(_busy)const LinearProgressIndicator(),
    if(_error!=null)Text(ar?'تعذر جلب قائمة اللغات.':_error!),
    if(uiLocale!=null)TextButton(
      onPressed:uiLocale.selectedTag==null?null:()=>uiLocale.onSelect(null),
      child:Text(ar?'استخدام لغة الجهاز':'Use device language')),
    for(final language in _languages??<FableLanguage>[])ListTile(
     title:Text(language.name),
     subtitle:Text(uiLocale==null||uiLocale.supports(language.code)
       ?language.code
       :ar?'هذه اللغة متاحة في الخادم وليست ضمن لغات واجهة التطبيق':
         'Available in Backend, but not bundled in this app UI'),
     onTap:uiLocale?.supports(language.code)==true
       ?()=>uiLocale!.onSelect(language.code):null,
     trailing:uiLocale?.selectedTag==language.code
       ?Icon(Icons.check_circle,semanticLabel:ar?'المحددة':'Selected')
       :language.isDefault
         ?Icon(Icons.info_outline,semanticLabel:ar?'افتراضية الخادم':'Backend default')
         :null),
    if(supported)FilledButton(onPressed:_busy?null:load,child:Text(ar?'تحميل اللغات':'Load languages')),
    if(copySupported)...[
      const SizedBox(height:12),
      Text(ar?'تحديثات النصوص المنشورة':'Published text updates'),
      if(_copy!=null)Text(_copy!.offlineFallback
        ? (ar?'لا يوجد اتصال؛ النسخة المحلية لا تزال متاحة.':'Offline: saved text remains available.')
        : _copy!.fromCache?(ar?'لم تتغير النصوص؛ لا حاجة لإعادة تحميلها.':'No text changes to download.')
        : (ar?'تم تنزيل النصوص الجديدة فقط.':'Updated copy downloaded.')),
      if(_copyError!=null)Text(ar?'تعذر التحقق؛ يستخدم التطبيق النصوص المضمّنة.':_copyError!),
      OutlinedButton(onPressed:_checkingCopy?null:()=>checkCopy(force:true),
        child:Text(ar?'فحص تحديثات النصوص':'Check for copy updates')),
    ],
    const SizedBox(height:12),Text(ar?'يعرض الخادم اللغات التي يدعمها؛ لا يمكن اختيار لغة للواجهة إلا إذا أدرجها إعداد التطبيق.':'The Backend lists its languages. Only bundled app UI languages can be selected.'),
   ])),
  );
 }
}

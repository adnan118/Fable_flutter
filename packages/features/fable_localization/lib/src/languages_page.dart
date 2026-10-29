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
 String get chosenOrigin=>widget.backendOrigin?.origin??origin;
 BackendApiGateway get transport => widget.injectedGateway??(_client??=FableAuthGateway(
   baseUri:Uri.parse(chosenOrigin),contract:widget.contract,
   allowHttpForLocalDevelopment:kDebugMode));
 bool get supported=>chosenOrigin.isNotEmpty&&widget.contract.supports('languages.list');
 bool get copySupported=>chosenOrigin.isNotEmpty&&widget.contract.supports('languages.clientCopy');
 Future<void> checkCopy({bool force=false})async{
  if(_checkingCopy||!copySupported)return;
  setState((){_checkingCopy=true;_copyError=null;});
  try{
   final client=transport;
   final locale=Localizations.localeOf(context).toLanguageTag().toLowerCase();
   final updated=await FableClientCopySync(client,namespace:chosenOrigin).sync(locale,force:force);
   if(mounted)setState(()=>_copy=updated);
  }catch(_){if(mounted)setState(()=>_copyError='Published text updates are temporarily unavailable. Bundled translations are unchanged.');}
  finally{if(mounted)setState(()=>_checkingCopy=false);}
 }
 Future<void> load() async{
  if(_busy||!supported)return;
  setState((){_busy=true;_error=null;});
  try{
   final client=transport;
   final entries=await FableLanguagesRepository(client).list();
   if(mounted)setState(()=>_languages=entries);
  }catch(_){if(mounted)setState(()=>_error='Could not load supported languages.');}
  finally{if(mounted)setState(()=>_busy=false);}
 }
 @override void didChangeDependencies(){
  super.didChangeDependencies();
  if(copySupported){
   final locale=Localizations.localeOf(context).toLanguageTag().toLowerCase();
   if(_lastCopyLocale!=locale){
    _lastCopyLocale=locale;
    WidgetsBinding.instance.addPostFrameCallback((_){if(mounted)checkCopy();});
   }
  }
 }
 @override void dispose(){_client?.dispose();super.dispose();}
 @override Widget build(BuildContext context){
  final ar=Localizations.localeOf(context).languageCode=='ar';
  return Scaffold(appBar:AppBar(title:Text(_copy?.text('languages.title',ar?'اللغات المدعومة':'Supported languages')??(ar?'اللغات المدعومة':'Supported languages'))),
   body:SafeArea(child:ListView(padding:const EdgeInsets.all(16),children:[
    if(!supported)Text(ar?'كتالوج اللغات غير متاح في عقد هذا الخادم.':'Language catalog is not in the imported contract.'),
    if(_busy)const LinearProgressIndicator(),
    if(_error!=null)Text(ar?'تعذر جلب قائمة اللغات.':_error!),
    for(final language in _languages??<FableLanguage>[])ListTile(
     title:Text(language.name),subtitle:Text(language.code),
     trailing:language.isDefault?Icon(Icons.check_circle,semanticLabel:ar?'الافتراضية':'Default'):null),
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
    const SizedBox(height:12),Text(ar?'هذه اللغات مدعومة في الخادم؛ تغيير لغة الواجهة يتم عبر إعدادات التطبيق.':'These languages are supported by the backend; app language is managed separately.'),
   ])),
  );
 }
}

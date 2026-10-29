import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:fable_core/fable_core.dart';
import 'package:fable_design_system/fable_design_system.dart';
import 'generated/feature_registry.dart';
import 'generated/language_policy.dart';
import '../l10n/app_localizations.dart';
// FABLE_ACCESS_IMPORT_BEGIN
import 'package:fable_access_control/fable_access_control.dart';
// FABLE_ACCESS_IMPORT_END

// FABLE_PUSH_IMPORT_BEGIN
import 'package:fable_notifications/fable_notifications.dart';
import 'dart:async';
// FABLE_PUSH_IMPORT_END
/// A new project has NO implicit Backend. The CLI creates an explicit
/// assets/config/backend.json, and a network capability remains unavailable
/// until a compatible contract/adapter has been installed.
class FableStarterApp extends StatefulWidget {
  const FableStarterApp({super.key});
  @override State<FableStarterApp> createState() => _AppState();
}

class _Bootstrap {
  const _Bootstrap(this.backend,this.fableContract,this.externalContract,this.externalBindings);
  final BackendSelection backend;
  final FableContract? fableContract;
  final ExternalOperationCatalog? externalContract;
  final ExternalFeatureBindings? externalBindings;
}

class _AppState extends State<FableStarterApp> {
  // FABLE_PUSH_ROUTES_BEGIN
  StreamSubscription<FableIdentityEvent>? _fablePushIdentityEvents;
  Future<void> _fableSetupNotificationAuth()async {
    try {
      final snapshot=await _bootstrap;
      FableSecureSession? credentials;
      if(snapshot.fableContract!=null){
        const apiBase=String.fromEnvironment('FABLE_API_BASE_URL');
        if(apiBase.isNotEmpty){
          final auth=FableAuthGateway(baseUri:Uri.parse(apiBase),
            contract:snapshot.fableContract!);
          credentials=auth.session;
          auth.dispose();
        }
      } else if(snapshot.externalContract!=null){
        credentials=ExternalAuthGateway.secureSessionFor(snapshot.externalContract!);
      }
      if(!mounted||credentials==null)return;
      final safeSession=credentials;
      FableNotificationNavigation.instance.isAuthenticated=()async =>
        (await safeSession.accessToken)?.isNotEmpty==true;
      _fablePushIdentityEvents=safeSession.identityEvents.listen((event){
        if(!event.authenticated)FableNotificationNavigation.instance.clearPending();
        else unawaited(FableNotificationNavigation.instance.resumeAfterLogin());
      });
      // An initial notification may have been tapped before session setup.
      unawaited(FableNotificationNavigation.instance.resumeAfterLogin());
    } catch (_) {FableNotificationNavigation.instance.clearPending();}
  }
  @override void initState(){
    super.initState();
    FableNotificationNavigation.instance.navigateCapability=_fableNavigateFromNotification;
    FableNotificationNavigation.instance.isAuthenticated=()async=>false;
    unawaited(_fableSetupNotificationAuth());
    
  }
  Future<bool> _fableNavigateFromNotification(String target, Map<String,String> data) async {
    final snapshot=await _bootstrap;
    if(!mounted)return false;
    final nav=FableNotificationNavigation.instance.navigatorKey.currentState;
    if(nav==null)return false;
    for(final feature in installedFeatures){
      if(feature.id!=target)continue;
      Widget? page;
      if(snapshot.fableContract!=null){page=feature.screen(snapshot.fableContract!);}
      else if(snapshot.externalContract!=null){
        page=feature.externalScreen(snapshot.externalContract!,
          snapshot.externalBindings??ExternalFeatureBindings.empty());
      }
      if(page==null)return false;
      nav.push(MaterialPageRoute<void>(builder:(_)=>page!));
      return true;
    }
    return false;
  }
  
  @override void dispose() {
    unawaited(_fablePushIdentityEvents?.cancel());
    FableNotificationNavigation.instance.reset();
    super.dispose();
  }
  // FABLE_PUSH_ROUTES_END

  late final Future<_Bootstrap> _bootstrap = _load();
  Locale? _locale; // null = follow device language; Backend limits locales unless AI-only
  Locale get _resolvedLocale => FableLanguagePolicy.resolve(_locale ?? WidgetsBinding.instance.platformDispatcher.locale);

  Future<_Bootstrap> _load() async {
    final backend=await BackendSelection.fromAssets(rootBundle);
    if (backend.canUseExternalCatalog) {
      final catalog=await ExternalOperationCatalog.fromAssets(rootBundle);
      if (catalog.adapter!=backend.adapter)throw const FormatException('Backend adapter mismatch');
      final bindings=await ExternalFeatureBindings.loadOptional(rootBundle,catalog);
      return _Bootstrap(backend,null,catalog,bindings);
    }
    if (!backend.canUseFableContract) return _Bootstrap(backend,null,null,null);
    // Fail closed on mismatched / tampered contract. No guessed API paths.
    final contract=await FableContract.fromAssets(rootBundle);
    return _Bootstrap(backend,contract,null,null);
  }

  @override Widget build(BuildContext context) => MaterialApp(
    // FABLE_PUSH_NAV_BEGIN
    navigatorKey:FableNotificationNavigation.instance.navigatorKey,
    // FABLE_PUSH_NAV_END
    onGenerateTitle:(context)=>AppLocalizations.of(context).appTitle,debugShowCheckedModeBanner:false,
    locale:_locale,supportedLocales:AppLocalizations.supportedLocales,
    localeResolutionCallback:(device,allowed)=>FableLanguagePolicy.resolveUi(device,allowed.toList(growable:false)),
    localizationsDelegates:AppLocalizations.localizationsDelegates,
    // FABLE_ACCESS_BUILDER_BEGIN

    builder:(context,child)=>MaterialUiCompatibilityBridge(
      child:FutureBuilder<_Bootstrap>(future:_bootstrap,builder:(context,state) {
        final connection=state.data;
        return connection==null ? child! : FableAccessBootstrap(
          fableContract:connection.fableContract,
          externalCatalog:connection.externalContract,
          child:child!,
        );
      })),
    // FABLE_ACCESS_BUILDER_END
    theme:FableTokens.theme(Brightness.light),
    darkTheme:FableTokens.theme(Brightness.dark),
    home:Scaffold(
      appBar:AppBar(title:Builder(builder:(context)=>Text(AppLocalizations.of(context).appTitle)),actions:[
        PopupMenuButton<String>(
          tooltip:'Language / اللغة',
          onSelected:(selected)=>setState(()=>_locale=selected=='device'?null:Locale(selected)),
          itemBuilder:(context)=>[
            const PopupMenuItem<String>(value:'device',child:Text('Device / لغة الجهاز')),
            for(final choice in FableLanguagePolicy.supportedLocales)
              PopupMenuItem<String>(value:choice.languageCode,child:Text(choice.toLanguageTag())),
          ],
          icon:const Icon(Icons.language),
        ),
      ]),
      body:SafeArea(child:FutureBuilder<_Bootstrap>(future:_bootstrap,builder:(context,snapshot){
        if(snapshot.connectionState!=ConnectionState.done){
          return const Center(child:FableSkeleton(height:110,width:240));
        }
        if(snapshot.hasError){
          return Center(child:Padding(padding:const EdgeInsets.all(24),
            child:Text(_resolvedLocale.languageCode=='ar'
              ? 'تعذر التحقق من إعدادات Backend أو العقد. افحص التهيئة المستوردة.'
              : 'Backend configuration or contract verification failed.',textAlign:TextAlign.center)));
        }
        final connection=snapshot.data!;
        final isAr=_resolvedLocale.languageCode=='ar';
        final backend=connection.backend;
        final label=backend.isFable?'Fable Backend':backend.adapter=='openapi'?'Other Backend · OpenAPI':'Other Backend · Custom API';
        final ready=connection.fableContract!=null || connection.externalContract!=null;
        return LayoutBuilder(builder:(context,constraints){
          final columns=constraints.maxWidth>900?4:constraints.maxWidth>580?3:2;
          return CustomScrollView(slivers:[
            SliverPadding(padding:const EdgeInsets.all(18),sliver:SliverToBoxAdapter(
              child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                Text(isAr?'الميزات المتاحة':'Installed capabilities',style:Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height:8),Text(label,style:Theme.of(context).textTheme.titleMedium),
                const SizedBox(height:4),
                Text(ready
                  ? (isAr?'عقد Backend مستورد محليًا؛ لم يتم اختبار اتصال الخادم بعد':'Backend catalog imported locally; live server connectivity not verified')
                  : (isAr?'بانتظار تهيئة الاتصال لهذا الـBackend':'Backend integration pending configuration'),
                  style:Theme.of(context).textTheme.bodySmall),
                if(!ready) Padding(padding:const EdgeInsets.only(top:8),child:Text(
                  isAr?'الميزات المحلية قابلة للعرض. عمليات الشبكة لا تعمل حتى إعداد Adapter والعقود الخاصة بالخادم المختار.'
                      :'Local capabilities can be explored. Network operations remain disabled until a matching backend adapter and contract are configured.')),
              ]))),
            SliverPadding(padding:const EdgeInsets.all(12),sliver:SliverGrid.builder(
              itemCount:installedFeatures.length,
              gridDelegate:SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount:columns,childAspectRatio:1.5,
                mainAxisSpacing:10,crossAxisSpacing:10),
              itemBuilder:(context,index){final feature=installedFeatures[index];
                return Card(child:InkWell(borderRadius:BorderRadius.circular(18),onTap:(){
                  if(connection.fableContract!=null){Navigator.of(context).push(MaterialPageRoute<void>(
                    builder:(_)=>feature.screen(connection.fableContract!)));
                  }else if(connection.externalContract!=null){
                    final bindings=connection.externalBindings ?? ExternalFeatureBindings.empty();
                    final integrated=feature.externalScreen(connection.externalContract!,bindings);
                    final operationId=bindings.operation(feature.id,'read');
                    if(integrated!=null || operationId!=null){
                      Navigator.of(context).push(MaterialPageRoute<void>(
                        builder:(_)=>integrated ?? _ExternalReadPage(catalog:connection.externalContract!,
                          operationId:operationId!,featureTitle:feature.title)));
                    }else{
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text(
                        'No operation mapping is available for this feature yet.')));
                    }
                  }else{
                    showModalBottomSheet<void>(context:context,builder:(context)=>SafeArea(child:Padding(
                      padding:const EdgeInsets.all(24),child:Column(mainAxisSize:MainAxisSize.min,children:[
                        Text(feature.title,style:Theme.of(context).textTheme.titleLarge),
                        const SizedBox(height:12),
                        Text(isAr?(connection.externalContract!=null?'العقد الخارجي جاهز، ويلزم ربط العمليات الدلالية لهذه الميزة صراحة.':'الميزة مثبتة لكن الاتصال لم يجهز بعد.')
                                  :(connection.externalContract!=null?'External API catalog ready. Map this feature to its actual domain operations.':'Feature installed; integration pending. No endpoint is assumed.')),
                      ]))));
                  }
                },child:Padding(padding:const EdgeInsets.all(12),child:Column(
                  mainAxisAlignment:MainAxisAlignment.center,children:[
                    Icon(feature.icon,size:30,color:Theme.of(context).colorScheme.primary),
                    const SizedBox(height:8),Text(feature.title,textAlign:TextAlign.center,maxLines:2,
                    overflow:TextOverflow.ellipsis),
                  ]))));
              }),
            ),
          ]);
        });
      })),
    ),
  );
}

/// Developer-only explicit GET test for a semantic operation imported from a
/// non-Fable contract. No tokens, request data or secrets are logged to the UI.
class _ExternalReadPage extends StatefulWidget {
  const _ExternalReadPage({required this.catalog,required this.operationId,required this.featureTitle});
  final ExternalOperationCatalog catalog;
  final String operationId,featureTitle;
  @override State<_ExternalReadPage> createState()=>_ExternalReadPageState();
}
class _ExternalReadPageState extends State<_ExternalReadPage> {
  String status='The operation has not been called. This is a developer integration screen.';
  bool busy=false;
  Future<void> check() async {
    if(!kDebugMode)return;
    final op=widget.catalog.require(widget.operationId);
    if(op.method!='GET' || op.path.contains('{')){
      setState(()=>status='GET without path parameters is required for this safe preview.');return;
    }
    setState(()=>busy=true);
    final session=ExternalAuthGateway.secureSessionFor(widget.catalog);
    final gateway=ExternalApiGateway(catalog:widget.catalog,session:session);
    try {
      final response=await gateway.execute(widget.operationId);
      if(!mounted)return;
      // Do not display raw API payloads: they may contain private account data.
      setState(()=>status='HTTP ${response.statusCode}: contract-bound GET completed. Payload suppressed for privacy.');
    }catch(_){if(mounted)setState(()=>status='Request failed or authorization is required. Check staging and session setup.');}
    finally{gateway.dispose();if(mounted)setState(()=>busy=false);}
  }
  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:Text(widget.featureTitle)),
    body:SafeArea(child:Padding(padding:const EdgeInsets.all(24),child:Column(
      crossAxisAlignment:CrossAxisAlignment.start,children:[
      Text('Bound operation: ${widget.operationId}',style:Theme.of(context).textTheme.titleMedium),
      const SizedBox(height:12),Text(status),const SizedBox(height:20),
      if(kDebugMode) FilledButton(onPressed:busy?null:check,child:Text(busy?'Checking...':'Test GET (development only)')),
      if(!kDebugMode) const Text('API testing tools are disabled in release mode.'),
    ]))));
}

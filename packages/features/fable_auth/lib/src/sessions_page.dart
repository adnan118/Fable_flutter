import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'package:fable_core/fable_core.dart';

/// Actual Fable Backend GET /auth/sessions consumer.
/// Revocation is intentionally not exposed until the protected Step-up
/// challenge/header contract is implemented. Never treat the token cache as a
/// verified server session.
class FableSessionsPage extends StatefulWidget {
  const FableSessionsPage({super.key,required this.gateway,required this.contract});
  final FableAuthGateway gateway;
  final FableContract contract;

  @override State<FableSessionsPage> createState()=>_FableSessionsPageState();
}
class _FableSessionsPageState extends State<FableSessionsPage> {
  StreamSubscription<FableIdentityEvent>? _identityEvents;
  List<FableActiveSession>? _sessions;
  FableSessionPolicy? _policy;
  bool _loading=false;
  String? _error;

  @override void initState(){
    super.initState();
    _identityEvents=widget.gateway.session.identityEvents.listen((_){
      if(!mounted)return;
      setState((){
        _sessions=null;_policy=null;_loading=false;
        _error='The authentication session changed. Sign in again to refresh devices.';
      });
    });
    unawaited(_refresh());
  }
  Future<void> _refresh() async {
    if(_loading)return;
    if(!widget.contract.supports('auth.sessions')){
      setState(()=>_error='Backend does not expose auth.sessions in the imported contract.');
      return;
    }
    final revision=widget.gateway.session.identityRevision;
    setState((){_loading=true;_error=null;});
    try{
      final sessions=await widget.gateway.listActiveSessions();
      FableSessionPolicy? runtimePolicy;
      if(widget.contract.supports('auth.session-policy')){
        try{
          // Failure to read policy never causes an invented local default.
          runtimePolicy=await widget.gateway.loadSessionPolicy();
        }catch(_){runtimePolicy=null;}
      }
      if(!mounted || widget.gateway.session.identityRevision!=revision)return;
      setState((){_sessions=sessions;_policy=runtimePolicy;});
    }on FableApiException catch(error){
      if(!mounted || widget.gateway.session.identityRevision!=revision)return;
      setState((){
        _sessions=null;
        _error=error.status==401?'Sign in to view your active sessions.'
          :'Backend rejected the session list. Check access rights and connectivity.';
      });
    }catch(_){
      if(!mounted || widget.gateway.session.identityRevision!=revision)return;
      setState((){
        _sessions=null;
        _error='Could not validate the active-session response from Backend.';
      });
    }finally{
      if(mounted && widget.gateway.session.identityRevision==revision)
        setState(()=>_loading=false);
    }
  }

  @override void dispose(){
    unawaited(_identityEvents?.cancel());
    super.dispose();
  }
  @override Widget build(BuildContext context){
    final ar=Localizations.localeOf(context).languageCode=='ar';
    final policy=_policy, sessions=_sessions;
    final mode=policy==null
      ? (ar?'سياسة الأجهزة غير مؤكدة من الخادم':'Device policy not confirmed by server')
      : policy.mode=='single'
        ? (ar?'يسمح بجلسة واحدة':'Single session')
        : policy.maxActive==0
          ? (ar?'جلسات متعددة دون حد عددي':'Multiple sessions, no fixed limit')
          : (ar?'الحد الأقصى: ${policy.maxActive}':'Maximum active sessions: ${policy.maxActive}');
    return Scaffold(
      appBar:AppBar(title:Text(ar?'أجهزتي والجلسات النشطة':'My devices & sessions')),
      body:SafeArea(child:ListView(padding:const EdgeInsets.all(20),children:[
        Text(mode,style:Theme.of(context).textTheme.titleMedium),
        const SizedBox(height:8),
        Text(ar?'هذه البيانات مصدرها الخادم مباشرة، وليست قائمة أجهزة محفوظة على الهاتف.'
          :'This list comes from the active Backend, not from stored phone credentials.'),
        const SizedBox(height:14),
        OutlinedButton.icon(
          onPressed:_loading?null:()=>unawaited(_refresh()),
          icon:const Icon(Icons.refresh),
          label:Text(ar?'تحديث الجلسات':'Refresh sessions'),
        ),
        if(_loading) const Padding(padding:EdgeInsets.all(20),child:Center(child:CircularProgressIndicator())),
        if(_error!=null) Padding(padding:const EdgeInsets.all(12),
          child:Text(_error!,textAlign:TextAlign.center)),
        if(!_loading&&sessions!=null&&sessions.isEmpty)
          Padding(padding:const EdgeInsets.all(12),
            child:Text(ar?'لا توجد جلسات نشطة':'No active sessions were returned.')),
        if(sessions!=null)for(final session in sessions)
          Card(child:ListTile(
            leading:const Icon(Icons.devices_other),
            title:Text(session.displayName?.isNotEmpty==true
              ?session.displayName!
              :(session.deviceName?.isNotEmpty==true?session.deviceName!
                :(session.platform??session.clientType??'Device'))),
            subtitle:Text([
              if(session.platform?.isNotEmpty==true)session.platform!,
              if(session.clientType?.isNotEmpty==true)session.clientType!,
              '${ar?'آخر نشاط':'Last active'}: ${session.lastUsedAt?.toLocal().toString()??(ar?'غير متاح':'Unavailable')}',
              '${ar?'تنتهي':'Expires'}: ${session.expiresAt.toLocal()}',
            ].join(' · ')),
            trailing:session.isCurrent
              ?Chip(label:Text(ar?'الجهاز الحالي':'This device'))
              :null,
          )),
        const SizedBox(height:20),
        Text(ar
          ?'إلغاء جلسات الأجهزة الأخرى محميّ بإثبات أمني إضافي. لن يعرض التطبيق زر إلغاء قبل إكمال عقد Step-up الآمن مع الباك.'
          :'Revoking other devices requires a verified security challenge. Revocation remains unavailable until Step-up is integrated.',
          textAlign:TextAlign.center),
      ])),
    );
  }
}

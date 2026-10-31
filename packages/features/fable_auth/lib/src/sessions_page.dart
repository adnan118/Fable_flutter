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
  bool _actionBusy=false;
  String? _pendingSensitiveChallenge;
  String? _pendingSessionId;
  List<String>? _pendingSelectedIds;
  final Set<String> _selectedSessionIds=<String>{};
  bool _pendingLogoutAll=false;
  final _otpController=TextEditingController();
  String? _error;

  @override void initState(){
    super.initState();
    _identityEvents=widget.gateway.session.identityEvents.listen((_){
      if(!mounted)return;
      _clearSensitive();
      _selectedSessionIds.clear();
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
      setState((){
        _sessions=sessions;_policy=runtimePolicy;
        _selectedSessionIds.removeWhere((id)=>!sessions.any(
          (session)=>session.id==id&&!session.isCurrent));
      });
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

  bool get _supportsSingleRevoke=>widget.contract.operations.values.any(
    (op)=>op.path=='/auth/sessions/{id}/revoke' &&
      op.method=='POST' && op.requiresAuth && op.credentialHeader==null);
  bool get _supportsBulkRevoke=>widget.gateway.canRevokeSelectedSessions;
  bool get _supportsLogoutAll=>widget.contract.operations.values.any(
    (op)=>op.path=='/auth/logout-all' && op.method=='POST' &&
      op.requiresAuth && op.credentialHeader==null);

  Future<void> _revoke(String? target,{bool logoutAll=false,List<String>? selectedIds}) async {
    if(_actionBusy||_loading)return;
    if(logoutAll ? !_supportsLogoutAll
      : selectedIds!=null ? !_supportsBulkRevoke : !_supportsSingleRevoke)return;
    if(selectedIds!=null && (selectedIds.isEmpty||selectedIds.length>100||
      _sessions==null||selectedIds.any((id)=>!_sessions!.any(
        (session)=>session.id==id&&!session.isCurrent))))return;
    final ar=Localizations.localeOf(context).languageCode=='ar';
    final accepted=await showDialog<bool>(context:context,builder:(ctx)=>
      AlertDialog(
        title:Text(logoutAll?(ar?'تسجيل الخروج من جميع الأجهزة؟':'Sign out on every device?')
          :selectedIds!=null?(ar?'إلغاء الجلسات المحددة؟':'Revoke selected sessions?')
          :(ar?'إلغاء جلسة الجهاز؟':'Revoke this device session?')),
        content:Text(ar
          ?'سيطلب الخادم إثباتاً أمنياً إذا لم تكن المصادقة القوية حديثة.'
          :'The server may require recent strong authentication.'),
        actions:[
          TextButton(onPressed:()=>Navigator.pop(ctx,false),
            child:Text(ar?'إلغاء':'Cancel')),
          FilledButton(onPressed:()=>Navigator.pop(ctx,true),
            child:Text(ar?'تأكيد':'Confirm')),
        ],
      ));
    if(accepted!=true||!mounted)return;
    final epoch=widget.gateway.session.identityRevision;
    setState((){_actionBusy=true;_error=null;});
    try{
      if(logoutAll){
        await widget.gateway.revokeAllSessions();
      }else if(selectedIds!=null){
        await widget.gateway.revokeSelectedSessions(selectedIds);
      }else{
        await widget.gateway.revokeOtherSession(target!);
      }
      if(!mounted||epoch!=widget.gateway.session.identityRevision && !logoutAll)return;
      _clearSensitive();
      if(logoutAll){
        setState((){
          _sessions=null;_policy=null;
          _error=ar?'تم إلغاء الجلسات؛ سجّل الدخول مجدداً.':'Sessions revoked; sign in again.';
        });
      }else{
        _selectedSessionIds.clear();
        await _refreshAfterAction();
      }
    }on FableApiException catch(error){
      if(!mounted||widget.gateway.session.identityRevision!=epoch)return;
      if(error.code=='AUTH_RECENT_AUTH_REQUIRED'&&widget.gateway.canRequestSensitiveProof){
        try{
          final challenge=await widget.gateway.requestSensitiveActionOtp();
          if(!mounted||widget.gateway.session.identityRevision!=epoch)return;
          setState((){
            _pendingSensitiveChallenge=challenge;
            _pendingSessionId=target;
            _pendingSelectedIds=selectedIds==null?null:List<String>.unmodifiable(selectedIds);
            _pendingLogoutAll=logoutAll;
          });
        }catch(_){
          if(mounted)setState(()=>_error=ar
            ?'تعذّر طلب رمز إثبات العملية الحساسة من الخادم.'
            :'Could not request the server security challenge.');
        }
      }else{
        setState(()=>_error=error.code=='AUTH_INDEPENDENT_FACTOR_REQUIRED'
          ?(ar?'لا توجد وسيلة تحقق مستقلة متاحة؛ يلزم إعدادها على الخادم.'
            :'An independent authentication factor is required.')
          :(ar?'رفض الخادم إلغاء الجلسة.':'Backend rejected session revocation.'));
      }
    }catch(_){
      if(mounted&&epoch==widget.gateway.session.identityRevision)
        setState(()=>_error=ar?'تعذّر إلغاء الجلسة.':'Session revocation failed.');
    }finally{
      if(mounted)setState(()=>_actionBusy=false);
    }
  }

  void _clearSensitive(){
    _otpController.clear();
    _pendingSensitiveChallenge=null;
    _pendingSessionId=null;
    _pendingSelectedIds=null;
    _pendingLogoutAll=false;
  }

  Future<void> _refreshAfterAction() async {
    if(!mounted)return;
    setState(()=>_sessions=null);
    await _refresh();
  }

  Future<void> _confirmOtp() async {
    final challenge=_pendingSensitiveChallenge;
    if(challenge==null||_actionBusy)return;
    final target=_pendingSessionId;
    final selectedIds=_pendingSelectedIds;
    final all=_pendingLogoutAll;
    final epoch=widget.gateway.session.identityRevision;
    final ar=Localizations.localeOf(context).languageCode=='ar';
    setState((){_actionBusy=true;_error=null;});
    try{
      final proof=await widget.gateway.verifySensitiveActionOtp(
        challenge,_otpController.text.trim());
      if(widget.gateway.session.identityRevision!=epoch)throw StateError('Identity changed');
      if(all)await widget.gateway.revokeAllSessions(proof:proof);
      else if(selectedIds!=null)await widget.gateway.revokeSelectedSessions(selectedIds,proof:proof);
      else await widget.gateway.revokeOtherSession(target!,proof:proof);
      if(!mounted)return;
      setState((){
        _clearSensitive();
        if(all){
          _sessions=null;_policy=null;
          _error=ar?'تم تسجيل الخروج من جميع الأجهزة.':'Signed out of all devices.';
        }
      });
      if(!all){
        _selectedSessionIds.clear();
        await _refreshAfterAction();
      }
    }catch(_){
      if(mounted&&widget.gateway.session.identityRevision==epoch)
        setState(()=>_error=ar
          ?'لم يقبل الخادم إثبات العملية. تحقق من الرمز أو أعد طلبه.'
          :'The server did not accept the security proof. Retry with a new challenge.');
    }finally{
      if(mounted)setState(()=>_actionBusy=false);
    }
  }

  @override void dispose(){
    unawaited(_identityEvents?.cancel());
    _otpController.dispose();
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
              :_supportsBulkRevoke
                ?Checkbox(value:_selectedSessionIds.contains(session.id),
                  onChanged:_actionBusy||_loading?null:(checked)=>setState((){
                    if(checked==true)_selectedSessionIds.add(session.id);
                    else _selectedSessionIds.remove(session.id);
                  }))
              :_supportsSingleRevoke
                ?IconButton(
                  tooltip:ar?'إلغاء جلسة الجهاز':'Revoke device session',
                  onPressed:(_actionBusy||_loading)?null:()=>unawaited(_revoke(session.id)),
                  icon:const Icon(Icons.phonelink_erase_outlined))
                :null,
          )),
        const SizedBox(height:20),
        if(_actionBusy)const LinearProgressIndicator(),
        if(_supportsBulkRevoke&&_selectedSessionIds.isNotEmpty)
          FilledButton.tonalIcon(
            onPressed:_actionBusy||_loading?null:()=>unawaited(
              _revoke(null,selectedIds:List<String>.of(_selectedSessionIds))),
            icon:const Icon(Icons.phonelink_erase_outlined),
            label:Text(ar
              ?'إلغاء الجلسات المحددة ('+_selectedSessionIds.length.toString()+')'
              :'Revoke selected sessions ('+_selectedSessionIds.length.toString()+')'),
          ),
        if(_supportsLogoutAll)
          OutlinedButton.icon(
            onPressed:_actionBusy||_loading?null:()=>unawaited(_revoke(null,logoutAll:true)),
            icon:const Icon(Icons.logout),
            label:Text(ar?'تسجيل الخروج من كل الأجهزة':'Sign out of all devices'),
          ),
        if(_pendingSensitiveChallenge!=null)...[
          Text(ar?'أدخل رمز التحقق الحساس الذي أرسله الخادم'
            :'Enter the sensitive-action code sent by the backend'),
          TextField(controller:_otpController,keyboardType:TextInputType.number,
            obscureText:true,maxLength:10,
            decoration:InputDecoration(labelText:ar?'رمز OTP':'OTP code')),
          FilledButton(onPressed:_actionBusy?null:()=>unawaited(_confirmOtp()),
            child:Text(ar?'التحقق وإكمال الإلغاء':'Verify and revoke')),
          TextButton(onPressed:_actionBusy?null:()=>setState(_clearSensitive),
            child:Text(ar?'إلغاء التحقق':'Cancel verification')),
        ],
        Text(ar
          ?'الإلغاء يتم من الخادم فقط، وقد يحتاج OTP لغرض SENSITIVE_ACTION. لا تُرسل العملية عند غياب مسار موثّق.'
          :'Revocation is server-authoritative and may require SENSITIVE_ACTION OTP. No route is guessed.',
          textAlign:TextAlign.center),
      ])),
    );
  }
}

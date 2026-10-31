import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fable_core/fable_core.dart';
import 'package:fable_design_system/fable_design_system.dart';
import 'managed_accounts_repository.dart';
import 'managed_accounts_page.dart';

/// Safe Fable core account view. A project-specific Profile remains a separate
/// capability and needs its own declared contract and screens.
class FableAccountPage extends StatefulWidget {
  const FableAccountPage({super.key,required this.contract});
  final FableContract contract;
  @override State<FableAccountPage> createState()=>_FableAccountPageState();
}
class _FableAccountPageState extends State<FableAccountPage> {
  static const _url=String.fromEnvironment('FABLE_API_BASE_URL');
  FableAuthGateway? _gateway;
  StreamSubscription<FableIdentityEvent>? _identityEvents;
  int _generation=0;
  FableAccountSummary? _account;
  final _displayName=TextEditingController();
  String? _error;
  bool _busy=false;

  bool get _supported=>widget.contract.supports('account.me') && _url.isNotEmpty;
  bool get _isAr=>Localizations.localeOf(context).languageCode=='ar';
  bool _current(int generation, FableAuthGateway client, int revision) =>
      mounted && generation==_generation && identical(client,_gateway) &&
      client.session.identityRevision==revision;

  void _subscribeToIdentity(FableAuthGateway client){
    _identityEvents ??= client.session.identityEvents.listen((_){
      if(!mounted)return;
      _generation++;
      _displayName.clear();
      setState((){_account=null;_error=null;_busy=false;});
    });
  }

  @override void didUpdateWidget(covariant FableAccountPage old){
    super.didUpdateWidget(old);
    if(!identical(old.contract,widget.contract)){
      _generation++;
      unawaited(_identityEvents?.cancel());
      _identityEvents=null;
      _gateway?.dispose();
      _gateway=null;
      _displayName.clear();
      _account=null;_error=null;_busy=false;
    }
  }

  Future<void> _read() async {
    if(_busy || !_supported)return;
    final requestGeneration=_generation;
    final initialGateway=_gateway;
    final initialRevision=initialGateway?.session.identityRevision;
    setState(() {_busy=true;_error=null;});
    try {
      final client=_gateway ??= FableAuthGateway(baseUri:Uri.parse(_url),
        contract:widget.contract,allowHttpForLocalDevelopment:kDebugMode);
      _subscribeToIdentity(client);
      final revision=client.session.identityRevision;
      final generation=_generation;
      final account=await client.account();
      if(!_current(generation,client,revision))return;
      _displayName.text=account.displayName ?? '';
      setState(() => _account=account);
    } on FableApiException catch(error) {
      if(!mounted || _generation!=requestGeneration ||
          (initialGateway!=null && (initialGateway!=_gateway ||
            initialRevision!=initialGateway.session.identityRevision)))return;
      setState(() {_account=null;_error=error.status==401
        ? (_isAr?'يلزم تسجيل الدخول لعرض الحساب.':'Sign in to view your account.')
        : (_isAr?'تعذّر تحميل الحساب. تحقق من الاتصال أو الصلاحيات.':'Unable to load account. Check connection and permissions.');});
    } catch (_) {
      if(mounted && _generation==requestGeneration &&
          (initialGateway==null || (identical(initialGateway,_gateway) &&
            initialRevision==initialGateway.session.identityRevision)))setState(() {_account=null;_error=_isAr
        ? 'تعذّر التحقق من بيانات الحساب أو العقد.':'Account response or contract could not be verified.';});
    } finally {if(mounted && _generation==requestGeneration &&
       (initialGateway==null || (identical(initialGateway,_gateway) &&
         initialRevision==initialGateway.session.identityRevision)))setState(()=>_busy=false);}
  }

  Future<void> _updateDisplayName() async {
    if(_busy || _account==null || !widget.contract.supports('account.displayName.update'))return;
    final name=_displayName.text.trim();
    if(name.isEmpty || name.length>100 || RegExp(r'[\x00-\x1F\x7F<>]').hasMatch(name)){
      setState(()=>_error=_isAr?'الاسم غير صالح (1–100 حرف).':'Invalid display name (1–100 characters).');
      return;
    }
    final generation=_generation;
    setState(() {_busy=true;_error=null;});
    try {
      final client=_gateway!;
      final revision=client.session.identityRevision;
      final updated=await client.updateAccountDisplayName(name);
      if(!_current(generation,client,revision))return;
      _displayName.text=updated.displayName ?? '';
      setState(()=>_account=updated);
    } catch (_) {
      if(mounted && generation==_generation)setState(()=>_error=_isAr?'فشل حفظ الاسم؛ أعد المحاولة بعد التحقق من الجلسة.':'Name could not be saved. Verify your session and retry.');
    } finally {if(mounted && generation==_generation)setState(()=>_busy=false);}
  }

  @override void dispose(){_generation++;unawaited(_identityEvents?.cancel());
    _displayName.dispose();_gateway?.dispose();super.dispose();}
  @override Widget build(BuildContext context) {
    final ar=_isAr;
    return Scaffold(appBar:AppBar(title:Text(ar?'الحساب':'Account')),
      body:SafeArea(child:ListView(padding:const EdgeInsets.all(24),children:[
        const Icon(Icons.account_circle_outlined,size:64),
        const SizedBox(height:14),
        if(!_supported) FableStateView(state:FableContentState.error,message: ar
          ? 'عملية account.me غير موجودة في عقد Fable المستورد أو لم يتم ضبط عنوان الخادم.'
          : 'account.me is not in the imported Fable contract, or the backend URL is missing.'),
        if(_busy) const FableStateView(state:FableContentState.loading),
        if(_error!=null) Text(_error!,textAlign:TextAlign.center),
        if(_account!=null)...[
          if(_account!.displayName?.isNotEmpty==true) SelectableText(_account!.displayName!,
            style:Theme.of(context).textTheme.titleLarge,textAlign:TextAlign.center),
          if(_account!.username?.isNotEmpty==true) SelectableText(_account!.username!,textAlign:TextAlign.center),
          if(_account!.email?.isNotEmpty==true) SelectableText(_account!.email!,textAlign:TextAlign.center),
          if(_account!.phone?.isNotEmpty==true) SelectableText(_account!.phone!,textAlign:TextAlign.center),
          if(widget.contract.supports('account.displayName.update')) ...[
            const SizedBox(height:14),
            TextField(controller:_displayName,maxLength:100,enabled:!_busy,
              decoration:InputDecoration(labelText:ar?'الاسم الظاهر':'Display name')),
            FilledButton.tonal(onPressed:_busy?null:_updateDisplayName,
              child:Text(ar?'حفظ الاسم':'Save display name')),
          ],
        ] else if(_supported && !_busy) FableStateView(state:FableContentState.empty,
          message:ar?'لم يتم تحميل بيانات الحساب بعد.':'Account has not been loaded yet.'),
        const SizedBox(height:18),
        if(_supported) FilledButton(onPressed:_busy?null:_read,
          child:Text(ar?'تحميل بيانات الحساب':'Load account')),
        const SizedBox(height:20),
        if(_supported && FableManagedAccountsRepository(
          _gateway ??= FableAuthGateway(baseUri:Uri.parse(_url),
            contract:widget.contract,allowHttpForLocalDevelopment:kDebugMode),
          widget.contract).canList)
          FilledButton.tonal(
            onPressed:_busy?null:()=>Navigator.of(context).push(
              MaterialPageRoute<void>(builder:(_)=>FableManagedAccountsPage(
                gateway:_gateway!,contract:widget.contract))),
            child:Text(ar?'إدارة الكيانات التابعة لي':'My managed entities')),
        const SizedBox(height:12),
        Text(ar?'هذا عرض الحساب الأساسي فقط. بيانات الملف الشخصي الخاصة بالمشروع تتطلب عقد Profile منفصلًا.'
          :'This is the core account only. Project-specific Profile fields require a separate backend contract.',
          textAlign:TextAlign.center),
      ])),
    );
  }
}

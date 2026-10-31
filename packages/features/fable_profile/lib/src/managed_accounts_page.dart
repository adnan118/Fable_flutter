import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'package:fable_core/fable_core.dart';
import 'managed_accounts_repository.dart';

/// Available ONLY with explicit Fable managed-entities contract operations.
/// Local selection cannot confer role, grant membership or synthesize a route.
class FableManagedAccountsPage extends StatefulWidget {
  const FableManagedAccountsPage({super.key,required this.gateway,required this.contract,
    this.onActivated});
  final FableAuthGateway gateway;
  final FableContract contract;
  final ValueChanged<FableManagedAccountSelection>? onActivated;
  @override State<FableManagedAccountsPage> createState()=>_FableManagedAccountsPageState();
}
class _FableManagedAccountsPageState extends State<FableManagedAccountsPage> {
  late final FableManagedAccountsRepository _repo=
    FableManagedAccountsRepository(widget.gateway,widget.contract);
  StreamSubscription<FableIdentityEvent>? _events;
  List<FableManagedAccount>? _entities;
  List<FableManagedInvitation>? _invitations;
  FableManagedAccountSelection? _selected;
  bool _busy=false;
  String? _message;
  bool get _ar=>Localizations.localeOf(context).languageCode=='ar';
  @override void initState(){
    super.initState();
    _events=widget.gateway.session.identityEvents.listen((_){
      if(mounted)setState((){
        _entities=null;_invitations=null;_selected=null;_busy=false;
        _message='Login identity changed. Refresh the new account.';
      });
    });
    WidgetsBinding.instance.addPostFrameCallback((_){if(mounted)unawaited(_reload());});
  }
  Future<void> _reload()async{
    if(_busy||!_repo.canList)return;
    final epoch=widget.gateway.session.identityRevision;
    setState((){_busy=true;_message=null;});
    try{
      final entities=await _repo.listMine();
      final invites=_repo.canReadInvitations?await _repo.invitationsMine():<FableManagedInvitation>[];
      if(!mounted||epoch!=widget.gateway.session.identityRevision)return;
      setState((){
        _entities=entities;_invitations=invites;
        if(!entities.any((e)=>e.id==_selected?.id&&e.status=='ACTIVE'))_selected=null;
      });
    }catch(_){if(mounted&&epoch==widget.gateway.session.identityRevision)
      setState(()=>_message='Backend did not authorize reading managed entities.');}
    finally{if(mounted&&epoch==widget.gateway.session.identityRevision)setState(()=>_busy=false);}
  }
  Future<void> _activate(FableManagedAccount entity)async{
    if(_busy||!_repo.canActivate)return;
    final epoch=widget.gateway.session.identityRevision;
    setState((){_busy=true;_message=null;_selected=null;});
    try{
      final selected=await _repo.activate(entity);
      if(!mounted||epoch!=widget.gateway.session.identityRevision)return;
      setState(()=>_selected=selected);
      widget.onActivated?.call(selected);
    }catch(_){if(mounted&&epoch==widget.gateway.session.identityRevision)
      setState(()=>_message='Backend rejected activation or membership.');}
    finally{if(mounted&&epoch==widget.gateway.session.identityRevision)setState(()=>_busy=false);}
  }
  Future<bool> _confirm(String title)async=>
    await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
      title:Text(title),
      actions:[
        TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancel')),
        FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Confirm')),
      ]))??false;
  Future<void> _create()async{
    if(_busy||!_repo.canCreate)return;
    final type=TextEditingController(),ar=TextEditingController(),en=TextEditingController();
    try{
      final form=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
        title:Text(_ar?'إنشاء كيان':'Create entity'),
        content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
          TextField(controller:type,maxLength:64,decoration:const InputDecoration(labelText:'Backend-enabled type')),
          TextField(controller:ar,maxLength:191,decoration:const InputDecoration(labelText:'Arabic name')),
          TextField(controller:en,maxLength:191,decoration:const InputDecoration(labelText:'English name')),
        ])),
        actions:[
          TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancel')),
          FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Create private entity')),
        ]));
      if(form!=true||!mounted)return;
      final rev=widget.gateway.session.identityRevision;
      setState((){_busy=true;_message=null;});
      try{
        // Private by default. Visibility changes require a separate reviewed UI.
        await _repo.create(type:type.text,nameAr:ar.text,nameEn:en.text,visibility:'PRIVATE');
        if(mounted&&rev==widget.gateway.session.identityRevision)await _reloadAfterMutation();
      }catch(_){if(mounted&&rev==widget.gateway.session.identityRevision)
        setState(()=>_message='Backend rejected entity creation (type, quota or authorization).');}
      finally{if(mounted&&rev==widget.gateway.session.identityRevision)setState(()=>_busy=false);}
    }finally{type.dispose();ar.dispose();en.dispose();}
  }
  Future<void> _reloadAfterMutation()async{
    if(!mounted)return;
    setState(()=>_busy=false);
    await _reload();
  }
  Future<void> _invite(FableManagedAccount entity)async{
    final chosen=_selected;
    if(_busy||chosen?.id!=entity.id||!_repo.canInvite||
       !entity.collaborationEnabled||
       !(chosen!.access=='OWNER'||chosen.access=='MANAGER'&&entity.managersCanInvite))return;
    final username=TextEditingController();
    try{
      final agreed=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
        title:const Text('Invite viewer'),
        content:TextField(controller:username,maxLength:30,decoration:const InputDecoration(
          labelText:'Existing username')),
        actions:[
          TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancel')),
          FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Invite')),
        ]));
      if(agreed!=true||!mounted)return;
      final rev=widget.gateway.session.identityRevision;
      setState((){_busy=true;_message=null;});
      try{
        await _repo.invite(entity.id,username:username.text.trim(),access:'VIEWER');
        if(mounted&&rev==widget.gateway.session.identityRevision)
          setState(()=>_message='Backend accepted the invitation.');
      }catch(_){if(mounted&&rev==widget.gateway.session.identityRevision)
        setState(()=>_message='Backend denied the invitation.');}
      finally{if(mounted&&rev==widget.gateway.session.identityRevision)setState(()=>_busy=false);}
    }finally{username.dispose();}
  }
  Future<void> _respond(FableManagedInvitation invite,bool accept)async{
    if(_busy||!await _confirm(accept?'Accept invitation?':'Decline invitation?'))return;
    if(!mounted)return;
    final rev=widget.gateway.session.identityRevision;
    setState((){_busy=true;_message=null;});
    try{
      await _repo.respondToInvitation(invite.id,accept:accept);
      if(mounted&&rev==widget.gateway.session.identityRevision)await _reloadAfterMutation();
    }catch(_){if(mounted&&rev==widget.gateway.session.identityRevision)
      setState(()=>_message='Backend rejected the invitation action.');}
    finally{if(mounted&&rev==widget.gateway.session.identityRevision)setState(()=>_busy=false);}
  }
  @override void dispose(){unawaited(_events?.cancel());super.dispose();}
  @override Widget build(BuildContext context){
    final ar=_ar;
    return Scaffold(appBar:AppBar(title:Text(ar?'الكيانات التي أديرها':'Managed entities')),
      body:SafeArea(child:ListView(padding:const EdgeInsets.all(18),children:[
        if(!_repo.canList)Text(ar?'ميزة الكيانات غير موجودة في عقد الباك المستورد.'
          :'The imported Fable contract has no managed-entities listing operation.'),
        if(_busy)const LinearProgressIndicator(),
        if(_message!=null)Text(_message!),
        if(_repo.canList)OutlinedButton.icon(
          onPressed:_busy?null:()=>unawaited(_reload()),
          icon:const Icon(Icons.refresh),label:Text(ar?'تحديث':'Refresh')),
        if(_repo.canCreate)FilledButton.tonal(
          onPressed:_busy?null:()=>unawaited(_create()),
          child:Text(ar?'إنشاء كيان خاص':'Create private entity')),
        if(_entities?.isEmpty==true)Text(ar?'لا توجد كيانات متاحة':'No managed entities'),
        for(final entity in _entities??<FableManagedAccount>[])Card(child:Column(children:[
          ListTile(
            title:Text(ar?entity.nameAr:entity.nameEn),
            subtitle:Text(entity.type+' · '+entity.status+' · '+entity.visibility),
            trailing:_selected?.id==entity.id
              ?Chip(label:Text(_selected!.access))
              :entity.status=='ACTIVE'&&_repo.canActivate
                ?OutlinedButton(
                  onPressed:_busy?null:()=>unawaited(_activate(entity)),
                  child:Text(ar?'اختيار':'Select'))
                :null),
          if(_selected?.id==entity.id&&entity.collaborationEnabled&&
            _repo.canInvite&&(_selected!.access=='OWNER'||
            _selected!.access=='MANAGER'&&entity.managersCanInvite))
            TextButton(onPressed:_busy?null:()=>unawaited(_invite(entity)),
              child:Text(ar?'دعوة مشاهد':'Invite viewer')),
        ])),
        if(_selected!=null)Text((ar?'السياق المعتمد: ':'Selected: ')+
          (ar?_selected!.nameAr:_selected!.nameEn)+' ('+_selected!.access+
          '). Backend re-verifies membership; this screen does not grant roles.'),
        if(_repo.canReadInvitations)...[
          const Divider(),Text(ar?'دعواتي':'My invitations'),
          for(final item in _invitations??<FableManagedInvitation>[])
            ListTile(title:Text(item.entityName),subtitle:Text(item.access),
              trailing:Wrap(children:[
                TextButton(onPressed:_busy?null:()=>unawaited(_respond(item,true)),
                  child:Text(ar?'قبول':'Accept')),
                TextButton(onPressed:_busy?null:()=>unawaited(_respond(item,false)),
                  child:Text(ar?'رفض':'Decline')),
              ])),
        ]
      ])),
    );
  }
}

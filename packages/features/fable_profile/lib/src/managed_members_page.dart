import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fable_core/fable_core.dart';
import 'managed_accounts_repository.dart';

/// Lists only backend-authorized entity users. No membership is inferred from
/// a visible entity, and removal cannot target the immutable owner.
class FableManagedMembersPage extends StatefulWidget {
  const FableManagedMembersPage({super.key,required this.repo,
    required this.entity,required this.selection,this.managedStore});
  final FableManagedEntityStore? managedStore;
  final FableManagedAccountsRepository repo;
  final FableManagedAccount entity;
  final FableManagedAccountSelection selection;
  @override State<FableManagedMembersPage> createState()=>_FableManagedMembersPageState();
}
class _FableManagedMembersPageState extends State<FableManagedMembersPage>
    with WidgetsBindingObserver {
  final _members=<FableManagedMember>[];
  final _sentInvitations=<FableSentInvitation>[];
  String? _memberCursor,_invitationCursor,_error;
  bool _membersComplete=false,_invitationsComplete=false,_busy=false;
  bool _verifying=false,_invalid=false;
  int _requestGeneration=0;
  late final int? _openedSelectionRevision;
  StreamSubscription<FableIdentityEvent>? _identities;
  bool get _ar=>Localizations.localeOf(context).languageCode=='ar';

  /// The page cannot silently follow B (or A→B→A) while its route still
  /// represents A. Store revision and identical activation are both required.
  bool get _current {
    final store=widget.managedStore;
    return !_invalid && store!=null &&
      _openedSelectionRevision==store.selectionRevision &&
      identical(store.selected,widget.selection) &&
      store.isBoundToCredentials(widget.repo.gateway.session) &&
      store.isBoundToBackend(widget.repo.gateway.managedEntityBackendIdentity) &&
      widget.selection.identityRevision==widget.repo.gateway.session.identityRevision;
  }
  bool _at(int generation)=>mounted && _current &&
      !_verifying && generation==_requestGeneration;
  bool get _owner=>_current && !_verifying && widget.entity.isOwner &&
    widget.selection.access=='OWNER';
  bool get _invitationAdmin=>_current && !_verifying &&
    widget.entity.collaborationEnabled &&
    (widget.selection.access=='OWNER'||
     widget.selection.access=='MANAGER'&&widget.entity.managersCanInvite);
  void _invalidate(String message){
    _requestGeneration++;
    if(!mounted)return;
    setState((){
      _invalid=true;_verifying=false;_busy=false;
      _members.clear();_sentInvitations.clear();
      _memberCursor=null;_invitationCursor=null;
      _membersComplete=true;_invitationsComplete=true;
      _error=message;
    });
  }
  void _onManagedSelectionChanged(){
    if(!_current) _invalidate('Selected managed entity context changed. Reopen this page.');
  }
  @override void initState(){
    super.initState();
    // Capture the exact selection epoch before any async route initialization.
    _openedSelectionRevision=widget.managedStore?.selectionRevision;
    WidgetsBinding.instance.addObserver(this);
    widget.managedStore?.addListener(_onManagedSelectionChanged);
    _identities=widget.repo.gateway.session.identityEvents.listen((_){
      _invalidate('Login changed. This entity context is no longer valid.');
    });
    WidgetsBinding.instance.addPostFrameCallback((_){
      if(!mounted)return;
      if(!_current) {
        _invalidate('A verified managed entity context is required.');
      } else {
        unawaited(_load());
      }
    });
  }
  @override void didUpdateWidget(covariant FableManagedMembersPage old){
    super.didUpdateWidget(old);
    if(!identical(widget.repo,old.repo) ||
       !identical(widget.entity,old.entity) ||
       !identical(widget.selection,old.selection) ||
       !identical(widget.managedStore,old.managedStore)){
      old.managedStore?.removeListener(_onManagedSelectionChanged);
      widget.managedStore?.addListener(_onManagedSelectionChanged);
      _invalidate('Managed entity page identity changed. Reopen this page.');
    }
  }
  @override void didChangeAppLifecycleState(AppLifecycleState state){
    if(state==AppLifecycleState.resumed)unawaited(_verifyMembershipOnResume());
  }
  Future<void> _verifyMembershipOnResume()async{
    if(!_current||_verifying)return;
    final generation=++_requestGeneration;
    setState((){
      _verifying=true;_busy=false;_error=null;
      _members.clear();_sentInvitations.clear();
      _membersComplete=false;_invitationsComplete=false;
      _memberCursor=null;_invitationCursor=null;
    });
    try {
      // The list is the current user's Backend-authoritative membership.
      // A selected role from an earlier snapshot is not enough after resume.
      final entities=await widget.repo.listMine();
      if(!mounted||!_current||generation!=_requestGeneration)return;
      final matches=entities.where((e)=>e.id==widget.selection.id &&
        e.status=='ACTIVE' && e.effectiveAccess==widget.selection.access &&
        (widget.selection.access!='OWNER'||e.isOwner) &&
        (widget.selection.access!='MANAGER'||e.collaborationEnabled)).toList();
      if(matches.length!=1){
        widget.managedStore?.clear();
        _invalidate('Backend no longer confirms this managed role.');
        return;
      }
      setState(()=>_verifying=false);
      await _load();
    }catch(_){
      if(!mounted||generation!=_requestGeneration)return;
      widget.managedStore?.clear();
      _invalidate('Backend could not revalidate the managed membership.');
    }
  }
  Future<void> _load({bool moreMembers=false,bool moreInvitations=false})async{
    if(_busy||!_current||_verifying)return;
    final generation=++_requestGeneration;
    final loadMembers=_owner&&widget.repo.canListMembers &&
      (moreMembers||(!moreInvitations&&!_membersComplete));
    final loadInvitations=_invitationAdmin&&widget.repo.canViewSentInvitations &&
      (moreInvitations||(!moreMembers&&!_invitationsComplete));
    if(!loadMembers&&!loadInvitations)return;
    setState((){_busy=true;_error=null;});
    try{
      if(loadMembers){
        final page=await widget.repo.members(widget.entity,widget.selection,
          after:moreMembers?_memberCursor:null);
        if(!_at(generation))return;
        setState((){
          if(!moreMembers)_members.clear();
          for(final member in page.items){
            if(!_members.any((existing)=>existing.userId==member.userId)){
              _members.add(member);
            }
          }
          if(moreMembers&&page.nextCursor==_memberCursor)
            throw const FormatException('Non-advancing member pagination');
          _memberCursor=page.nextCursor;
          _membersComplete=page.nextCursor==null;
        });
      }
      if(loadInvitations){
        final page=await widget.repo.sentInvitations(widget.entity,widget.selection,
          after:moreInvitations?_invitationCursor:null);
        if(!_at(generation))return;
        setState((){
          if(!moreInvitations)_sentInvitations.clear();
          for(final inv in page.items){
            if(!_sentInvitations.any((existing)=>existing.id==inv.id))
              _sentInvitations.add(inv);
          }
          if(moreInvitations&&page.nextCursor==_invitationCursor)
            throw const FormatException('Non-advancing invitation pagination');
          _invitationCursor=page.nextCursor;
          _invitationsComplete=page.nextCursor==null;
        });
      }
    }on FableApiException catch(error){
      if(!_at(generation))return;
      if(error.status==403||error.code=='MANAGED_ACCOUNT_NOT_FOUND'){
        widget.managedStore?.clear();
        _invalidate('Backend refused this managed role. Reopen after verification.');
      }else{
        setState(()=>_error=_ar?'تعذّر تحميل بيانات الإدارة الموثّقة من الخادم.'
          :'Backend refused or returned an invalid member/admin page.');
      }
    }catch(_){
      if(_at(generation))
        setState(()=>_error=_ar?'تعذّر تحميل بيانات الإدارة الموثّقة من الخادم.'
          :'Backend refused or returned an invalid member/admin page.');
    }finally{
      if(_at(generation))setState(()=>_busy=false);
    }
  }
  Future<void> _reload() async{
    if(!_current||_busy||_verifying)return;
    setState((){
      _membersComplete=false;_invitationsComplete=false;
      _memberCursor=null;_invitationCursor=null;
    });
    await _load();
  }
  Future<bool> _confirm(String label)async=>
    await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
      title:Text(label),
      content:Text(_ar?'سيطبق الخادم الصلاحيات ولا يمكن إزالة مالك الكيان.'
        :'Backend enforces membership rights; the owner cannot be removed.'),
      actions:[
        TextButton(onPressed:()=>Navigator.pop(ctx,false),
          child:Text(_ar?'إلغاء':'Cancel')),
        FilledButton(onPressed:()=>Navigator.pop(ctx,true),
          child:Text(_ar?'تأكيد':'Confirm')),
      ]))??false;
  Future<void> _remove(FableManagedMember member)async{
    if(!_current||_busy||!_owner||member.isOwner||
      !widget.repo.canRemoveMember)return;
    final generation=_requestGeneration;
    if(!await _confirm(_ar?'إزالة هذا العضو؟':'Remove this member?') ||
       !_at(generation)||!_owner)return;
    setState((){_busy=true;_error=null;});
    try{
      await widget.repo.removeMember(widget.entity,widget.selection,member);
      if(_at(generation)){
        setState((){
          _members.removeWhere((item)=>item.userId==member.userId);
          _memberCursor=null;_membersComplete=false;
        });
      }
    }catch(_){
      if(_at(generation))setState(()=>_error='Backend rejected this removal.');
    }finally{if(_at(generation))setState(()=>_busy=false);}
  }
  Future<void> _revoke(FableSentInvitation invitation)async{
    if(!_current||_busy||!_invitationAdmin||
      !widget.repo.canRevokeSentInvitation)return;
    final generation=_requestGeneration;
    if(!await _confirm(_ar?'إلغاء هذه الدعوة؟':'Revoke this invitation?') ||
       !_at(generation)||!_invitationAdmin)return;
    setState((){_busy=true;_error=null;});
    try{
      await widget.repo.revokeSentInvitation(widget.entity,widget.selection,invitation);
      if(_at(generation)){
        setState((){
          _sentInvitations.removeWhere((item)=>item.id==invitation.id);
          _invitationCursor=null;_invitationsComplete=false;
        });
      }
    }catch(_){
      if(_at(generation))setState(()=>_error='Backend rejected invitation revocation.');
    }finally{if(_at(generation))setState(()=>_busy=false);}
  }
  @override void dispose(){
    ++_requestGeneration;
    WidgetsBinding.instance.removeObserver(this);
    widget.managedStore?.removeListener(_onManagedSelectionChanged);
    unawaited(_identities?.cancel());
    super.dispose();
  }
  @override Widget build(BuildContext context){
    final ar=_ar;
    return Scaffold(appBar:AppBar(title:Text(ar?'أعضاء الكيان ودعواته':'Members and invitations')),
      body:SafeArea(child:ListView(padding:const EdgeInsets.all(16),children:[
        Text(ar?widget.entity.nameAr:widget.entity.nameEn,
          style:Theme.of(context).textTheme.titleLarge),
        if(_busy||_verifying)const LinearProgressIndicator(),
        if(_error!=null)Padding(padding:const EdgeInsets.all(8),child:Text(_error!)),
        if(_current)OutlinedButton.icon(onPressed:_busy||_verifying?null:()=>unawaited(_reload()),
          icon:const Icon(Icons.refresh),label:Text(ar?'تحديث':'Refresh')),
        if(_owner&&widget.repo.canListMembers)...[
          Text(ar?'الأعضاء النشطون':'Active members',
            style:Theme.of(context).textTheme.titleMedium),
          for(final member in _members)
            ListTile(
              title:Text(member.username??member.displayName??'Account'),
              subtitle:Text(member.access+
                (member.displayName==null?'':' · '+member.displayName!)),
              trailing:member.isOwner
                ?Chip(label:Text(ar?'المالك':'Owner'))
                :widget.repo.canRemoveMember
                  ?IconButton(onPressed:_busy||!_current?null:
                    ()=>unawaited(_remove(member)),
                    tooltip:ar?'إزالة العضو':'Remove member',
                    icon:const Icon(Icons.person_remove_outlined))
                  :null,
            ),
          if(!_membersComplete)
            TextButton(onPressed:_busy?null:()=>unawaited(
              _load(moreMembers:_memberCursor!=null)),
              child:Text(ar?'عرض المزيد من الأعضاء':'Load more members')),
        ],
        if(_invitationAdmin&&widget.repo.canViewSentInvitations)...[
          const Divider(),
          Text(ar?'الدعوات المرسلة المعلقة':'Pending sent invitations',
            style:Theme.of(context).textTheme.titleMedium),
          for(final inv in _sentInvitations)
            ListTile(
              title:Text(inv.username??inv.displayName??'Invitee'),
              subtitle:Text(inv.access),
              trailing:widget.repo.canRevokeSentInvitation
                ?IconButton(onPressed:_busy||!_current?null:
                  ()=>unawaited(_revoke(inv)),
                  tooltip:ar?'إلغاء الدعوة':'Revoke invitation',
                  icon:const Icon(Icons.cancel_outlined))
                :null,
            ),
          if(!_invitationsComplete)
            TextButton(onPressed:_busy?null:()=>unawaited(
              _load(moreInvitations:_invitationCursor!=null)),
              child:Text(ar?'عرض المزيد من الدعوات':'Load more invitations')),
        ],
        if(!_current)Text(ar?'تغيّر الحساب أو صلاحياته؛ أعد فتح صفحة الكيان بعد التحقق.'
          :'Managed entity context changed. Reopen with verified access.'),
      ])),
    );
  }
}

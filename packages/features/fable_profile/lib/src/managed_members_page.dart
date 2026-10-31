import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'package:fable_core/fable_core.dart';
import 'managed_accounts_repository.dart';

/// Lists only backend-authorized entity users. No membership is inferred from
/// a visible entity, and removal cannot target the immutable owner.
class FableManagedMembersPage extends StatefulWidget {
  const FableManagedMembersPage({super.key,required this.repo,
    required this.entity,required this.selection});
  final FableManagedAccountsRepository repo;
  final FableManagedAccount entity;
  final FableManagedAccountSelection selection;
  @override State<FableManagedMembersPage> createState()=>_FableManagedMembersPageState();
}
class _FableManagedMembersPageState extends State<FableManagedMembersPage>{
  final _members=<FableManagedMember>[];
  final _sentInvitations=<FableSentInvitation>[];
  String? _memberCursor,_invitationCursor,_error;
  bool _membersComplete=false,_invitationsComplete=false,_busy=false;
  StreamSubscription<FableIdentityEvent>? _identities;
  bool get _ar=>Localizations.localeOf(context).languageCode=='ar';
  bool get _current=>widget.selection.identityRevision==
    widget.repo.gateway.session.identityRevision;
  bool get _owner=>widget.entity.isOwner &&
    widget.selection.access=='OWNER';
  bool get _invitationAdmin=>widget.entity.collaborationEnabled &&
    (widget.selection.access=='OWNER'||
     widget.selection.access=='MANAGER'&&widget.entity.managersCanInvite);
  @override void initState(){
    super.initState();
    _identities=widget.repo.gateway.session.identityEvents.listen((_){
      if(!mounted)return;
      setState((){
        _members.clear();_sentInvitations.clear();
        _membersComplete=true;_invitationsComplete=true;_busy=false;
        _error='Login changed. This entity context is no longer valid.';
      });
    });
    WidgetsBinding.instance.addPostFrameCallback((_){
      if(mounted)unawaited(_load());
    });
  }
  Future<void> _load({bool moreMembers=false,bool moreInvitations=false})async{
    if(_busy||!_current)return;
    final loadMembers=_owner&&widget.repo.canListMembers &&
      (moreMembers||(!moreInvitations&&!_membersComplete));
    final loadInvitations=_invitationAdmin&&widget.repo.canViewSentInvitations &&
      (moreInvitations||(!moreMembers&&!_invitationsComplete));
    if(!loadMembers&&!loadInvitations)return;
    final revision=widget.selection.identityRevision;
    setState((){_busy=true;_error=null;});
    try{
      if(loadMembers){
        final page=await widget.repo.members(widget.entity,widget.selection,
          after:moreMembers?_memberCursor:null);
        if(!mounted||!_current)return;
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
        if(!mounted||!_current)return;
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
    }catch(_){
      if(mounted&&_current&&revision==widget.repo.gateway.session.identityRevision)
        setState(()=>_error=_ar?'تعذّر تحميل بيانات الإدارة الموثّقة من الخادم.'
          :'Backend refused or returned an invalid member/admin page.');
    }finally{
      if(mounted&&_current&&revision==widget.repo.gateway.session.identityRevision)
        setState(()=>_busy=false);
    }
  }
  Future<void> _reload() async{
    if(!_current||_busy)return;
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
    if(!await _confirm(_ar?'إزالة هذا العضو؟':'Remove this member?')||!mounted)return;
    final rev=widget.selection.identityRevision;
    setState((){_busy=true;_error=null;});
    try{
      await widget.repo.removeMember(widget.entity,widget.selection,member);
      if(mounted&&_current&&rev==widget.repo.gateway.session.identityRevision){
        setState((){
          _members.removeWhere((item)=>item.userId==member.userId);
          _memberCursor=null;_membersComplete=false;
        });
      }
    }catch(_){
      if(mounted&&_current&&rev==widget.repo.gateway.session.identityRevision)
        setState(()=>_error='Backend rejected this removal.');
    }finally{if(mounted&&_current&&rev==widget.repo.gateway.session.identityRevision)
      setState(()=>_busy=false);}
  }
  Future<void> _revoke(FableSentInvitation invitation)async{
    if(!_current||_busy||!_invitationAdmin||
      !widget.repo.canRevokeSentInvitation)return;
    if(!await _confirm(_ar?'إلغاء هذه الدعوة؟':'Revoke this invitation?')||!mounted)return;
    final rev=widget.selection.identityRevision;
    setState((){_busy=true;_error=null;});
    try{
      await widget.repo.revokeSentInvitation(widget.entity,widget.selection,invitation);
      if(mounted&&_current&&rev==widget.repo.gateway.session.identityRevision){
        setState((){
          _sentInvitations.removeWhere((item)=>item.id==invitation.id);
          _invitationCursor=null;_invitationsComplete=false;
        });
      }
    }catch(_){
      if(mounted&&_current&&rev==widget.repo.gateway.session.identityRevision)
        setState(()=>_error='Backend rejected invitation revocation.');
    }finally{if(mounted&&_current&&rev==widget.repo.gateway.session.identityRevision)
      setState(()=>_busy=false);}
  }
  @override void dispose(){unawaited(_identities?.cancel());super.dispose();}
  @override Widget build(BuildContext context){
    final ar=_ar;
    return Scaffold(appBar:AppBar(title:Text(ar?'أعضاء الكيان ودعواته':'Members and invitations')),
      body:SafeArea(child:ListView(padding:const EdgeInsets.all(16),children:[
        Text(ar?widget.entity.nameAr:widget.entity.nameEn,
          style:Theme.of(context).textTheme.titleLarge),
        if(_busy)const LinearProgressIndicator(),
        if(_error!=null)Padding(padding:const EdgeInsets.all(8),child:Text(_error!)),
        if(_current)OutlinedButton.icon(onPressed:_busy?null:()=>unawaited(_reload()),
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
        if(!_current)Text(ar?'تغيرت هوية المستخدم؛ أعد فتح صفحة الكيان.'
          :'Login identity changed. Reopen this entity with a verified session.'),
      ])),
    );
  }
}

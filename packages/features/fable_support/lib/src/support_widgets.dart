import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'support_repository.dart';

/// Read-only support tickets. This is a personal, authenticated list.
/// Legacy call sites still compile, but fail closed until a verified session
/// provider and its invalidation stream are supplied. Never infer user
/// ownership from the mere existence of a repository.
class FableSupportTicketList extends StatefulWidget {
  const FableSupportTicketList({super.key,required this.repository,
    this.identityRevision,this.isAuthenticated,this.identityInvalidations});
  final FableSupportRepository repository;
  final int Function()? identityRevision;
  final bool Function()? isAuthenticated;
  final Stream<void>? identityInvalidations;
  @override State<FableSupportTicketList> createState()=>_FableSupportTicketListState();
}

class _FableSupportTicketListState extends State<FableSupportTicketList> {
  Future<List<FableSupportTicket>>? _load;
  StreamSubscription<void>? _identityChanges;
  int? _loadIdentity;
  int _generation=0;

  @override void initState(){super.initState();_bind();}
  void _bind(){
    _identityChanges=widget.identityInvalidations?.listen((_){
      if(!mounted)return;
      setState(_restart);
    });
    _restart();
  }
  int? _verifiedRevision(){
    final revision=widget.identityRevision;
    final authenticated=widget.isAuthenticated;
    if(revision==null||authenticated==null||
       widget.identityInvalidations==null)return null;
    try{
      if(!authenticated())return null;
      final value=revision();
      return value>=0?value:null;
    }catch(_){
      // A host-supplied session callback is not a source of authorization.
      // Never issue a personal GET while its state is unknown.
      return null;
    }
  }
  void _restart(){
    _generation++;
    _load=null;
    _loadIdentity=null;
    final revision=_verifiedRevision();
    if(revision==null)return;
    _loadIdentity=revision;
    _load=widget.repository.list();
  }
  // RC317: the FutureBuilder must recheck identity immediately before
  // displaying ticket content, even if the invalidation event is delayed.
  bool _sameVerifiedIdentity()=>_loadIdentity!=null&&
      _verifiedRevision()==_loadIdentity;

  void _manualRefresh(){
    // Only the currently bound authenticated session can start another GET.
    // Never refresh an old list under another account after A -> B -> A.
    if(!mounted)return;
    if(!_sameVerifiedIdentity()){
      // A delayed identity event must not leave stale tickets visible after
      // a user interaction; drop the old snapshot without another request.
      setState((){
        _generation++;
        _load=null;
        _loadIdentity=null;
      });
      return;
    }
    setState(_restart);
  }

  @override void didUpdateWidget(covariant FableSupportTicketList old){
    super.didUpdateWidget(old);
    if(!identical(old.repository,widget.repository)||
       old.identityRevision!=widget.identityRevision||
       old.isAuthenticated!=widget.isAuthenticated||
       !identical(old.identityInvalidations,widget.identityInvalidations)){
      unawaited(_identityChanges?.cancel());
      _identityChanges=null;
      _bind();
    }
  }
  @override void dispose(){
    _generation++;
    unawaited(_identityChanges?.cancel());
    super.dispose();
  }

  @override Widget build(BuildContext context){
    final revision=widget.identityRevision;
    final authenticated=widget.isAuthenticated;
    if(revision==null||authenticated==null||widget.identityInvalidations==null){
      return const Text('Connect an authenticated session to view support tickets.');
    }
    final verified=_verifiedRevision();
    if(verified==null){
      return const Text('Sign in or verify your session to view support tickets.');
    }
    // Hide every old-account ticket even if the host has not yet published
    // an identity invalidation event. A rebuilt widget must never reuse data.
    if(_loadIdentity!=verified){
      return const Text('Session changed. Reopen support tickets to verify.');
    }
    final active=_load;
    if(active==null)return const Text('Support tickets are not available.');
    return FutureBuilder<List<FableSupportTicket>>(
      key:ValueKey<int>(_generation),
      future:active,
      builder:(context,snapshot){
        final arabic=Localizations.localeOf(context).languageCode=='ar';
        if(!_sameVerifiedIdentity()){
          return const Text('Session changed. Reopen support tickets to verify.');
        }
        if(snapshot.connectionState!=ConnectionState.done){
          return const Center(child:CircularProgressIndicator());
        }
        if(snapshot.hasError){
          return Column(mainAxisSize:MainAxisSize.min,children:[
            Text(arabic?'تعذّر تحميل التذاكر. حاول مجددًا.':
              'Support unavailable. Please try again.'),
            TextButton(onPressed:_manualRefresh,
              child:Text(arabic?'إعادة المحاولة':'Try again')),
          ]);
        }
        return Column(mainAxisSize:MainAxisSize.min,children:[
          for(final ticket in (snapshot.data??const <FableSupportTicket>[]).take(50))
            ListTile(title:Text(ticket.subject),subtitle:Text(ticket.status)),
          TextButton(onPressed:_manualRefresh,
            child:Text(arabic?'تحديث':'Refresh')),
        ]);
      },
    );
  }
}

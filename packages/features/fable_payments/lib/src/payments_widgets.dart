import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'payments_repository.dart';

/// RC316: read-only payment status with host-verified identity epoch.
/// Legacy callers without the three session providers fail closed (no HTTP).
class FablePaymentStatusCard extends StatefulWidget {
  const FablePaymentStatusCard({
    super.key, required this.repository, required this.paymentId,
    this.identityRevision, this.isAuthenticated, this.identityInvalidations,
  });
  final FablePaymentReadRepository repository;
  final String paymentId;
  // Revision MUST be monotonic for sign-in, sign-out and A -> B -> A.
  final int Function()? identityRevision;
  final bool Function()? isAuthenticated;
  final Stream<void>? identityInvalidations;
  @override
  State<FablePaymentStatusCard> createState()=>_FablePaymentStatusCardState();
}

class _FablePaymentStatusCardState extends State<FablePaymentStatusCard> {
  StreamSubscription<void>? _subscription;
  Future<FablePaymentSnapshot>? _load;
  int? _readRevision;
  int _generation=0;
  bool _needsReopen=false;

  @override void initState(){
    super.initState();
    _bindIdentity();
    _beginRead();
  }
  void _bindIdentity(){
    _subscription=widget.identityInvalidations?.listen((_){
      if(!mounted)return;
      setState((){
        _generation++;
        _load=null;
        _readRevision=null;
        // Never auto-refetch the previous payment ID in a new account.
        _needsReopen=true;
      });
    });
  }
  int? _verifiedRevision(){
    final revision=widget.identityRevision;
    final isAuthenticated=widget.isAuthenticated;
    if(revision==null||isAuthenticated==null||
        widget.identityInvalidations==null)return null;
    try{
      if(!isAuthenticated())return null;
      final current=revision();
      return current>=0?current:null;
    }catch(_){return null;}
  }
  bool _current(int generation,int revision)=>
      mounted && !_needsReopen && _generation==generation &&
      _readRevision==revision && _verifiedRevision()==revision;

  Future<FablePaymentSnapshot> _readChecked(
    FablePaymentReadRepository repository,String id,int generation,int revision,
  )async{
    if(!_current(generation,revision)){
      throw StateError('Payment session changed before request');
    }
    final payment=await repository.read(id);
    if(!_current(generation,revision)){
      throw StateError('Payment session changed during request');
    }
    return payment;
  }

  void _beginRead(){
    _generation++;
    _readRevision=null;
    _load=null;
    final revision=_verifiedRevision();
    if(_needsReopen||revision==null)return;
    _readRevision=revision;
    _load=_readChecked(widget.repository,widget.paymentId,_generation,revision);
  }
  @override void didUpdateWidget(covariant FablePaymentStatusCard old){
    super.didUpdateWidget(old);
    final identityChanged=old.identityRevision!=widget.identityRevision||
        old.isAuthenticated!=widget.isAuthenticated||
        !identical(old.identityInvalidations,widget.identityInvalidations);
    final repositoryChanged=!identical(old.repository,widget.repository);
    if(identityChanged){
      unawaited(_subscription?.cancel());
      _subscription=null;
      _bindIdentity();
    }
    if(identityChanged||repositoryChanged){
      // A replacement Backend may use a different ID namespace. Never send
      // the old payment ID to the new repository automatically or reveal a
      // completion from the previous repository, even at the same revision.
      _generation++;
      _load=null;
      _readRevision=null;
      _needsReopen=true;
    }
    if(old.paymentId!=widget.paymentId){
      // Only an explicitly selected new ID can begin a new verified read.
      _needsReopen=false;
      _beginRead();
    }
  }
  @override void dispose(){
    _generation++;
    _load=null;
    _readRevision=null;
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  @override Widget build(BuildContext context){
    final revision=_verifiedRevision();
    if(widget.identityRevision==null||widget.isAuthenticated==null||
       widget.identityInvalidations==null){
      return const Text('A verified payment session is required.');
    }
    if(revision==null)return const Text('Sign in to view payment status.');
    if(_needsReopen||revision!=_readRevision){
      return const Text('Session changed. Reopen payment status to verify.');
    }
    final active=_load;
    if(active==null)return const Text('Payment status unavailable.');
    final generation=_generation;
    return FutureBuilder<FablePaymentSnapshot>(
      key:ValueKey<int>(generation),future:active,
      builder:(context,snapshot){
        // Recheck at display time even if a session notification is delayed.
        if(!_current(generation,revision)){
          return const Text('Session changed. Reopen payment status to verify.');
        }
        if(snapshot.connectionState!=ConnectionState.done){
          return const LinearProgressIndicator();
        }
        if(snapshot.hasError)return const Text('Payment status unavailable.');
        final payment=snapshot.data;
        if(payment==null||
           payment.id.toLowerCase()!=widget.paymentId.toLowerCase()){
          return const Text('Payment status unavailable.');
        }
        return ListTile(
          title:const Text('Payment status'),subtitle:Text(payment.status),
        );
      },
    );
  }
}

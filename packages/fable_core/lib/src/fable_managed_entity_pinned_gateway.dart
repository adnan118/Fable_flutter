import 'dart:async';

import 'package:dio/dio.dart';

import 'fable_auth_gateway.dart';
import 'fable_api.dart';
import 'fable_contract.dart';
import 'fable_dpop_proof_signer.dart';
import 'fable_managed_entity_scope.dart';
import 'fable_session.dart';

/// RC299: a project-pinned managed-entity gateway. No entity header is ever
/// inferred from the global app or attached to unrelated operations.
/// Authorization is still verified by the Backend for every request.
class FableManagedEntityPinnedGateway extends FableAuthGateway {
  FableManagedEntityPinnedGateway({
    required Uri baseUri,
    required FableContract contract,
    required this.store,
    required Map<String,String> approvedOperationHashes,
    FableSecureSession? secureSession,
    FableDpopProofSigner? dpopProofSigner,
    Dio? client,
    bool allowHttpForLocalDevelopment=false,
  }) : _approved=Map<String,String>.unmodifiable(approvedOperationHashes),
    super(baseUri:baseUri,contract:contract,
      secureSession:secureSession,dpopProofSigner:dpopProofSigner,client:client,
      allowHttpForLocalDevelopment:allowHttpForLocalDevelopment) {
    if(_approved.isEmpty||_approved.length>40||
       !store.isBoundToCredentials(session)||
       !store.isBoundToBackend(managedEntityBackendIdentity)){
      throw StateError('Managed entity gateway must use a bound verified Fable project and identity');
    }
    for(final item in _approved.entries){
      final op=verifiedContract.operations[item.key];
      if(op==null||op.contractHash!=item.value||
         !RegExp(r'^[a-f0-9]{64}$').hasMatch(item.value)||
         !const {'GET','POST','PATCH','DELETE'}.contains(op.method)||
         op.recordAccess==null||
         !RegExp(r'^managed-entity:[A-Za-z][A-Za-z0-9_]*$').hasMatch(op.recordAccess!)||
         !(op.method=='GET'?
           ((item.key.endsWith('.get')&&op.path=='/'+item.key.split('.').first+'/{id}')||
            (item.key.endsWith('.list.paginated')&&op.path=='/'+item.key.split('.').first)):
           (op.method=='POST'
             ?(!op.requiresIfMatch&&item.key.endsWith('.create')&&
               op.path=='/'+item.key.split('.').first)
             :(op.requiresIfMatch&&
               item.key.endsWith(op.method=='PATCH'?'.update':'.delete')&&
               op.path=='/'+item.key.split('.').first+'/{id}')))||
         !op.requiresAuth||!op.enforceAuth||op.credentialHeader!=null||
         !op.path.startsWith('/')||op.path.startsWith('/auth/')||
         op.path.contains('..')||op.path.contains('?')){
        throw StateError('Managed operation must be explicitly signed and authenticated: ${item.key}');
      }
    }
    for(final item in _approved.entries){
      final op=verifiedContract.operations[item.key]!;
      if(const {'GET','POST'}.contains(op.method))continue;
      final feature=item.key.split('.').first;
      final read=verifiedContract.operations['$feature.get'];
      if(read==null||read.method!='GET'||
         read.path!='/'+feature+'/{id}'||
         read.recordAccess!=op.recordAccess||
         _approved[read.id]!=read.contractHash ||
         read.contractHash.isEmpty){
        throw StateError('Managed conditional write requires an approved, identically scoped signed GET');
      }
    }
    store.addListener(_notifyScopeChange);
  }

  final FableManagedEntityStore store;
  final Map<String,String> _approved;
  final StreamController<Object?> _scopeEvents=StreamController<Object?>.broadcast(sync:true);
  bool _disposed=false;

  /// Pass these events (combined with auth identity events if needed) to
  /// generated UI pages so old selected-entity rows are cleared on A->B->A.
  Stream<Object?> get scopeEvents=>_scopeEvents.stream;
  void _notifyScopeChange(){
    if(!_disposed)_scopeEvents.add(store.selectionRevision);
  }

  bool _bound() =>
    !_disposed&&store.isBoundToCredentials(session)&&
    store.isBoundToBackend(managedEntityBackendIdentity);

  @override
  Future<Response<dynamic>> execute(String operationId,{
    Map<String,dynamic>? path,Map<String,dynamic>? query,Object? body,
    CancelToken? cancelToken,String? ifMatch,
  }) {
    if(!_bound())throw FableApiException(403,'managed_context_backend_or_identity_changed');
    final entry=verifiedContract.operations[operationId];
    if(entry==null||_approved[operationId]!=entry.contractHash)
      throw FableApiException(403,'managed_operation_not_signed_for_context');
    final selected=store.selected;
    if(selected==null)throw FableApiException(403,'managed_entity_selection_required');
    final readOnly=entry.method=='GET';
    if(readOnly){
      if(body!=null||ifMatch!=null)
        throw FableApiException(400,'managed_get_cannot_mutate');
    }else{
      if(entry.method=='POST'){
        if(entry.requiresIfMatch||path!=null||query!=null||ifMatch!=null||
           body is! Map||body.isEmpty||
           body.keys.any((key)=>key is! String))
          throw FableApiException(400,'managed_create_payload_invalid');
      }else if(!entry.requiresIfMatch||
         !const {'PATCH','DELETE'}.contains(entry.method)){
        throw FableApiException(403,'managed_write_not_signed');
      }
      if(!const {'OWNER','MANAGER'}.contains(selected.access))
        throw FableApiException(403,'managed_mutation_access_denied');
      final id=path?['id'];
      if(entry.method!='POST' && (id is! String||path!.length!=1||
         !RegExp(r'^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$',
           caseSensitive:false).hasMatch(id)||
         query!=null||
         ifMatch==null||!RegExp(r'^[a-f0-9]{64}$').hasMatch(ifMatch)||
         (entry.method=='DELETE'&&body!=null)||
         (entry.method=='PATCH'&&(body is! Map||body.isEmpty)))){
        throw FableApiException(400,'managed_mutation_input_or_revision_invalid');
      }
    }
    final revision=store.selectionRevision;
    final account=session.identityRevision;
    bool valid()=>
      _bound()&&store.selectionRevision==revision&&
      session.identityRevision==account&&store.selected?.id==selected.id&&
      store.selected?.access==selected.access;
    if(!valid())throw FableApiException(409,'managed_entity_context_changed_discard_response');
    return super.executeInManagedEntity(operationId,selected.id,
      path:path,query:query,body:body,cancelToken:cancelToken,ifMatch:ifMatch,
      contextStillValid:valid);
  }

  @override
  void dispose(){
    if(_disposed)return;
    _disposed=true;
    store.removeListener(_notifyScopeChange);
    unawaited(_scopeEvents.close());
    super.dispose();
  }
}

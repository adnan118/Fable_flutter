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
         !op.requiresAuth||!op.enforceAuth||op.credentialHeader!=null||
         !op.path.startsWith('/')||op.path.startsWith('/auth/')||
         op.path.contains('..')||op.path.contains('?')){
        throw StateError('Managed operation must be explicitly signed and authenticated: ${item.key}');
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
    if(!const {'GET','HEAD'}.contains(entry.method)&&
       !const {'OWNER','MANAGER'}.contains(selected.access))
      throw FableApiException(403,'managed_mutation_access_denied');
    if(const {'PATCH','DELETE'}.contains(entry.method)&&ifMatch==null)
      throw FableApiException(428,'managed_revision_precondition_required');
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

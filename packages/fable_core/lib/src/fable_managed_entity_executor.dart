import 'fable_api.dart';
import 'fable_auth_gateway.dart';
import 'fable_managed_entity_scope.dart';

/// Explicit Fable-only executor for generated managed-entity feature repositories.
///
/// Only call this for an operation whose imported Fable contract explicitly
/// supports entity scoping. It never injects the entity into global operations,
/// and must never be reused with Other Backend contracts.
class FableManagedEntityExecutor {
  const FableManagedEntityExecutor(this.gateway,this.store);
  final FableAuthGateway gateway;
  final FableManagedEntityStore store;

  Future<Object?> execute(String operationId,{
    Map<String,dynamic>? path,Map<String,dynamic>? query,Object? body,
  }) async {
    if(!store.isBoundToCredentials(gateway.session)||
       !store.isBoundToBackend(gateway.managedEntityBackendIdentity)){
      throw StateError('Selected managed store belongs to another session or Backend');
    }
    final selection=store.selected;
    if(selection==null){
      throw StateError('Select a Backend-confirmed managed entity first');
    }
    final revision=store.selectionRevision;
    final identity= gateway.session.identityRevision;
    bool valid()=>store.isBoundToCredentials(gateway.session)&&
      store.isBoundToBackend(gateway.managedEntityBackendIdentity)&&
      gateway.session.identityRevision==identity&&
      store.selectionRevision==revision&&
      identical(store.selected,selection);

    Object? response;
    try {
      response=(await gateway.executeInManagedEntity(
        operationId,selection.id,path:path,query:query,body:body,
        contextStillValid:valid)).data;
    } on FableApiException catch(error){
      // رفض الحساب A المتأخر لا يمسح اختيار الحساب B، حتى في A→B→A.
      if(!valid()){
        throw FableApiException(409,
          'managed_entity_context_changed_discard_response');
      }
      if(error.status==403||error.code=='MANAGED_ACCOUNT_NOT_FOUND'){
        store.clear();
      }
      rethrow;
    }
    if(!valid()){
      throw FableApiException(409,
        'managed_entity_context_changed_discard_response');
    }
    return response;
  }
}

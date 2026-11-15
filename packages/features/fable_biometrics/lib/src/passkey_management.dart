import 'package:fable_core/fable_core.dart';

/// Credential management belongs to the selected Fable backend and never to
/// a guessed Other Backend route. Passkey material itself stays native.
class FablePasskeyManagementOperations {
  const FablePasskeyManagementOperations._(this.removeId,this.listId);
  final String removeId;
  final String? listId;

  factory FablePasskeyManagementOperations.fromFable(FableContract catalog,
      {String? listOperationId}) {
    const removeId='passkeys.remove';
    final remove=catalog.require(removeId);
    if(remove.method!='DELETE'||
        !const <String>{'/auth/passkeys/:id','/auth/passkeys/{id}'}
          .contains(remove.path) ||
        !remove.requiresAuth||!remove.enforceAuth||
        remove.credentialHeader!=null||remove.contractHash.isEmpty) {
      throw const FormatException('Verified protected Fable passkey remove operation required');
    }
    if(listOperationId!=null){
      final list=catalog.require(listOperationId);
      if(list.method!='GET'||list.path!='/auth/passkeys'||
          !list.requiresAuth||!list.enforceAuth||
          list.credentialHeader!=null||list.contractHash.isEmpty) {
        throw const FormatException('Verified protected Fable passkey list operation required');
      }
    }
    return FablePasskeyManagementOperations._(removeId,listOperationId);
  }
}

class FablePasskeyCredentialInfo {
  const FablePasskeyCredentialInfo({required this.id,required this.backedUp,
    this.label,this.deviceType,this.createdAt,this.lastUsedAt});
  final String id;
  final String? label,deviceType,createdAt,lastUsedAt;
  final bool backedUp;
}

/// The caller must supply its actual backend's recent-auth proof UUID.
/// The server checks user ownership, proof validity and last-login-method safety.
class FablePasskeyManagementRepository {
  FablePasskeyManagementRepository._(this.client,this.operations);
  final UnifiedApiClient client;
  final FablePasskeyManagementOperations operations;
  static final _uuid=RegExp(
    r'^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$',
    caseSensitive:false);
  bool _removing=false;

  factory FablePasskeyManagementRepository.forFable(UnifiedApiClient client,
      {String? listOperationId}) {
    final catalog=client.contract;
    if(catalog is! FableContract||client.adapter is! FableTransportAdapter){
      throw ArgumentError('Passkey management requires a verified Fable transport');
    }
    return FablePasskeyManagementRepository._(client,
      FablePasskeyManagementOperations.fromFable(catalog,
        listOperationId:listOperationId));
  }

  Future<int> _signedInEpoch() async {
    final identity=client.session.identityRevision;
    final token=await client.session.accessToken;
    if(token==null||token.isEmpty||client.session.identityRevision!=identity){
      throw StateError('Authenticated user session required');
    }
    return identity;
  }

  /// This route is not present in every generated project manifest.
  /// Only an explicitly exported matching GET can be used to list credentials.
  Future<List<FablePasskeyCredentialInfo>> list() async {
    final op=operations.listId;
    if(op==null)throw StateError('Passkey list operation is not exported');
    final identity=await _signedInEpoch();
    final reply=await client.request(op);
    if(client.session.identityRevision!=identity)return const [];
    final raw=reply.data;
    if(raw is! List||raw.length>256){
      throw const FormatException('Invalid passkey list response');
    }
    final output=<FablePasskeyCredentialInfo>[],seen=<String>{};
    String? limited(dynamic value,{int max=191}){
      if(value==null)return null;
      if(value is! String||value.length>max||
          value.contains(RegExp(r'[\x00-\x1f\x7f]'))){
        throw const FormatException('Invalid passkey credential detail');
      }
      return value;
    }
    for(final row in raw){
      if(row is! Map || row['id'] is! String||
          !_uuid.hasMatch(row['id'] as String)||
          !seen.add(row['id'] as String)||
          row['backedUp'] is! bool){
        throw const FormatException('Invalid passkey credential');
      }
      output.add(FablePasskeyCredentialInfo(
        id:row['id'] as String, backedUp:row['backedUp'] as bool,
        label:limited(row['label']),deviceType:limited(row['deviceType'],max:64),
        createdAt:limited(row['createdAt'],max:64),
        lastUsedAt:limited(row['lastUsedAt'],max:64)));
    }
    return List<FablePasskeyCredentialInfo>.unmodifiable(output);
  }

  Future<bool> remove({required String credentialId,
      required String securityChallengeId}) async {
    if(!_uuid.hasMatch(credentialId)||!_uuid.hasMatch(securityChallengeId)){
      throw ArgumentError('Verified UUID credential and recent-auth proof required');
    }
    if(_removing)throw StateError('Passkey removal already in progress');
    _removing=true;
    try {
      final identity=await _signedInEpoch();
      final reply=await client.request(operations.removeId,
        path:{'id':credentialId},securityChallengeId:securityChallengeId);
      if(client.session.identityRevision!=identity)return false;
      final data=FableImmutablePayload.object(reply.data);
      if(data['count'] is! int||!(data['count']==0||data['count']==1)){
        throw const FormatException('Invalid passkey removal confirmation');
      }
      return data['count']==1;
    }finally{_removing=false;}
  }
}

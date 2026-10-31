import 'package:fable_core/fable_core.dart';

/// Optional Fable Managed Accounts capability. The mere presence of a
/// Blueprint or a profile tile never authorizes these operations.
class FableManagedAccount {
  const FableManagedAccount({
    required this.id,required this.type,required this.nameAr,
    required this.nameEn,required this.status,required this.visibility,
    required this.collaborationEnabled,required this.managersCanInvite,
    this.isOwner=false,this.slug,
  });
  final String id,type,nameAr,nameEn,status,visibility;
  final String? slug;
  final bool collaborationEnabled,managersCanInvite;
  final bool isOwner;

  static final _uuid=RegExp(
    r'^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$',
    caseSensitive:false);
  factory FableManagedAccount.fromPayload(Object? raw){
    if(raw is! Map)throw const FormatException('Managed entity is not an object');
    String field(String k,{int max=191}){
      final v=raw[k];
      if(v is! String||v.trim().isEmpty||v.length>max||
        RegExp(r'[\x00-\x1f\x7f<>]').hasMatch(v))
        throw FormatException('Invalid managed entity field: $k');
      return v;
    }
    final id=field('id',max:36);
    if(!_uuid.hasMatch(id))throw const FormatException('Invalid managed entity UUID');
    final status=field('status',max:32),visibility=field('visibility',max:32);
    if(!const {'ACTIVE','DISABLED','PENDING_DELETE'}.contains(status)||
      !const {'PUBLIC','PRIVATE','INVITE_ONLY'}.contains(visibility))
      throw const FormatException('Invalid managed entity status or visibility');
    if(raw['collaborationEnabled'] is! bool||raw['managersCanInvite'] is! bool)
      throw const FormatException('Invalid managed entity collaboration settings');
    // listMine only returns the requester's memberships. Never infer OWNER
    // from a visible entity or from the owner's public identifier.
    final memberships=raw['memberships'];
    final isOwner=memberships is List &&
      memberships.length<=100 &&
      memberships.any((membership)=>membership is Map &&
        membership['access']=='OWNER' && membership['active']==true);
    final rawSlug=raw['slug'];
    if(rawSlug!=null&&(rawSlug is! String||
       !RegExp(r'^[a-z0-9][a-z0-9-]{1,189}[a-z0-9]$').hasMatch(rawSlug)))
      throw const FormatException('Invalid managed entity slug');
    return FableManagedAccount(id:id,type:field('type',max:64),
      nameAr:field('nameAr'),nameEn:field('nameEn'),
      status:status,visibility:visibility,
      collaborationEnabled:raw['collaborationEnabled'] as bool,
      managersCanInvite:raw['managersCanInvite'] as bool,isOwner:isOwner,
      slug:rawSlug as String?);
  }
}

/// Volatile selection, validated against the activation response.
/// Backend remains the final authority for every subsequent scoped request.
class FableManagedAccountSelection {
  const FableManagedAccountSelection({
    required this.id,required this.access,required this.nameAr,
    required this.nameEn,required this.identityRevision,
  });
  final String id,access,nameAr,nameEn;
  final int identityRevision;
}

class FableManagedInvitation {
  const FableManagedInvitation({
    required this.id,required this.entityId,required this.entityName,
    required this.access,required this.expiresAt});
  final String id,entityId,entityName,access;
  final DateTime expiresAt;
  factory FableManagedInvitation.fromPayload(Object? raw){
    if(raw is! Map)throw const FormatException('Invalid managed invitation');
    final id=raw['id'],access=raw['access'],expiry=raw['expiresAt'],
      managed=raw['managedAccount'];
    if(id is! String||!FableManagedAccount._uuid.hasMatch(id)||
       access is! String||!const {'MANAGER','VIEWER'}.contains(access)||
       expiry is! String||managed is! Map)
      throw const FormatException('Invalid invitation identity');
    final managedId=managed['id'],name=managed['nameAr'];
    if(managedId is! String||!FableManagedAccount._uuid.hasMatch(managedId)||
       name is! String||name.length>191||name.isEmpty)
      throw const FormatException('Invalid invited entity');
    final parsed=DateTime.tryParse(expiry);
    if(parsed==null)throw const FormatException('Invalid invitation expiry');
    return FableManagedInvitation(id:id,entityId:managedId,entityName:name,
      access:access,expiresAt:parsed.toUtc());
  }
}

/// In-memory OTP proof request. Never persist this challenge, its code or the
/// authenticated identity it belongs to.
class FableManagedLifecycleChallenge {
  const FableManagedLifecycleChallenge._(this.challengeId,this.purpose,
    this.entityId,this.operation,this.identityRevision);
  final String challengeId,purpose,entityId,operation;
  final int identityRevision;
}

class FableManagedMember {
  const FableManagedMember({required this.userId,required this.access,
    required this.isOwner,this.username,this.displayName,this.joinedAt});
  final String userId,access;
  final bool isOwner;
  final String? username,displayName;
  final DateTime? joinedAt;
  factory FableManagedMember.fromPayload(Object? raw){
    if(raw is! Map)throw const FormatException('Invalid member');
    final userId=raw['userId'],access=raw['access'],owner=raw['isOwner'];
    if(userId is! String||!FableManagedAccount._uuid.hasMatch(userId)||
      access is! String||!const {'OWNER','MANAGER','VIEWER'}.contains(access)||
      owner is! bool || (owner!=(access=='OWNER')))
      throw const FormatException('Invalid managed membership or owner status');
    String? field(String key){
      final v=raw[key];
      if(v==null)return null;
      if(v is! String||v.length>191||RegExp(r'[\x00-\x1f\x7f<>]').hasMatch(v))
        throw FormatException('Invalid member presentation: $key');
      return v;
    }
    final joined=raw['joinedAt'];
    if(joined!=null && (joined is! String||DateTime.tryParse(joined)==null))
      throw const FormatException('Invalid member creation date');
    return FableManagedMember(userId:userId,access:access,isOwner:owner,
      username:field('username'),displayName:field('displayName'),
      joinedAt:joined is String?DateTime.parse(joined).toUtc():null);
  }
}

class FableSentInvitation {
  const FableSentInvitation({required this.id,required this.access,
    required this.expiresAt,this.username,this.displayName});
  final String id,access;
  final DateTime expiresAt;
  final String? username,displayName;
  factory FableSentInvitation.fromPayload(Object? raw){
    if(raw is! Map)throw const FormatException('Invalid sent invitation');
    final id=raw['id'],access=raw['access'],expiresAt=raw['expiresAt'];
    if(id is! String||!FableManagedAccount._uuid.hasMatch(id)||
      access is! String||!const {'MANAGER','VIEWER'}.contains(access)||
      expiresAt is! String||DateTime.tryParse(expiresAt)==null)
      throw const FormatException('Invalid sent invitation');
    String? safe(Object? input){
      if(input==null)return null;
      if(input is! String||input.length>191||
        RegExp(r'[\x00-\x1f\x7f<>]').hasMatch(input))
        throw const FormatException('Invalid invitation recipient');
      return input;
    }
    return FableSentInvitation(id:id,access:access,
      expiresAt:DateTime.parse(expiresAt).toUtc(),
      username:safe(raw['username']),displayName:safe(raw['displayName']));
  }
}

class FableCursorPage<T> {
  const FableCursorPage(this.items,this.nextCursor);
  final List<T> items;
  final String? nextCursor;
}

class FableManagedAccountsRepository {
  const FableManagedAccountsRepository(this.gateway,this.contract);
  final FableAuthGateway gateway;
  final FableContract contract;

  String _operation(String path,String method){
    final choices=contract.operations.values.where((o)=>o.path==path &&
      o.method==method && o.requiresAuth && o.credentialHeader==null).toList();
    if(choices.length!=1)throw StateError(
      'Managed Accounts operation not exported by this Fable project: $method $path');
    return choices.single.id;
  }
  bool can(String path,String method){
    try {_operation(path,method);return true;}catch(_){return false;}
  }
  bool get canList=>can('/managed-entities','GET');
  bool get canActivate=>can('/managed-entities/{id}/activate','POST');
  bool get canCreate=>can('/managed-entities','POST');
  bool get canInvite=>can('/managed-entities/{id}/invitations','POST');
  bool get canReadInvitations=>can('/managed-entities/invitations/me','GET');

  static Object? _unwrap(Object? raw){
    if(raw is Map && raw.containsKey('data'))return raw['data'];
    return raw;
  }
  static List<Object?> _array(Object? raw){
    final a=_unwrap(raw);
    if(a is! List||a.length>10000)throw const FormatException('Invalid managed entities collection');
    return a.cast<Object?>();
  }
  Future<List<FableManagedAccount>> listMine() async {
    final rev=gateway.session.identityRevision;
    final response=await gateway.execute(_operation('/managed-entities','GET'));
    if(rev!=gateway.session.identityRevision)
      throw FableApiException(409,'session_changed_discard_response');
    return List.unmodifiable(_array(response.data).map(FableManagedAccount.fromPayload));
  }

  Future<FableManagedAccountSelection> activate(FableManagedAccount entity) async {
    if(entity.status!='ACTIVE')throw StateError('Only an active entity can be selected');
    final rev=gateway.session.identityRevision;
    final response=await gateway.execute(_operation('/managed-entities/{id}/activate','POST'),
      path:{'id':entity.id});
    if(rev!=gateway.session.identityRevision)
      throw FableApiException(409,'session_changed_discard_response');
    final payload=_unwrap(response.data);
    if(payload is! Map || payload['managedEntityId']!=entity.id||
      !const {'OWNER','MANAGER','VIEWER'}.contains(payload['access']) ||
      (payload['access']=='OWNER'&&!entity.isOwner) ||
      payload['header'] is! Map ||
      (payload['header'] as Map)['name']!='X-Fable-Managed-Entity-Id'||
      (payload['header'] as Map)['value']!=entity.id)
      throw const FormatException('Backend did not confirm a managed entity context');
    return FableManagedAccountSelection(id:entity.id,
      access:payload['access'] as String,nameAr:entity.nameAr,nameEn:entity.nameEn,
      identityRevision:rev);
  }

  Future<void> create({required String type,required String nameAr,
    required String nameEn,required String visibility}) async{
    final t=type.trim().toLowerCase(),ar=nameAr.trim(),en=nameEn.trim();
    if(!RegExp(r'^[a-z][a-z0-9_-]{1,63}$').hasMatch(t)||
      ar.isEmpty||en.isEmpty||ar.length>191||en.length>191||
      !const {'PUBLIC','PRIVATE','INVITE_ONLY'}.contains(visibility))
      throw ArgumentError('Invalid managed entity create data');
    await gateway.execute(_operation('/managed-entities','POST'),body:{
      'type':t,'nameAr':ar,'nameEn':en,'visibility':visibility,
    });
  }

  Future<List<FableManagedInvitation>> invitationsMine() async{
    final rev=gateway.session.identityRevision;
    final response=await gateway.execute(
      _operation('/managed-entities/invitations/me','GET'));
    if(gateway.session.identityRevision!=rev)
      throw FableApiException(409,'session_changed_discard_response');
    return List.unmodifiable(_array(response.data).map(FableManagedInvitation.fromPayload));
  }
  Future<void> respondToInvitation(String id,{required bool accept}) async{
    if(!FableManagedAccount._uuid.hasMatch(id))throw ArgumentError('Invalid invitation ID');
    final suffix=accept?'accept':'decline';
    await gateway.execute(_operation('/managed-entities/invitations/{invitationId}/$suffix','POST'),
      path:{'invitationId':id});
  }
  Future<void> invite(String entityId,{required String username,required String access}) async{
    if(!FableManagedAccount._uuid.hasMatch(entityId)||
      !RegExp(r'^[a-z0-9._]{3,30}$').hasMatch(username)||
      !const {'MANAGER','VIEWER'}.contains(access))
      throw ArgumentError('Invalid invitee or delegated access level');
    await gateway.execute(_operation('/managed-entities/{id}/invitations','POST'),
      path:{'id':entityId},body:{'username':username,'access':access});
  }

  bool get canReadDetails=>can('/managed-entities/{id}','GET');
  bool get canUpdateDetails=>can('/managed-entities/{id}','PATCH');

  Future<FableManagedAccount> readDetails(FableManagedAccount entity)async{
    if(entity.status!='ACTIVE'||!FableManagedAccount._uuid.hasMatch(entity.id))
      throw StateError('Managed entity cannot be read in this state');
    final revision=gateway.session.identityRevision;
    final response=await gateway.execute(
      _operation('/managed-entities/{id}','GET'),path:{'id':entity.id});
    if(revision!=gateway.session.identityRevision)
      throw FableApiException(409,'session_changed_discard_response');
    final details=FableManagedAccount.fromPayload(_unwrap(response.data));
    if(details.id!=entity.id||(entity.isOwner&&!details.isOwner))
      throw const FormatException('Backend returned a different entity or identity');
    return details;
  }

  /// Only patch changed values. Changing privacy/collaboration may remove
  /// existing members and outstanding invitations on the server.
  Future<void> updateDetails(FableManagedAccount entity,{
    required String nameAr,required String nameEn,required String visibility,
    required bool collaborationEnabled,required bool managersCanInvite,
    String? slug,
  })async{
    if(!entity.isOwner||!const {'ACTIVE','DISABLED'}.contains(entity.status)||
       !canUpdateDetails)throw StateError('Entity editing not authorized');
    final ar=nameAr.trim(),en=nameEn.trim(),newSlug=slug?.trim();
    if(ar.isEmpty||en.isEmpty||ar.length>191||en.length>191||
       RegExp(r'[\x00-\x1f\x7f<>]').hasMatch(ar)||
       RegExp(r'[\x00-\x1f\x7f<>]').hasMatch(en)||
       !const {'PUBLIC','PRIVATE','INVITE_ONLY'}.contains(visibility))
      throw ArgumentError('Invalid managed entity names or visibility');
    if(newSlug!=null&&newSlug.isNotEmpty&&
       !RegExp(r'^[a-z0-9][a-z0-9-]{1,189}[a-z0-9]$').hasMatch(newSlug))
      throw ArgumentError('Invalid managed entity slug');
    final collaboration=visibility=='PRIVATE'?false:collaborationEnabled;
    final delegation=collaboration?managersCanInvite:false;
    final body=<String,Object?>{};
    if(ar!=entity.nameAr)body['nameAr']=ar;
    if(en!=entity.nameEn)body['nameEn']=en;
    if(visibility!=entity.visibility)body['visibility']=visibility;
    if(collaboration!=entity.collaborationEnabled)body['collaborationEnabled']=collaboration;
    if(delegation!=entity.managersCanInvite)body['managersCanInvite']=delegation;
    if(newSlug!=null&&newSlug.isNotEmpty&&newSlug!=entity.slug)body['slug']=newSlug;
    if(body.isEmpty)throw StateError('No entity changes to submit');
    final revision=gateway.session.identityRevision;
    final response=await gateway.execute(
      _operation('/managed-entities/{id}','PATCH'),
      path:{'id':entity.id},body:body);
    if(revision!=gateway.session.identityRevision)
      throw FableApiException(409,'session_changed_discard_response');
    final result=_unwrap(response.data);
    if(result is! Map||result['id']!=entity.id||
       result['nameAr']!=ar||result['nameEn']!=en||
       result['visibility']!=visibility||
       result['collaborationEnabled']!=collaboration||
       result['managersCanInvite']!=delegation)
      throw const FormatException('Backend did not confirm managed entity changes');
  }

  bool get canListMembers=>can('/managed-entities/{id}/members','GET');
  bool get canRemoveMember=>can('/managed-entities/{id}/members/{userId}','DELETE');
  bool get canViewSentInvitations=>can('/managed-entities/{id}/invitations','GET');
  bool get canRevokeSentInvitation=>can('/managed-entities/{id}/invitations/{invitationId}','DELETE');

  void _requireSelection(FableManagedAccount entity,FableManagedAccountSelection selected,{
    bool ownerOnly=false,
  }){
    if(selected.id!=entity.id||
       selected.identityRevision!=gateway.session.identityRevision||
       (selected.access=='OWNER'&&!entity.isOwner) ||
       (ownerOnly && (!entity.isOwner||selected.access!='OWNER')))
      throw StateError('No verified identity, owner rights or active entity context');
    if(entity.status!='ACTIVE'&&entity.status!='DISABLED')
      throw StateError('Inactive entity does not permit membership administration');
  }

  FableCursorPage<T> _cursorPage<T>(Object? value,T Function(Object?) parse){
    final payload=_unwrap(value);
    if(payload is! Map||payload['items'] is! List)
      throw const FormatException('Invalid Backend cursor page');
    final rows=payload['items'] as List;
    if(rows.length>50)throw const FormatException('Backend exceeded membership page size');
    final next=payload['nextCursor'];
    if(next!=null&&(next is! String||!FableManagedAccount._uuid.hasMatch(next)))
      throw const FormatException('Invalid next page cursor');
    return FableCursorPage<T>(
      List<T>.unmodifiable(rows.map(parse)),next as String?);
  }

  Future<FableCursorPage<FableManagedMember>> members(
    FableManagedAccount entity,FableManagedAccountSelection selected,{String? after})async{
    _requireSelection(entity,selected,ownerOnly:true);
    if(after!=null&&!FableManagedAccount._uuid.hasMatch(after))
      throw ArgumentError('Invalid membership page cursor');
    final response=await gateway.execute(_operation('/managed-entities/{id}/members','GET'),
      path:{'id':entity.id},query:after==null?null:{'after':after});
    if(gateway.session.identityRevision!=selected.identityRevision)
      throw FableApiException(409,'session_changed_discard_response');
    return _cursorPage<FableManagedMember>(
      response.data,FableManagedMember.fromPayload);
  }

  Future<bool> removeMember(FableManagedAccount entity,FableManagedAccountSelection selected,
    FableManagedMember member)async{
    _requireSelection(entity,selected,ownerOnly:true);
    if(member.isOwner||member.access=='OWNER'||!FableManagedAccount._uuid.hasMatch(member.userId))
      throw StateError('Owner membership is immutable');
    final response=await gateway.execute(
      _operation('/managed-entities/{id}/members/{userId}','DELETE'),
      path:{'id':entity.id,'userId':member.userId});
    if(gateway.session.identityRevision!=selected.identityRevision)
      throw FableApiException(409,'session_changed_discard_response');
    final payload=_unwrap(response.data);
    if(payload is! Map||payload['removed']!=true)
      throw const FormatException('Backend did not confirm removal');
    return true;
  }

  Future<FableCursorPage<FableSentInvitation>> sentInvitations(
    FableManagedAccount entity,FableManagedAccountSelection selected,{String? after})async{
    _requireSelection(entity,selected);
    if(!entity.collaborationEnabled ||
       !(selected.access=='OWNER' ||
         selected.access=='MANAGER'&&entity.managersCanInvite))
      throw StateError('Only a verified authorized invitation admin may access sent invitations');
    if(after!=null&&!FableManagedAccount._uuid.hasMatch(after))
      throw ArgumentError('Invalid invitation cursor');
    final response=await gateway.execute(
      _operation('/managed-entities/{id}/invitations','GET'),
      path:{'id':entity.id},query:after==null?null:{'after':after});
    if(gateway.session.identityRevision!=selected.identityRevision)
      throw FableApiException(409,'session_changed_discard_response');
    return _cursorPage<FableSentInvitation>(
      response.data,FableSentInvitation.fromPayload);
  }
  Future<void> revokeSentInvitation(FableManagedAccount entity,
    FableManagedAccountSelection selected,FableSentInvitation invitation)async{
    _requireSelection(entity,selected);
    if(!entity.collaborationEnabled ||
      !(selected.access=='OWNER'||
        selected.access=='MANAGER'&&entity.managersCanInvite))
      throw StateError('Invalid invitation revocation permissions');
    await gateway.execute(
      _operation('/managed-entities/{id}/invitations/{invitationId}','DELETE'),
      path:{'id':entity.id,'invitationId':invitation.id});
    if(gateway.session.identityRevision!=selected.identityRevision)
      throw FableApiException(409,'session_changed_discard_response');
  }

  static const _lifecyclePaths=<String,String>{
    'disable':'/managed-entities/{id}/disable',
    'enable':'/managed-entities/{id}/enable',
    'delete-request':'/managed-entities/{id}/delete-request',
    'restore':'/managed-entities/{id}/restore',
  };

  bool canLifecycle(String action){
    final route=_lifecyclePaths[action];
    if(route==null||!can(route,'POST'))return false;
    return can('/auth/2fa/status','GET') &&
      can('/auth/otp/request','POST') && can('/auth/otp/verify','POST');
  }

  Future<FableManagedLifecycleChallenge> requestLifecycleChallenge(
      FableManagedAccount entity,String action)async{
    if(!entity.isOwner)throw StateError('Only a Backend-listed owner may request entity lifecycle actions');
    if(!canLifecycle(action)||!FableManagedAccount._uuid.hasMatch(entity.id))
      throw StateError('Backend has not exported this verified lifecycle/OTP workflow');
    if(action=='disable'&&entity.status!='ACTIVE' ||
       action=='enable'&&entity.status!='DISABLED' ||
       action=='restore'&&entity.status!='PENDING_DELETE' ||
       action=='delete-request'&&!const {'ACTIVE','DISABLED'}.contains(entity.status))
      throw StateError('This lifecycle action is invalid for the entity status');
    final rev=gateway.session.identityRevision;
    final status=await gateway.execute(_operation('/auth/2fa/status','GET'));
    if(gateway.session.identityRevision!=rev)
      throw FableApiException(409,'session_changed_discard_response');
    final data=_unwrap(status.data);
    if(data is! Map || data['enabled'] is! bool)
      throw const FormatException('Backend did not disclose authoritative 2FA status');
    final purpose=data['enabled']==true?'TWO_FACTOR':'SENSITIVE_ACTION';
    final request=await gateway.execute(_operation('/auth/otp/request','POST'),
      body:{'purpose':purpose});
    if(gateway.session.identityRevision!=rev)
      throw FableApiException(409,'session_changed_discard_response');
    final value=_unwrap(request.data),challengeId=value is Map?value['challengeId']:null;
    if(challengeId is! String || !FableManagedAccount._uuid.hasMatch(challengeId))
      throw const FormatException('Backend returned invalid lifecycle challenge identity');
    return FableManagedLifecycleChallenge._(challengeId,purpose,entity.id,action,rev);
  }

  /// The Backend consumes a VERIFIED, purpose-scoped, one-time OTP. No local
  /// authority or reusable proof is created and lifecycle changes are not
  /// automatically repeated on network errors.
  Future<Object?> verifyAndApplyLifecycle(
    FableManagedLifecycleChallenge pending,String code)async{
    if(!canLifecycle(pending.operation)||!RegExp(r'^[0-9]{4,10}$').hasMatch(code))
      throw ArgumentError('Invalid lifecycle OTP or backend operation');
    final rev=pending.identityRevision;
    if(gateway.session.identityRevision!=rev)
      throw StateError('Lifecycle challenge belongs to another login');
    final verified=await gateway.execute(_operation('/auth/otp/verify','POST'),
      body:{'challengeId':pending.challengeId,'code':code});
    if(gateway.session.identityRevision!=rev)
      throw FableApiException(409,'session_changed_discard_response');
    final proof=_unwrap(verified.data);
    if(proof is! Map||proof['verified']!=true||
       proof['challengeId']!=pending.challengeId||
       proof['purpose']!=pending.purpose)
      throw const FormatException('Wrong security proof purpose or challenge');
    final route=_lifecyclePaths[pending.operation]!;
    final changed=await gateway.execute(_operation(route,'POST'),
      path:{'id':pending.entityId},body:{'otpChallengeId':pending.challengeId});
    if(gateway.session.identityRevision!=rev)
      throw FableApiException(409,'session_changed_discard_response');
    return _unwrap(changed.data);
  }

  /// The caller must opt into each scoped operation. No implicit injection
  /// into Auth/Other Backends. The server re-checks membership on every call.
  Future<Object?> executeInContext(FableManagedAccountSelection selected,
    String operationId,{Map<String,dynamic>? path,Map<String,dynamic>? query,Object? body}) async {
    if(gateway.session.identityRevision!=selected.identityRevision)
      throw StateError('Managed entity selection belongs to a different login');
    final response=await gateway.executeInManagedEntity(
      operationId,selected.id,path:path,query:query,body:body);
    if(gateway.session.identityRevision!=selected.identityRevision)
      throw FableApiException(409,'session_changed_discard_response');
    return response.data;
  }
}

import 'package:fable_core/fable_core.dart';

/// إدارة الكيانات ميزة اختيارية خاصة بعقد Fable المثبت في هذا المشروع.
/// ظهور Widget أو وجود Blueprint عام لا يثبت توافر العملية أو صلاحيتها.
/// راجع docs/integrations/FABLE-FLUTTER-PARITY-MASTER.ar.md
class FableManagedAccount {
  const FableManagedAccount({
    required this.id,required this.type,required this.nameAr,
    required this.nameEn,required this.status,required this.visibility,
    required this.collaborationEnabled,required this.managersCanInvite,
    this.isOwner=false,this.slug,this.effectiveAccess,
  });
  final String id,type,nameAr,nameEn,status,visibility;
  final String? slug;
  final bool collaborationEnabled,managersCanInvite;
  final bool isOwner;
  /// Role in the latest authenticated listMine snapshot (not an authorization).
  /// Missing/inactive membership never validates a previously selected role.
  final String? effectiveAccess;

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
    // listMine contains only the current user's memberships, not everyone.
    // A previous MANAGER selection must be revoked when Backend now reports
    // VIEWER, inactive membership, or no trustworthy membership at all.
    final memberships=raw['memberships'];
    String? effectiveAccess;
    if(memberships!=null) {
      if(memberships is! List || memberships.length>100)
        throw const FormatException('Invalid managed membership list');
      for(final membership in memberships) {
        if(membership is! Map || membership['active'] is! bool ||
            !const {'OWNER','MANAGER','VIEWER'}.contains(membership['access'])) {
          throw const FormatException('Invalid managed membership role');
        }
        if(membership['active']==true) {
          if(effectiveAccess!=null)
            throw const FormatException('Conflicting active managed memberships');
          effectiveAccess=membership['access'] as String;
        }
      }
    }
    final isOwner=effectiveAccess=='OWNER';
    final rawSlug=raw['slug'];
    if(rawSlug!=null&&(rawSlug is! String||
       !RegExp(r'^[a-z0-9][a-z0-9-]{1,189}[a-z0-9]$').hasMatch(rawSlug)))
      throw const FormatException('Invalid managed entity slug');
    return FableManagedAccount(id:id,type:field('type',max:64),
      nameAr:field('nameAr'),nameEn:field('nameEn'),
      status:status,visibility:visibility,
      collaborationEnabled:raw['collaborationEnabled'] as bool,
      managersCanInvite:raw['managersCanInvite'] as bool,isOwner:isOwner,
      effectiveAccess:effectiveAccess,slug:rawSlug as String?);
  }
}

/// Public presentation is strictly smaller than the authenticated entity
/// model; never deserialize memberships, owner identifiers or private flags.
class FableManagedPublicEntity {
  const FableManagedPublicEntity({
    required this.id,required this.type,required this.nameAr,
    required this.nameEn,required this.slug,this.createdAt,
  });
  final String id,type,nameAr,nameEn,slug;
  final DateTime? createdAt;
  factory FableManagedPublicEntity.fromPayload(Object? raw){
    if(raw is! Map||raw['visibility']!='PUBLIC')
      throw const FormatException('Not a public managed entity');
    String requiredString(String key,{int max=191}){
      final v=raw[key];
      if(v is! String||v.isEmpty||v.length>max||
         RegExp(r'[\x00-\x1f\x7f<>]').hasMatch(v))
        throw FormatException('Invalid public entity field: $key');
      return v;
    }
    final id=requiredString('id',max:36),slug=requiredString('slug');
    if(!FableManagedAccount._uuid.hasMatch(id)||
       !RegExp(r'^[a-z0-9][a-z0-9-]{1,189}[a-z0-9]$').hasMatch(slug))
      throw const FormatException('Invalid public entity identity');
    final created=raw['createdAt'];
    if(created!=null&&(created is! String||DateTime.tryParse(created)==null))
      throw const FormatException('Invalid public entity createdAt');
    return FableManagedPublicEntity(id:id,type:requiredString('type',max:64),
      nameAr:requiredString('nameAr'),nameEn:requiredString('nameEn'),
      slug:slug,createdAt:created is String?DateTime.parse(created).toUtc():null);
  }
}

/// Volatile selection, validated against the activation response.
/// Backend remains the final authority for every subsequent scoped request.
class FableManagedAccountSelection extends FableManagedEntitySelection {
  const FableManagedAccountSelection({
    required super.id,required super.access,required super.nameAr,
    required super.nameEn,required super.identityRevision,
  });
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
  String _publicOperation(){
    final exported=contract.operations.values.where((operation)=>
      operation.method=='GET'&&operation.path=='/managed-entities/public/{slug}'&&
      !operation.requiresAuth&&operation.credentialHeader==null).toList();
    if(exported.length!=1)
      throw StateError('Public managed entity operation is not exported');
    return exported.single.id;
  }
  bool get canViewPublic {
    try {_publicOperation();return true;}catch(_){return false;}
  }
  Future<FableManagedPublicEntity> publicBySlug(String slug)async{
    if(!RegExp(r'^[a-z0-9][a-z0-9-]{1,189}[a-z0-9]$').hasMatch(slug))
      throw ArgumentError('Invalid public entity slug');
    final revision=gateway.session.identityRevision;
    final response=await gateway.execute(_publicOperation(),path:{'slug':slug});
    if(revision!=gateway.session.identityRevision)
      throw FableApiException(409,'session_changed_discard_response');
    final item=FableManagedPublicEntity.fromPayload(_unwrap(response.data));
    if(item.slug!=slug)
      throw const FormatException('Backend returned different public entity');
    return item;
  }

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

  /// All optional Backend CreateManagedAccountDto controls are explicit;
  /// never depend on unknown server defaults or synthesize entity types.
  Future<void> create({required String type,required String nameAr,
    required String nameEn,required String visibility,String? slug,
    bool collaborationEnabled=false,bool managersCanInvite=false}) async{
    final t=type.trim().toLowerCase(),ar=nameAr.trim(),en=nameEn.trim(),
      normalizedSlug=slug?.trim();
    if(!RegExp(r'^[a-z][a-z0-9_-]{1,63}$').hasMatch(t)||
      ar.isEmpty||en.isEmpty||ar.length>191||en.length>191||
      RegExp(r'[\x00-\x1f\x7f<>]').hasMatch(ar)||
      RegExp(r'[\x00-\x1f\x7f<>]').hasMatch(en)||
      !const {'PUBLIC','PRIVATE','INVITE_ONLY'}.contains(visibility)||
      (normalizedSlug!=null&&normalizedSlug.isNotEmpty&&
        !RegExp(r'^[a-z0-9][a-z0-9-]{1,189}[a-z0-9]$').hasMatch(normalizedSlug)))
      throw ArgumentError('Invalid managed entity create data');
    final collab=visibility=='PRIVATE'?false:collaborationEnabled;
    final managerInvites=collab&&managersCanInvite;
    final revision=gateway.session.identityRevision;
    final response=await gateway.execute(_operation('/managed-entities','POST'),body:{
      'type':t,'nameAr':ar,'nameEn':en,'visibility':visibility,
      'collaborationEnabled':collab,'managersCanInvite':managerInvites,
      if(normalizedSlug!=null&&normalizedSlug.isNotEmpty)'slug':normalizedSlug,
    });
    if(revision!=gateway.session.identityRevision)
      throw FableApiException(409,'session_changed_discard_response');
    final created=_unwrap(response.data);
    if(created is! Map||
      created['id'] is! String||
      !FableManagedAccount._uuid.hasMatch(created['id'] as String)||
      created['type']!=t||created['nameAr']!=ar||created['nameEn']!=en||
      created['visibility']!=visibility||
      created['collaborationEnabled']!=collab||
      created['managersCanInvite']!=managerInvites||
      (normalizedSlug!=null&&normalizedSlug.isNotEmpty&&
        created['slug']!=normalizedSlug))
      throw const FormatException('Backend did not confirm created entity configuration');
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
    final revision=gateway.session.identityRevision;
    final suffix=accept?'accept':'decline';
    final response=await gateway.execute(
      _operation('/managed-entities/invitations/{invitationId}/$suffix','POST'),
      path:{'invitationId':id});
    if(gateway.session.identityRevision!=revision)
      throw FableApiException(409,'session_changed_discard_response');
    final raw=response.data;
    final expectedCode=accept
      ?'MANAGED_ENTITY_INVITATION_ACCEPTED'
      :'MANAGED_ENTITY_INVITATION_DECLINED';
    if(raw is! Map || raw['success']!=true ||
        raw['messageCode']!=expectedCode)
      throw const FormatException('Backend did not confirm invitation decision');
    if(accept){
      final data=raw['data'];
      if(data is! Map || data['managedEntityId'] is! String ||
          !FableManagedAccount._uuid.hasMatch(data['managedEntityId'] as String) ||
          !const {'MANAGER','VIEWER'}.contains(data['access']))
        throw const FormatException('Backend returned an invalid accepted membership');
    }else if(raw['data']!=null){
      throw const FormatException('Unexpected declined-invitation response');
    }
  }
  /// A local UI role label is never sufficient to authorize invitations.
  /// A contract-exported operation, current identity and verified activation
  /// must all agree; the server still verifies every invitation and membership.
  Future<void> invite(FableManagedAccount entity,
    FableManagedAccountSelection selected,{
    required String username,required String access,
  }) async{
    _requireSelection(entity,selected);
    if(entity.status!='ACTIVE'||entity.visibility=='PRIVATE'||
       !entity.collaborationEnabled||
       !(selected.access=='OWNER'||
         selected.access=='MANAGER'&&entity.managersCanInvite))
      throw StateError('Invitation is not permitted by verified entity settings');
    final recipient=username.trim().toLowerCase();
    if(!RegExp(r'^[a-z0-9._]{3,30}$').hasMatch(recipient)||
       !const {'MANAGER','VIEWER'}.contains(access))
      throw ArgumentError('Invalid invitee or delegated access level');
    final response=await gateway.execute(
      _operation('/managed-entities/{id}/invitations','POST'),
      path:{'id':entity.id},body:{'username':recipient,'access':access});
    if(gateway.session.identityRevision!=selected.identityRevision)
      throw FableApiException(409,'session_changed_discard_response');
    final confirmed=_unwrap(response.data);
    if(confirmed is! Map||
       confirmed['id'] is! String||
       !FableManagedAccount._uuid.hasMatch(confirmed['id'] as String)||
       confirmed['managedEntityId']!=entity.id||
       confirmed['username']!=recipient||confirmed['access']!=access||
       confirmed['expiresAt'] is! String||
       DateTime.tryParse(confirmed['expiresAt'] as String)==null)
      throw const FormatException('Backend did not confirm verified invitation');
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
    FableManagedLifecycleChallenge pending,String code,{
      bool Function()? contextStillValid,
    })async{
    // Check again AFTER OTP verification: the Backend may have consumed the
    // proof while the user switched managed entities. Never then submit a
    // sensitive lifecycle mutation for the former UI context.
    bool validContext()=>contextStillValid?.call()??true;
    if(!validContext())throw StateError('Managed lifecycle context changed');
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
    if(!validContext())throw StateError('Managed lifecycle context changed after OTP verification');
    final route=_lifecyclePaths[pending.operation]!;
    final changed=await gateway.execute(_operation(route,'POST'),
      path:{'id':pending.entityId},body:{'otpChallengeId':pending.challengeId});
    if(gateway.session.identityRevision!=rev)
      throw FableApiException(409,'session_changed_discard_response');
    return _unwrap(changed.data);
  }

  /// Preferred API for screens bound to a shared managed-entity store.
  /// A late response from entity A is never rendered into entity B after a
  /// same-login switch, even when the authenticated identity epoch is stable.
  /// The Backend still authorizes each operation independently.
  Future<Object?> executeUsingStore(FableManagedEntityStore store,
      String operationId,{Map<String,dynamic>? path,
        Map<String,dynamic>? query,Object? body}) async {
    // Activation is accepted only after Fable's verified selection response.
    // Future generated feature repositories can use the same core executor.
    if(store.selected is! FableManagedAccountSelection)
      throw StateError('No Backend-confirmed Fable managed account selected');
    return FableManagedEntityExecutor(gateway,store).execute(
      operationId,path:path,query:query,body:body);
  }

  /// Legacy explicit selection API. UI code should prefer executeUsingStore
  /// so selection changes invalidate in-flight response consumption.
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


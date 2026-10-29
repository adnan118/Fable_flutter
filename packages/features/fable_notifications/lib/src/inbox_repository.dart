import 'package:fable_core/fable_core.dart';

final _uuid=RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');
final _safeId=RegExp(r'^[a-zA-Z0-9_-]{1,128}$');
/// Backend owns audience visibility. Never infer/read arbitrary notifications
/// from a guessed route or expose admin broadcast operations to mobile clients.
class FableInboxItem {
  const FableInboxItem({required this.id,required this.title,required this.body,
      required this.publishedAt,this.readAt,this.data=const {}});
  final String id,title,body;
  final DateTime? publishedAt,readAt;
  final Map<String,String> data;
  static FableInboxItem fromPayload(Object? value,{bool requireUuidIds=true}) {
    if(value is! Map)throw const FormatException('Invalid inbox item');
    final id=value['id'],title=value['title'],body=value['body'];
    if(id is! String || !(requireUuidIds ? _uuid.hasMatch(id) : _safeId.hasMatch(id)) ||
        title is! String || body is! String || title.length>400 || body.length>10000){
      throw const FormatException('Invalid inbox fields');
    }
    DateTime? time(Object? input)=>input is String?DateTime.tryParse(input):null;
    final rawData=value['data'];
    final data=<String,String>{};
    if(rawData is Map){
      // Only navigation allowlisted scalar fields; other metadata is not exposed.
      for(final key in const ['target','route','deepLink','url']){
        final v=rawData[key];
        if(v is String && v.length <= 2048)data[key]=v;
      }
    }
    return FableInboxItem(id:id,title:title,body:body,data:Map.unmodifiable(data),
      publishedAt:time(value['publishedAt']),readAt:time(value['readAt']));
  }
}
class FableInboxRepository {
  const FableInboxRepository(this.gateway, {
    this.listOperationId='notifications.inbox',
    this.markReadOperationId='notifications.read',
    this.requireUuidIds=true,
  });
  final BackendApiGateway gateway;
  final String listOperationId, markReadOperationId;
  final bool requireUuidIds;
  Future<List<FableInboxItem>> list() async {
    final response=await gateway.execute(listOperationId);
    final raw=response.data;
    // Fable notification inbox currently returns a top-level list. Do not
    // silently accept some unrelated success envelope on a changed API.
    if(raw is! List)throw const FormatException('Expected inbox list');
    if(raw.length>100)throw const FormatException('Inbox exceeds bounded page');
    return List.unmodifiable(raw.map((item)=>FableInboxItem.fromPayload(item,requireUuidIds:requireUuidIds)));
  }
  Future<void> markRead(String id) async {
    if(!(requireUuidIds ? _uuid.hasMatch(id) : _safeId.hasMatch(id))){
      throw ArgumentError('Invalid notification id');
    }
    await gateway.execute(markReadOperationId,path:{'id':id});
  }
}

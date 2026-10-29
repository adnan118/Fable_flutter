import 'package:fable_core/fable_core.dart';
/// Metadata and runtime strategy reading only. Resumable uploads live in
/// media_upload_repository.dart; protected playback remains a separate gate.
class FableMediaReadRepository {
 const FableMediaReadRepository(this.gateway);
 final BackendApiGateway gateway;
 Future<Map<String,dynamic>> runtimeContract() async {
  final response=await gateway.execute('media.clientContract');
  final value=response.data;
  if(value is! Map)throw const FormatException('Invalid media runtime contract');
  return Map<String,dynamic>.unmodifiable(Map<String,dynamic>.from(value));
 }
 Future<Map<String,dynamic>> metadata(String id) async {
  if(!RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$').hasMatch(id)){
   throw ArgumentError('Invalid media id');
  }
  final response=await gateway.execute('media.metadata',path:{'id':id});
  if(response.data is! Map)throw const FormatException('Invalid media metadata');
  return Map<String,dynamic>.unmodifiable(Map<String,dynamic>.from(response.data as Map));
 }
}

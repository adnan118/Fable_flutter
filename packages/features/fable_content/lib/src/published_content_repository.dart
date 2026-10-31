import 'package:fable_core/fable_core.dart';

/// Snapshot of effective public pages. Admin drafts are not mobile content.
class FablePublishedIndexEntry {
 const FablePublishedIndexEntry(this.slug,this.versionId,this.version);
 final String slug,versionId;
 final int version;
 static final _slugPattern=RegExp(r'^[\p{L}\p{N}][\p{L}\p{N}_-]{0,189}$',unicode:true);
 static final _uuid=RegExp(r'^[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}$');
 factory FablePublishedIndexEntry.fromPayload(Object? raw){
  if(raw is! Map||raw['slug'] is! String||raw['revision'] is! String||
     raw['version'] is! int)throw const FormatException('Invalid published entry');
  final slug=raw['slug'] as String,revision=raw['revision'] as String,
    version=raw['version'] as int;
  if(!_slugPattern.hasMatch(slug)||!_uuid.hasMatch(revision)||version<1)
    throw const FormatException('Invalid published content revision');
  return FablePublishedIndexEntry(slug,revision,version);
 }
}

/// Read-only published documents from a verified operation catalog.
/// For Other Backend, pass its explicitly bound operation ID and adapter.
/// A structurally different external response requires an injected converter,
/// never guessing endpoint names or treating an admin/draft response as public.
class FablePublishedDocument {
  const FablePublishedDocument({required this.id,required this.slug,
    required this.versionId,required this.title,required this.locale,
    required this.blocks,this.summary,this.requiresAcceptance=false});
  final String id,slug,versionId,title,locale;
  final String? summary;
  final bool requiresAcceptance;
  final List<FableContentBlock> blocks;

  static FablePublishedDocument fromPayload(Object? input){
    if(input is! Map)throw const FormatException('Published content must be a map');
    String field(Map source,String name,{int max=500}){
      final v=source[name];if(v is! String||v.isEmpty||v.length>max)throw FormatException('Invalid published field $name');
      return v;
    }
    final page=input['page'],version=input['version'],locale=input['locale'];
    final blocks=input['blocks'];
    if(page is! Map||version is! Map||locale is! Map||blocks is! List||blocks.length>100)throw const FormatException('Invalid published content envelope');
    final summary=input['summary'];
    if(summary!=null&&(summary is! String||summary.length>5000))throw const FormatException('Invalid summary');
    final acceptance=page['requiresAcceptance'];
    if(acceptance!=null&&acceptance is! bool)throw const FormatException('Invalid acceptance policy');
    return FablePublishedDocument(id:field(page,'id'),slug:field(page,'slug'),
      versionId:field(version,'id'),title:field(input,'title',max:500),
      locale:field(locale,'resolved',max:35),summary:summary as String?,
      requiresAcceptance:acceptance==true,
      blocks:List.unmodifiable(blocks.map(FableContentBlock.fromPayload)));
  }
}
class FableContentBlock {
  const FableContentBlock({required this.type,required this.id,required this.data});
  final String type,id;
  final Map<String,dynamic> data;
  static FableContentBlock fromPayload(Object? input){
    if(input is! Map||input['id'] is! String||input['type'] is! String||input['data'] is! Map)throw const FormatException('Invalid block');
    final type=input['type'] as String;
    if(type.length>60||!RegExp(r'^[a-z][a-z0-9-]*$').hasMatch(type))throw const FormatException('Invalid content block type');
    final data=Map<String,dynamic>.from(input['data'] as Map);
    if(data.length>70)throw const FormatException('Excessive block fields');
    return FableContentBlock(id:input['id'] as String,type:type,data:Map.unmodifiable(data));
  }
}
typedef FablePublishedContentDecoder = FablePublishedDocument Function(Object? response);
class FablePublishedContentRepository {
  const FablePublishedContentRepository(this.gateway,{this.readOperationId='content.page.read',
    this.acceptOperationId='content.page.accept',this.slugPathParameter='slug',
    this.localeQueryParameter='locale',this.indexOperationId,
    this.decoder=FablePublishedDocument.fromPayload});
  final BackendApiGateway gateway;
  final String readOperationId,acceptOperationId;
  /// Optional verified changes snapshot; never guessed for external backends.
  final String? indexOperationId;
  /// Explicit path/query names for an imported Other Backend contract.
  final String slugPathParameter;
  final String? localeQueryParameter;
  /// A project can explicitly decode its *verified* external public schema.
  final FablePublishedContentDecoder decoder;
  static final _slug=RegExp(r'^[\p{L}\p{N}][\p{L}\p{N}_-]{0,189}$',unicode:true);
  Future<List<FablePublishedIndexEntry>> publishedIndex()async{
    final operation=indexOperationId;
    if(operation==null)throw StateError('No verified published-content index operation');
    final response=await gateway.execute(operation);
    final raw=response.data;
    if(raw is! Map||raw['revision'] is! String||
       !RegExp(r'^[0-9a-f]{64}$').hasMatch(raw['revision'] as String)||
       raw['unchanged']!=false||raw['resetRequired']!=false||
       raw['entries'] is! List)
      throw const FormatException('Invalid published-content snapshot');
    final rows=raw['entries'] as List;
    if(rows.length>500)throw const FormatException('Published content index exceeds limit');
    final items=rows.map(FablePublishedIndexEntry.fromPayload).toList();
    if(items.map((e)=>e.slug).toSet().length!=items.length)
      throw const FormatException('Duplicate published content slug');
    return List.unmodifiable(items);
  }

  Future<FablePublishedDocument> read(String slug,{String? locale}) async{
    if(!_slug.hasMatch(slug))throw ArgumentError.value(slug,'slug','Invalid public content slug');
    if(locale!=null&&!RegExp(r'^[a-zA-Z]{2,8}(?:-[a-zA-Z0-9]{2,8})*$').hasMatch(locale))throw ArgumentError.value(locale,'locale');
    if(!RegExp(r'^[a-zA-Z][a-zA-Z0-9_]{0,49}$').hasMatch(slugPathParameter))throw ArgumentError('Invalid path parameter');
    if(localeQueryParameter!=null&&!RegExp(r'^[a-zA-Z][a-zA-Z0-9_]{0,49}$').hasMatch(localeQueryParameter!))throw ArgumentError('Invalid locale query parameter');
    final result=await gateway.execute(readOperationId,path:{slugPathParameter:slug},
      query:locale==null||localeQueryParameter==null?null:{localeQueryParameter!:locale});
    // Decoder must return a typed published document; never render raw admin data.
    return decoder(result.data);
  }
  Future<void> accept(FablePublishedDocument content)async{
    if(content.id.isEmpty||content.versionId.isEmpty)throw ArgumentError('Invalid version');
    await gateway.execute(acceptOperationId,path:{'pageId':content.id},body:{'versionId':content.versionId});
  }
}

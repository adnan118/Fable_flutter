import 'package:fable_core/fable_core.dart';

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
    this.localeQueryParameter='locale',this.decoder=FablePublishedDocument.fromPayload});
  final BackendApiGateway gateway;
  final String readOperationId,acceptOperationId;
  /// Explicit path/query names for an imported Other Backend contract.
  final String slugPathParameter;
  final String? localeQueryParameter;
  /// A project can explicitly decode its *verified* external public schema.
  final FablePublishedContentDecoder decoder;
  static final _slug=RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9_-]{0,99}$');
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

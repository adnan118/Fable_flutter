import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:material_ui/material_ui.dart';
import 'package:fable_core/fable_core.dart';
import 'package:fable_feature_contract/fable_feature_contract.dart';
import 'src/published_content_index.dart';
import 'src/published_content_repository.dart';
export 'src/published_content_repository.dart';
export 'src/published_content_widgets.dart';
export 'src/published_content_index.dart';

/// A real public-content index only for an explicitly exported Fable contract.
/// Other Backends supply their own operation bindings and screen explicitly.
class FableContentFeature extends FableFeature {
 const FableContentFeature():super(
   id:'content',title:'Published content',icon:Icons.article_outlined,
   backendKeywords:const ['content','public','page']);

 @override Widget screen(FableContract contract){
  final read=contract.operations['content.page.read'],
    index=contract.operations['content.publicChanges'],
    accept=contract.operations['content.page.accept'];
  const base=String.fromEnvironment('FABLE_API_BASE_URL');
  if(base.isEmpty||
     read?.method!='GET'||read?.path!='/content/pages/{slug}'||
     read?.requiresAuth!=false||
     index?.method!='GET'||index?.path!='/content/pages/changes'||
     index?.requiresAuth!=false||
     accept?.method!='POST'||accept?.path!='/content/pages/{pageId}/accept'||
     accept?.requiresAuth!=true){
    // Do not render a document page that cannot record legally required consent.
    return FableCapabilityScreen(feature:this,contract:contract);
  }
  final gateway=FableAuthGateway(baseUri:Uri.parse(base),
    contract:contract,allowHttpForLocalDevelopment:kDebugMode);
  return FablePublishedContentIndexPage(
    repository:FablePublishedContentRepository(gateway,
      indexOperationId:'content.publicChanges'),
    identitySignals:gateway.session.identityEvents,
    onDispose:gateway.dispose);
 }
}

const FableContentFeature contentFeature=FableContentFeature();

import 'package:material_ui/material_ui.dart';
import 'package:fable_feature_contract/fable_feature_contract.dart';
export 'src/published_content_repository.dart';
export 'src/published_content_widgets.dart';

/// Optional library-level capability; no global routing or required screens.
/// Use FablePublishedContentPage with an injected verified BackendApiGateway
/// and explicit operation IDs in either Fable or Other Backend projects.
const FableFeature contentFeature=FableFeature(
  id:'content',title:'Published content',icon:Icons.article_outlined,
  backendKeywords:['content','public','page']);

import 'package:material_ui/material_ui.dart';
import 'package:fable_feature_contract/fable_feature_contract.dart';

const FableFeature deeplinksFeature=FableFeature(
  id:'deeplinks', title:'Deep links', icon:Icons.link, backendKeywords:['link']);
export 'src/deep_link_policy.dart';
export 'src/deep_link_dispatcher.dart';
export 'src/deep_link_bootstrap.dart';

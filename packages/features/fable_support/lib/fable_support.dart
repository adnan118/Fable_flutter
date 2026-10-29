import 'package:material_ui/material_ui.dart';
import 'package:fable_feature_contract/fable_feature_contract.dart';

const FableFeature supportFeature=FableFeature(
  id:'support', title:'Support', icon:Icons.support_agent, backendKeywords:['support','ticket']);

export 'src/support_repository.dart';
export 'src/support_widgets.dart';

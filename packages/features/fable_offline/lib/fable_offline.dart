import 'package:material_ui/material_ui.dart';
import 'package:fable_feature_contract/fable_feature_contract.dart';
export 'src/offline_reaction_queue.dart';
export 'src/offline_queue_panel.dart';

const FableFeature offlineFeature=FableFeature(
  id:'offline', title:'Offline', icon:Icons.cloud_off_outlined, backendKeywords:['sync']);

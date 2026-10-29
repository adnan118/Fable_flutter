export 'src/public_change_sse.dart';
export 'src/public_change_sync.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fable_feature_contract/fable_feature_contract.dart';

const FableFeature realtimeFeature=FableFeature(
  id:'realtime', title:'Realtime', icon:Icons.sync, backendKeywords:['realtime','livekit']);
export 'src/verified_change_coordinator.dart';

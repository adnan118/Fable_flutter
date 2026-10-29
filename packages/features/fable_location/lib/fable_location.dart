import 'package:material_ui/material_ui.dart';
import 'package:fable_feature_contract/fable_feature_contract.dart';
export 'src/location_repository.dart';
export 'src/location_widgets.dart';

const FableFeature locationFeature=FableFeature(
  id:'location', title:'Location', icon:Icons.place_outlined, backendKeywords:['location-platform','location','map']);

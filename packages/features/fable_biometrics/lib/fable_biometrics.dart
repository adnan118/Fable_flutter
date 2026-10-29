import 'package:material_ui/material_ui.dart';
import 'package:fable_feature_contract/fable_feature_contract.dart';
export 'src/biometrics_repository.dart';
export 'src/biometrics_widgets.dart';

const FableFeature biometricsFeature=FableFeature(
  id:'biometrics', title:'Biometrics', icon:Icons.fingerprint, backendKeywords:['passkey','webauthn']);


import 'package:material_ui/material_ui.dart';
import 'package:fable_feature_contract/fable_feature_contract.dart';
export 'src/access_snapshot.dart';
export 'src/permission_gate.dart';
export 'src/access_repository.dart';
export 'src/access_policy.dart';
export 'src/access_session.dart';
export 'src/authorized_action.dart';
export 'src/access_bootstrap.dart';
export 'src/role_view.dart';
const FableFeature access_controlFeature = FableFeature(
  id: 'access_control', title: 'Access control', icon: Icons.shield_outlined,
  backendKeywords: ['access', 'permissions', 'roles']);

import 'package:material_ui/material_ui.dart';
import 'package:fable_feature_contract/fable_feature_contract.dart';

const FableFeature paymentsFeature=FableFeature(
  id:'payments', title:'Payments', icon:Icons.payments_outlined, backendKeywords:['payment','transaction']);

export 'src/payments_repository.dart';
export 'src/payments_widgets.dart';

import 'package:material_ui/material_ui.dart';
import 'package:fable_core/fable_core.dart';
import 'package:fable_feature_contract/fable_feature_contract.dart';
import 'src/login_page.dart';
import 'src/external_login_page.dart';
export 'src/sessions_page.dart';

class FableAuthFeature extends FableFeature {
  const FableAuthFeature():super(id:'auth',title:'Authentication',icon:Icons.lock_outline,
      backendKeywords:const ['auth','session']);
  @override Widget screen(FableContract contract)=>FableLoginPage(contract:contract);
  @override Widget? externalScreen(ExternalOperationCatalog catalog, ExternalFeatureBindings bindings) =>
      ExternalLoginPage(catalog:catalog);
}
const FableAuthFeature authFeature=FableAuthFeature();

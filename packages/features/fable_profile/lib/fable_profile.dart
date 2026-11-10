import 'package:material_ui/material_ui.dart';
import 'package:fable_core/fable_core.dart';
import 'package:fable_feature_contract/fable_feature_contract.dart';
import 'src/external_profile_page.dart';
import 'src/fable_account_page.dart';
import 'src/profile_account_route_policy.dart';

export 'src/external_profile_repository.dart';
export 'src/profile_account_route_policy.dart';
export 'src/managed_accounts_repository.dart' show FableManagedScopedOperation, FableManagedAccountsRepository;
export 'src/external_profile_page.dart';

class FableProfileFeature extends FableFeature {
  const FableProfileFeature() : super(
    id: 'profile', title: 'Profile', icon: Icons.person_outline,
    backendKeywords: const ['profile', 'account']);

  @override bool canLaunchFable(FableContract contract) =>
    FableProfileAccountRoutePolicy.canRead(contract);
  @override Widget screen(FableContract contract)=>FableAccountPage(contract:contract);

  @override
  Widget? externalScreen(ExternalOperationCatalog catalog, ExternalFeatureBindings bindings) {
    if (bindings.operation('profile', 'read') == null) return null;
    return ExternalProfilePage(catalog: catalog, bindings: bindings);
  }
}
const FableProfileFeature profileFeature = FableProfileFeature();

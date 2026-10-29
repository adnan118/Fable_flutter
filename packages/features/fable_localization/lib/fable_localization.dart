import 'package:material_ui/material_ui.dart';
import 'package:fable_core/fable_core.dart';
import 'package:fable_feature_contract/fable_feature_contract.dart';
import 'src/languages_page.dart';
export 'src/languages_repository.dart';
export 'src/client_copy_sync.dart';
/// Device/explicit-user locale selection is controlled by application Core.
/// This feature reads the *supported* languages from an exported backend
/// operation; it never fabricates an automatic translation endpoint.
class FableLocalizationFeature extends FableFeature {
 const FableLocalizationFeature():super(id:'localization',title:'Localization',icon:Icons.language,
  backendKeywords:const ['language','translation']);
 @override Widget screen(FableContract contract)=>FableLanguagesPage(contract:contract);
}
const FableLocalizationFeature localizationFeature=FableLocalizationFeature();

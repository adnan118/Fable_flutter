import 'package:material_ui/material_ui.dart';
import 'package:fable_core/fable_core.dart';
import 'package:fable_feature_contract/fable_feature_contract.dart';
import 'src/inbox_page.dart';
export 'src/inbox_repository.dart';
export 'src/notification_navigation.dart';
export 'src/inbox_refresh_signal.dart';
class FableNotificationsFeature extends FableFeature {
 const FableNotificationsFeature():super(id:'notifications',title:'Notifications',icon:Icons.notifications_none,backendKeywords:const ['notification','push']);
 @override Widget screen(FableContract contract)=>FableInboxPage(contract:contract);
 @override Widget? externalScreen(ExternalOperationCatalog catalog,ExternalFeatureBindings bindings) {
   // Never guess a route, payload or permission from a non-Fable API.
   final list=bindings.operation('notifications','list');
   final markRead=bindings.operation('notifications','markRead');
   if(list==null||markRead==null)return null;
   final get=catalog.require(list), post=catalog.require(markRead);
   if(get.method!='GET'||!get.requiresAuth||get.credentialHeader!=null||
      !const ['POST','PATCH','PUT'].contains(post.method)||
      !post.requiresAuth||post.credentialHeader!=null||
      RegExp(r'\{([^{}]*)\}').allMatches(post.path).map((m)=>m.group(1)).join(',')!='id'||
      RegExp(r'\{([^{}]*)\}').hasMatch(get.path))return null;
   return FableInboxPage.external(catalog:catalog,listOperationId:list,
     markReadOperationId:markRead);
 }
}
const FableNotificationsFeature notificationsFeature=FableNotificationsFeature();

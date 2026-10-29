import 'package:material_ui/material_ui.dart';
import 'package:fable_core/fable_core.dart';

/// A feature can be installed while its optional backend operations are absent.
class FableFeature {
  const FableFeature({required this.id,required this.title,required this.icon,this.backendKeywords=const []});
  final String id,title;final IconData icon;final List<String> backendKeywords;
  /// Override only for features that have real, explicitly bound external operations.
  Widget? externalScreen(ExternalOperationCatalog catalog, ExternalFeatureBindings bindings) => null;
  Widget screen(FableContract contract)=>FableCapabilityScreen(feature:this,contract:contract);
}

/// Generated declaration for a project-specific domain feature.
/// This describes architecture only; it does not claim that UI or business
/// behavior has been implemented. Project code can build on this descriptor.
class FableProjectFeatureDescriptor {
  const FableProjectFeatureDescriptor({
    required this.id,
    required this.label,
    required this.requiredCapabilities,
    required this.dependsOnFeatures,
    required this.operationIds,
    required this.status,
    required this.implementationStatus,
  });

  final String id;
  final String label;
  final List<String> requiredCapabilities;
  final List<String> dependsOnFeatures;
  final List<String> operationIds;
  final String status;
  final String implementationStatus;
}

class FableCapabilityScreen extends StatelessWidget {
  const FableCapabilityScreen({super.key,required this.feature,required this.contract});
  final FableFeature feature;final FableContract contract;
  @override Widget build(BuildContext context){
    final candidates=contract.operations.values.where((op)=>feature.backendKeywords.any((word)=>op.id.toLowerCase().contains(word))).toList();
    return Scaffold(appBar:AppBar(title:Text(feature.title)),body:SafeArea(child:ListView(padding:const EdgeInsets.all(20),children:[
      Icon(feature.icon,size:54,color:Theme.of(context).colorScheme.primary),const SizedBox(height:20),
      Text(feature.title,style:Theme.of(context).textTheme.headlineMedium,textAlign:TextAlign.center),
      const SizedBox(height:16),
      Text(candidates.isEmpty?'No matching backend operations in imported contract. This module is not yet connected to a live service.':'Available backend operations (${candidates.length})',textAlign:TextAlign.center),
      for(final op in candidates)ListTile(title:Text(op.id),subtitle:Text('${op.method} ${op.path}')),
      const SizedBox(height:12),
      const Text('This is a capability integration screen, not a completed consumer workflow.',textAlign:TextAlign.center),
    ])));
  }
}

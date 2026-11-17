import 'package:flutter_test/flutter_test.dart';
import 'package:fable_core/fable_core.dart';

FableContract _signedContract()=>FableContract(
  contractHash:'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  operations:const <String,FableOperation>{
    'catalog.list.paginated':FableOperation(
      'catalog.list.paginated','GET','/catalog',
      'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      requiresAuth:true,enforceAuth:true,recordAccess:'managed-entity:company'),
    'public.health':FableOperation(
      'public.health','GET','/health',
      'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
      requiresAuth:false,enforceAuth:true,recordAccess:'permission-wide'),
  },
  featureIds:const <String>{'catalog','auth'},
  projectName:'source-only-fixture',selectionMode:'explicit',
);
void main(){
  test('RC358 a signed managed operation must carry a verified selected entity',()async{
    final api=UnifiedApiClient(baseUri:Uri.parse('https://api.example.test'),
      contract:_signedContract(),session:FableSecureSession());
    addTearDown(api.dispose);
    await expectLater(api.request('catalog.list.paginated'),throwsArgumentError);
  });
  test('RC358 managed entity header always requires a live context validation callback',()async{
    final api=UnifiedApiClient(baseUri:Uri.parse('https://api.example.test'),
      contract:_signedContract(),session:FableSecureSession());
    addTearDown(api.dispose);
    await expectLater(api.request('catalog.list.paginated',
      managedEntityId:'00000000-0000-4000-8000-000000000000'),
      throwsArgumentError);
  });
  test('RC358 a context callback without entity ID is refused before network access',()async{
    final api=UnifiedApiClient(baseUri:Uri.parse('https://api.example.test'),
      contract:_signedContract(),session:FableSecureSession());
    addTearDown(api.dispose);
    await expectLater(api.request('public.health',contextStillValid:()=>true),
      throwsArgumentError);
  });
}

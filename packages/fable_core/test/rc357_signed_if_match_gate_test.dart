import 'package:flutter_test/flutter_test.dart';
import 'package:fable_core/fable_core.dart';

FableContract _contract()=>FableContract(
  contractHash:'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  operations:const <String,FableOperation>{
    'notes.update':FableOperation('notes.update','PATCH','/notes',
      'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      requiresAuth:true,enforceAuth:true,requiresIfMatch:true),
    'notes.delete':FableOperation('notes.delete','DELETE','/notes',
      'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
      requiresAuth:true,enforceAuth:true,requiresIfMatch:true),
    'notes.create':FableOperation('notes.create','POST','/notes',
      'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd',
      requiresAuth:true,enforceAuth:true),
  },
  featureIds:const <String>{'notes'},projectName:'source-only-fixture',
  selectionMode:'explicit',
);
void main(){
  test('RC357 a signed PATCH or DELETE cannot reach network without If-Match',()async{
    final client=UnifiedApiClient(
      baseUri:Uri.parse('https://api.example.test'),
      contract:_contract(),session:FableSecureSession(),
    );
    addTearDown(client.dispose);
    await expectLater(client.execute('notes.update'),throwsArgumentError);
    await expectLater(client.execute('notes.delete'),throwsArgumentError);
  });
  test('RC357 an unsigned POST cannot smuggle signed-only If-Match',()async{
    final client=UnifiedApiClient(
      baseUri:Uri.parse('https://api.example.test'),
      contract:_contract(),session:FableSecureSession(),
    );
    addTearDown(client.dispose);
    await expectLater(client.execute('notes.create',
      ifMatch:'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'),
      throwsArgumentError);
  });
  test('RC357 signed mutation rejects malformed or quoted revision hash',()async{
    final client=UnifiedApiClient(
      baseUri:Uri.parse('https://api.example.test'),
      contract:_contract(),session:FableSecureSession(),
    );
    addTearDown(client.dispose);
    await expectLater(client.execute('notes.update',ifMatch:'bad'),throwsArgumentError);
    await expectLater(client.execute('notes.update',
      ifMatch:'"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"'),
      throwsArgumentError);
  });
}

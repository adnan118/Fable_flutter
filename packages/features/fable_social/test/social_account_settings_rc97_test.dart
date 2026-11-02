import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fable_core/fable_core.dart';
import 'package:fable_social/fable_social.dart';

class _FakeSdk implements FableSocialCredentialProvider {
  @override Future<FableSocialCredential?> obtain(FableSocialChallenge challenge) async=>null;
}
class _Session extends FableSecureSession {
  _Session(String name):super(namespace:name);
  @override int identityRevision=0;
  @override Future<String?> get accessToken async=>'session-mock';
  @override Future<String?> get refreshToken async=>null;
}
FableContract _catalog()=>FableContract(
  contractHash:'rc97',projectName:'test',selectionMode:'advisory',
  featureIds:const {'auth','social'},operations:{
    for(final role in FableSocialOperations.fableIds.keys)
      FableSocialOperations.fableIds[role]!:
        FableOperation(FableSocialOperations.fableIds[role]!,
          role=='unlink'?'DELETE':'POST',
          role=='unlink'?'/auth/social/:provider':
            role=='googleLink'?'/auth/social/google/link':
            role=='appleLink'?'/auth/social/apple/link':
            '/auth/social/$role','rc97',
          requiresAuth:const {'googleLink','appleLink','unlink'}.contains(role),
          enforceAuth:true),
  });

void main(){
  testWidgets('RC97 shows link/unlink actions when social SDK shares gateway',
      (tester)async{
    final session=_Session('test.social.rc97.1'),catalog=_catalog();
    final gateway=FableAuthGateway(baseUri:Uri.parse('https://test.invalid'),
      contract:catalog,secureSession:session);
    addTearDown(gateway.dispose);
    final repo=FableSocialRepository(gateway:gateway,session:session,
      operations:FableSocialOperations.fable(catalog),
      credentials:_FakeSdk(),adapter:const FableSocialBackendAdapter());
    await tester.pumpWidget(MaterialApp(home:FableSocialAccountSettingsPage(
      gateway:gateway,repository:repo)));
    expect(find.text('Link google'),findsOneWidget);
    expect(find.text('Unlink apple'),findsOneWidget);
    expect(find.textContaining('Unavailable:'),findsNothing);
  });
  testWidgets('RC97 refuses linking with different Auth session',
      (tester)async{
    final correct=_Session('test.social.rc97.2'),wrong=_Session('test.social.rc97.3'),
      catalog=_catalog();
    final gateway=FableAuthGateway(baseUri:Uri.parse('https://test.invalid'),
      contract:catalog,secureSession:correct);
    addTearDown(gateway.dispose);
    final repo=FableSocialRepository(gateway:gateway,session:wrong,
      operations:FableSocialOperations.fable(catalog),
      credentials:_FakeSdk(),adapter:const FableSocialBackendAdapter());
    await tester.pumpWidget(MaterialApp(home:FableSocialAccountSettingsPage(
      gateway:gateway,repository:repo)));
    expect(find.textContaining('Unavailable:'),findsOneWidget);
    expect(find.text('Link google'),findsNothing);
  });
}

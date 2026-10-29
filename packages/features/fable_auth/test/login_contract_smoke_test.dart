import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fable_core/fable_core.dart';
import 'package:fable_auth/src/login_page.dart';

void main() {
  testWidgets('Missing backend contract cannot create an authenticated UI', (tester) async {
    const contract = FableContract(contractHash: 'unconfigured',
      operations: <String, FableOperation>{},
      featureIds: <String>{}, projectName: 'Test', selectionMode: 'advisory');
    await tester.pumpWidget(const MaterialApp(home: FableLoginPage(contract: contract)));
    expect(find.text('Login contract missing'), findsOneWidget);
    expect(find.text('Session saved securely.'), findsNothing);
  });
}

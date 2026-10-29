import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fable_design_system/fable_design_system.dart';
void main(){
  testWidgets('design skeleton is accessible', (tester) async {
    await tester.pumpWidget(MaterialApp(theme:FableTokens.theme(Brightness.light),
      home:const Scaffold(body:FableSkeleton(height:35))));
    expect(find.byType(FableSkeleton),findsOneWidget);
  });
}

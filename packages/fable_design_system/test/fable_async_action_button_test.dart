import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fable_design_system/fable_design_system.dart';
void main() {
  testWidgets('mutations are opt-in and not executed twice', (tester) async {
    var calls = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: FableAsyncActionButton(
      label: 'Save', onExecute: () async { calls++; },
    ))));
    expect(calls, 0);
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(calls, 1);
  });
  testWidgets('destructive actions always require confirmation', (tester) async {
    var calls = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: FableAsyncActionButton(
      label: 'Delete', isDestructive:true,
      onExecute: () async { calls++; },
    ))));
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(calls, 0);
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(calls, 0);
  });
}

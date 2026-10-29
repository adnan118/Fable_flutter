import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fable_design_system/fable_design_system.dart';

void main() {
  testWidgets('Error offers a real retry action only when supplied', (tester) async {
    var tries = 0;
    await tester.pumpWidget(MaterialApp(home: FableStateView(
      state: FableContentState.error, onRetry: () => tries++)));
    expect(find.text('Could not load this content'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    expect(tries, 1);
    await tester.pumpWidget(const MaterialApp(home: FableStateView(state: FableContentState.error)));
    expect(find.text('Try again'), findsNothing);
  });
  test('Critical offline/error fallbacks are available without network', () {
    expect(FableStateCopy.forLocale(const Locale('ar')).offline,
      FableStateCopy.arabic.offline);
    expect(FableStateCopy.forLocale(const Locale('en')).error,
      FableStateCopy.english.error);
  });
  testWidgets('Ready requires content, other states do not expose it', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: FableStateView(
      state: FableContentState.ready, child: Text('Actual content'))));
    expect(find.text('Actual content'), findsOneWidget);
    await tester.pumpWidget(const MaterialApp(home: FableStateView(
      state: FableContentState.empty, child: Text('Actual content'))));
    expect(find.text('Actual content'), findsNothing);
  });
}

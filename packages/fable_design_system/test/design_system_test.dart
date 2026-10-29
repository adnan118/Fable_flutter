import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fable_design_system/fable_design_system.dart';

void main() {
  test('Adaptive tokens are based on width, never platform identity', () {
    expect(FableAdaptive.fromWidth(400), FableWindowClass.compact);
    expect(FableAdaptive.fromWidth(600), FableWindowClass.medium);
    expect(FableAdaptive.fromWidth(840), FableWindowClass.expanded);
    expect(FableAdaptive.fromWidth(1200), FableWindowClass.large);
    expect(FableAdaptive.pick(400, compact:2, medium:3), 2);
    expect(FableAdaptive.pick(840, compact:2, medium:3, expanded:4), 4);
    expect(FableComponentTokens.buttonHeightAt(400), 52);
    expect(FableComponentTokens.buttonHeightAt(1200), 60);
  });
  test('Brand, semantic status and surface extensions coexist in dark theme', () {
    const brand=FableBrandPalette(primary:Color(0xFF0B7285),
      secondary:Color(0xFFFF8A00),additional:{'promotion':Color(0xFFAA44AA)});
    const status=FableSemanticColors.defaults;
    final light=FableTokens.theme(Brightness.light,brandPalette:brand,semanticColors:status);
    final dark=FableTokens.theme(Brightness.dark,brandPalette:brand,semanticColors:status);
    expect(light.extension<FableBrandPalette>()!.colorFor('promotion'),const Color(0xFFAA44AA));
    expect(light.extension<FableSemanticColors>()!.success,status.success);
    expect(dark.colorScheme.error,status.error);
    expect(dark.extension<FableUiColors>()!.textPrimary,dark.colorScheme.onSurface);
    expect(light.extension<FableUiColors>()!.border,light.colorScheme.outlineVariant);
  });
  testWidgets('Responsive widgets see constrained width', (tester) async {
    FableWindowClass? window;
    await tester.pumpWidget(MaterialApp(home:Center(child:SizedBox(width:400,
      child:FableAdaptiveBuilder(builder:(context,constraints,actual) {
        window=actual;
        return const Text('Adaptive');
      })))));
    expect(window,FableWindowClass.compact);
  });
}

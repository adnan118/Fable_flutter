import 'package:material_ui/material_ui.dart';
import 'fable_adaptive.dart';
import 'tokens.g.dart';

/// Component-specific dimensions built on Foundation rather than literals in Widgets.
abstract final class FableComponentTokens {
  static const double buttonHeight=FableGeneratedTokens.componentButtonHeight;
  static const double fieldHeight=FableGeneratedTokens.componentInputHeight;
  static const double iconMedium=FableGeneratedTokens.componentIconMedium;
  static const double imageMedium=FableGeneratedTokens.componentImageMedium;
  static const double minimumTouchTarget=FableGeneratedTokens.componentTouchTarget;
  static const double formMaxWidth=FableGeneratedTokens.componentMaxFormWidth;
  static const double screenPadding=FableGeneratedTokens.componentScreenPadding;
  static double buttonHeightAt(double width)=>FableAdaptive.pick(width,compact:buttonHeight,medium:56,expanded:60);
  static double screenPaddingAt(double width)=>FableAdaptive.pick(width,compact:screenPadding,medium:32,expanded:48,large:64);
}

/// A reusable accessible baseline button; widgets never hard-code brand colors.
class FablePrimaryButton extends StatelessWidget {
  const FablePrimaryButton({super.key,required this.label,required this.onPressed,this.icon});
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => FableAdaptiveBuilder(builder:(context,constraints,_) {
    final minHeight=FableComponentTokens.buttonHeightAt(constraints.maxWidth);
    return SizedBox(height:minHeight,child:ElevatedButton(
      onPressed:onPressed,child:icon==null
        ? Text(label,maxLines:2,overflow:TextOverflow.ellipsis,textAlign:TextAlign.center)
        : Wrap(alignment:WrapAlignment.center,crossAxisAlignment:WrapCrossAlignment.center,
          spacing:FableGeneratedTokens.space8,children:[
          Icon(icon,size:FableComponentTokens.iconMedium),
          Text(label,maxLines:2,overflow:TextOverflow.ellipsis),
        ])));
  });
}

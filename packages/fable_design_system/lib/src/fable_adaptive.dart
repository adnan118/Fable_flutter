import 'package:material_ui/material_ui.dart';
import 'tokens.g.dart';

/// Responds to available *content width*, not device names or orientation.
enum FableWindowClass { compact, medium, expanded, large }

abstract final class FableAdaptive {
  static FableWindowClass fromWidth(double width) {
    assert(width >= 0, 'Available width must be non-negative');
    if (width < FableGeneratedTokens.breakpointCompact) return FableWindowClass.compact;
    if (width < FableGeneratedTokens.breakpointMedium) return FableWindowClass.medium;
    if (width < FableGeneratedTokens.breakpointExpanded) return FableWindowClass.expanded;
    return FableWindowClass.large;
  }

  /// Uses nearest LayoutBuilder constraints to support split-screen and foldables.
  static T pick<T>(double width, {required T compact, T? medium, T? expanded, T? large}) {
    switch (fromWidth(width)) {
      case FableWindowClass.large: return large ?? expanded ?? medium ?? compact;
      case FableWindowClass.expanded: return expanded ?? medium ?? compact;
      case FableWindowClass.medium: return medium ?? compact;
      case FableWindowClass.compact: return compact;
    }
  }
  static double spacing(double width, {double compact = FableGeneratedTokens.space16}) =>
      pick(width, compact:compact, medium:compact*1.125, expanded:compact*1.25, large:compact*1.5);
}

class FableAdaptiveBuilder extends StatelessWidget {
  const FableAdaptiveBuilder({super.key, required this.builder});
  final Widget Function(BuildContext context, BoxConstraints constraints, FableWindowClass size) builder;
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder:(context,constraints) =>
      builder(context,constraints,FableAdaptive.fromWidth(constraints.maxWidth.isFinite
          ? constraints.maxWidth : MediaQuery.sizeOf(context).width)));
}

/// Font sizing is logical pixels; Flutter's TextScaler handles accessibility.
/// Do not multiply these values by MediaQuery.textScaler a second time.
enum FableTextRole { display, headline, title, body, label, caption }

abstract final class FableAdaptiveTypography {
  static double size(FableTextRole role, double width) {
    final value = switch(role) {
      FableTextRole.display => FableGeneratedTokens.typeDisplay,
      FableTextRole.headline => FableGeneratedTokens.typeHeadline,
      FableTextRole.title => FableGeneratedTokens.typeTitle,
      FableTextRole.body => FableGeneratedTokens.typeBody,
      FableTextRole.label => FableGeneratedTokens.typeLabel,
      FableTextRole.caption => FableGeneratedTokens.typeCaption,
    };
    return FableAdaptive.pick(width,compact:value,medium:value*1.08,expanded:value*1.16,large:value*1.25);
  }
  static TextStyle style(BuildContext context, FableTextRole role, {Color? color, FontWeight? weight}) {
    return TextStyle(fontSize:size(role,MediaQuery.sizeOf(context).width),color:color,fontWeight:weight);
  }
}

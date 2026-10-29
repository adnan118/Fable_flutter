import 'package:material_ui/material_ui.dart';

/// Light/Dark surface and content roles resolve from ColorScheme; never use
/// success/error colors as arbitrary background or brand colors.
@immutable
class FableUiColors extends ThemeExtension<FableUiColors> {
  const FableUiColors({required this.background,required this.surface,
    required this.surfaceVariant,required this.border,required this.textPrimary,
    required this.textSecondary,required this.textInverse});
  final Color background,surface,surfaceVariant,border,textPrimary,textSecondary,textInverse;
  factory FableUiColors.fromScheme(ColorScheme scheme) => FableUiColors(
    background:scheme.surface, surface:scheme.surfaceContainerLow,
    surfaceVariant:scheme.surfaceContainerHighest, border:scheme.outlineVariant,
    textPrimary:scheme.onSurface,textSecondary:scheme.onSurfaceVariant,
    textInverse:scheme.onPrimary);
  @override
  FableUiColors copyWith({Color? background,Color? surface,Color? surfaceVariant,
    Color? border,Color? textPrimary,Color? textSecondary,Color? textInverse}) => FableUiColors(
      background:background??this.background,surface:surface??this.surface,
      surfaceVariant:surfaceVariant??this.surfaceVariant,border:border??this.border,
      textPrimary:textPrimary??this.textPrimary,textSecondary:textSecondary??this.textSecondary,
      textInverse:textInverse??this.textInverse);
  @override
  FableUiColors lerp(ThemeExtension<FableUiColors>? other,double t) {
    if(other is! FableUiColors)return this;
    return FableUiColors(background:Color.lerp(background,other.background,t)!,
      surface:Color.lerp(surface,other.surface,t)!,
      surfaceVariant:Color.lerp(surfaceVariant,other.surfaceVariant,t)!,
      border:Color.lerp(border,other.border,t)!,
      textPrimary:Color.lerp(textPrimary,other.textPrimary,t)!,
      textSecondary:Color.lerp(textSecondary,other.textSecondary,t)!,
      textInverse:Color.lerp(textInverse,other.textInverse,t)!);
  }
}

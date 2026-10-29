export 'src/fable_async_action_button.dart';
import 'package:material_ui/material_ui.dart';
import 'src/tokens.g.dart';
import 'src/fable_adaptive.dart';
import 'src/fable_component_tokens.dart';
import 'src/fable_ui_colors.dart';

export 'src/fable_adaptive.dart';
export 'src/fable_component_tokens.dart';
export 'src/fable_ui_colors.dart';
export 'src/fable_state_view.dart';

/// Named brand colors are independent of semantic feedback colors.
/// Additional color keys are application-defined (e.g., promotion, loyalty).
@immutable
class FableBrandPalette extends ThemeExtension<FableBrandPalette> {
  const FableBrandPalette({required this.primary,this.secondary,this.tertiary,this.accent,
    this.additional=const <String,Color>{}});
  final Color primary;
  final Color? secondary,tertiary,accent;
  final Map<String,Color> additional;

  Color? colorFor(String role) {
    switch(role){
      case 'primary':return primary;
      case 'secondary':return secondary;
      case 'tertiary':return tertiary;
      case 'accent':return accent;
      default:return additional[role];
    }
  }
  @override
  FableBrandPalette copyWith({Color? primary,Color? secondary,Color? tertiary,Color? accent,
    Map<String,Color>? additional}) => FableBrandPalette(
      primary:primary??this.primary,secondary:secondary??this.secondary,
      tertiary:tertiary??this.tertiary,accent:accent??this.accent,
      additional:additional??this.additional);
  static Color? _mix(Color? left,Color? right,double t) =>
    left==null||right==null ? (t<0.5?left:right) : Color.lerp(left,right,t);
  @override
  FableBrandPalette lerp(ThemeExtension<FableBrandPalette>? other,double t){
    if(other is! FableBrandPalette)return this;
    final extras=<String,Color>{};
    for(final key in {...additional.keys,...other.additional.keys}){
      final merged=_mix(additional[key],other.additional[key],t);
      if(merged!=null)extras[key]=merged;
    }
    return FableBrandPalette(primary:Color.lerp(primary,other.primary,t)!,
      secondary:_mix(secondary,other.secondary,t),
      tertiary:_mix(tertiary,other.tertiary,t),
      accent:_mix(accent,other.accent,t),additional:extras);
  }
}

/// Status tokens remain available even when a project has no brand manifest.
/// Use icon/text plus color for accessibility, not color alone.
@immutable
class FableSemanticColors extends ThemeExtension<FableSemanticColors> {
  const FableSemanticColors({required this.success,required this.error,
    required this.warning,required this.info});
  final Color success,error,warning,info;
  static const defaults=FableSemanticColors(
    success:Color(0xFF15803D),error:Color(0xFFB91C1C),
    warning:Color(0xFFB45309),info:Color(0xFF1D4ED8));

  /// Selects a readable black/white foreground (WCAG contrast for an opaque background).
  static Color onColor(Color background) => background.computeLuminance()>0.179
    ? const Color(0xFF000000) : const Color(0xFFFFFFFF);
  Color get onSuccess=>onColor(success);
  Color get onError=>onColor(error);
  Color get onWarning=>onColor(warning);
  Color get onInfo=>onColor(info);
  @override
  FableSemanticColors copyWith({Color? success,Color? error,Color? warning,Color? info})=>
    FableSemanticColors(success:success??this.success,error:error??this.error,
      warning:warning??this.warning,info:info??this.info);
  @override
  FableSemanticColors lerp(ThemeExtension<FableSemanticColors>? other,double t){
    if(other is! FableSemanticColors)return this;
    return FableSemanticColors(success:Color.lerp(success,other.success,t)!,
      error:Color.lerp(error,other.error,t)!,
      warning:Color.lerp(warning,other.warning,t)!,
      info:Color.lerp(info,other.info,t)!);
  }
}

/// Mirrors mobile/design-tokens.tokens.json (DTCG shape).
abstract final class FableTokens {
  static const Color brand=FableGeneratedTokens.brand;
  static const Color ink=FableGeneratedTokens.ink;
  static const Color secondary=FableGeneratedTokens.secondary;
  static const double space4=FableGeneratedTokens.space4;
  static const double space2=FableGeneratedTokens.spaceXxs;
  static const double space48=FableGeneratedTokens.spaceXxxl;
  static const double space8=FableGeneratedTokens.space8;
  static const double space16=FableGeneratedTokens.space16;
  static const double space24=FableGeneratedTokens.space24;
  static const double space32=FableGeneratedTokens.space32;
  static const double radius8=FableGeneratedTokens.radius8;
  static const double radius4=FableGeneratedTokens.radiusXs;
  static const double radius28=FableGeneratedTokens.radiusXl;
  static const double radius12=FableGeneratedTokens.radius12;
  static const double radius20=FableGeneratedTokens.radius20;
  static const Duration motionQuick=FableGeneratedTokens.quick;
  static const Duration motionStandard=FableGeneratedTokens.standard;
  static ThemeData theme(Brightness brightness, {Color? seedColor,
    FableBrandPalette? brandPalette,FableSemanticColors? semanticColors,
    String? fontFamily}){
    final palette=brandPalette ?? FableBrandPalette(primary:seedColor??brand);
    final feedback=semanticColors??FableSemanticColors.defaults;
    final base=ColorScheme.fromSeed(seedColor:seedColor??palette.primary,brightness:brightness);
    final colors=base.copyWith(
      secondary:palette.secondary??base.secondary,
      onSecondary:palette.secondary==null?base.onSecondary:FableSemanticColors.onColor(palette.secondary!),
      tertiary:palette.tertiary??base.tertiary,
      onTertiary:palette.tertiary==null?base.onTertiary:FableSemanticColors.onColor(palette.tertiary!),
      error:feedback.error,onError:feedback.onError,
    );
    final ui=FableUiColors.fromScheme(colors);
    final textTheme=TextTheme(
      displayLarge:TextStyle(fontFamily:fontFamily,fontSize:FableGeneratedTokens.typeDisplay,fontWeight:FontWeight.w700,color:ui.textPrimary),
      headlineMedium:TextStyle(fontFamily:fontFamily,fontSize:FableGeneratedTokens.typeHeadline,fontWeight:FontWeight.w700,color:ui.textPrimary),
      titleLarge:TextStyle(fontFamily:fontFamily,fontSize:FableGeneratedTokens.typeTitle,fontWeight:FontWeight.w600,color:ui.textPrimary),
      bodyMedium:TextStyle(fontFamily:fontFamily,fontSize:FableGeneratedTokens.typeBody,color:ui.textPrimary),
      labelLarge:TextStyle(fontFamily:fontFamily,fontSize:FableGeneratedTokens.typeLabel,fontWeight:FontWeight.w600,color:ui.textPrimary),
      bodySmall:TextStyle(fontFamily:fontFamily,fontSize:FableGeneratedTokens.typeCaption,color:ui.textSecondary),
    );
    return ThemeData(useMaterial3:true,colorScheme:colors,
      fontFamily:fontFamily,textTheme:textTheme,
      extensions:<ThemeExtension<dynamic>>[palette,feedback,ui],
      scaffoldBackgroundColor:colors.surface,
      appBarTheme:const AppBarTheme(centerTitle:false),
      inputDecorationTheme:InputDecorationTheme(
        contentPadding:const EdgeInsets.symmetric(horizontal:FableGeneratedTokens.space16,vertical:FableGeneratedTokens.space16),
        border:OutlineInputBorder(borderRadius:BorderRadius.circular(radius12))),
      elevatedButtonTheme:ElevatedButtonThemeData(style:ElevatedButton.styleFrom(
        minimumSize:const Size(0,FableComponentTokens.buttonHeight),
        shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(radius12)))),
      outlinedButtonTheme:OutlinedButtonThemeData(style:OutlinedButton.styleFrom(
        minimumSize:const Size(0,FableComponentTokens.buttonHeight),
        shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(radius12)))),
      cardTheme:CardThemeData(shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(radius20))),
      visualDensity:VisualDensity.standard);
  }
}
class FableSkeleton extends StatefulWidget {
  const FableSkeleton({super.key,required this.height,this.width=double.infinity});
  final double height,width;
  @override State<FableSkeleton> createState()=>_FableSkeletonState();
}
class _FableSkeletonState extends State<FableSkeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _animation=AnimationController(vsync:this,duration:const Duration(milliseconds:1100))..repeat(reverse:true);
  @override void dispose(){_animation.dispose();super.dispose();}
  @override Widget build(BuildContext context){
    final reduce=MediaQuery.disableAnimationsOf(context);
    if(reduce)return _shape(context,0.22);
    return AnimatedBuilder(animation:_animation,builder:(context,_)=>_shape(context,0.12+0.12*_animation.value));
  }
  Widget _shape(BuildContext context,double opacity)=>Semantics(label:'Loading',child:Container(
    width:widget.width,height:widget.height,
    decoration:BoxDecoration(color:Theme.of(context).colorScheme.onSurface.withValues(alpha:opacity),
      borderRadius:BorderRadius.circular(FableTokens.radius12))));
}
class FableAsyncContent<T> extends StatelessWidget {
  const FableAsyncContent({super.key,required this.data,required this.builder,required this.retry});
  final Future<T> data;final Widget Function(BuildContext,T) builder;final VoidCallback retry;
  @override Widget build(BuildContext context)=>FutureBuilder<T>(future:data,builder:(context,snapshot){
    if(snapshot.connectionState!=ConnectionState.done)return const FableSkeleton(height:130);
    if(snapshot.hasError)return Center(child:Column(mainAxisSize:MainAxisSize.min,children:[
      const Text('Could not load'),TextButton(onPressed:retry,child:const Text('Retry'))]));
    final result=snapshot.data;if(result==null)return const Center(child:Text('No data'));
    return builder(context,result);
  });
}

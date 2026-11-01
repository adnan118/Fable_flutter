import 'package:flutter/widgets.dart';

/// An application-owned locale selection hook exposed to optional feature
/// screens. Does not assume any Fable/Other Backend language endpoint.
/// Selecting a language is only enabled for a bundled, wizard-approved tag.
class FableAppLocaleScope extends InheritedWidget {
 const FableAppLocaleScope({
  super.key,required this.allowedTags,required this.selectedTag,
  required this.onSelect,required super.child,
 });
 final List<String> allowedTags;
 /// Null means follow the device locale, not the first Backend language.
 final String? selectedTag;
 final void Function(String? tag) onSelect;
 bool supports(String tag)=>allowedTags.contains(tag);
 static FableAppLocaleScope? maybeOf(BuildContext context)=>
   context.dependOnInheritedWidgetOfExactType<FableAppLocaleScope>();
 @override bool updateShouldNotify(covariant FableAppLocaleScope old)=>
   selectedTag!=old.selectedTag ||
   !listEquals(allowedTags,old.allowedTags) ||
   !identical(onSelect,old.onSelect);
 static bool listEquals(List<String> a,List<String> b){
  if(identical(a,b))return true;
  if(a.length!=b.length)return false;
  for(var i=0;i<a.length;i++)if(a[i]!=b[i])return false;
  return true;
 }
}

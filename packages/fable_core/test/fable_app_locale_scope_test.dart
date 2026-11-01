import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fable_core/fable_core.dart';

void main(){
 testWidgets('only wizard-approved bundled languages may be selected by a feature screen',
 (tester)async{
  String? requested='unset';
  await tester.pumpWidget(MaterialApp(home:FableAppLocaleScope(
    allowedTags:const ['ar','en'],selectedTag:'ar',
    onSelect:(tag)=>requested=tag,
    child:Builder(builder:(context){
      final scope=FableAppLocaleScope.maybeOf(context)!;
      return Column(children:[
        Text(scope.selectedTag??'device'),
        for(final value in ['ar','en','de'])
          TextButton(onPressed:scope.supports(value)
            ?()=>scope.onSelect(value):null,child:Text(value)),
        TextButton(onPressed:()=>scope.onSelect(null),
          child:const Text('device')),
      ]);
    }),
  )));
  expect(find.text('ar'),findsWidgets);
  await tester.tap(find.widgetWithText(TextButton,'en'));
  expect(requested,'en');
  expect(tester.widget<TextButton>(
    find.widgetWithText(TextButton,'de')).onPressed,isNull);
  await tester.tap(find.widgetWithText(TextButton,'device'));
  expect(requested,isNull);
 });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fable_content/fable_content.dart';

Map<String,Object?> doc(String value)=>{'type':'doc','content':[
  {'type':'paragraph','content':[{'type':'text','text':value}]}
]};

void main(){
 test('Backend structured rich text v2 displays nested paragraphs and marks',(){
  final rich={'type':'doc','content':[
   {'type':'paragraph','content':[
    {'type':'text','text':'سياسة الخصوصية','marks':[{'type':'bold'}]},
    {'type':'hardBreak'},
    {'type':'text','text':'Privacy policy','marks':[{'type':'italic'}]},
   ]},
   {'type':'orderedList','content':[
    {'type':'listItem','content':[{'type':'paragraph','content':[
     {'type':'text','text':'One'}]}]},
    {'type':'listItem','content':[{'type':'paragraph','content':[
     {'type':'text','text':'Two'}]}]},
   ]},
  ]};
  final text=FableStructuredText.parse(rich).toPlainText();
  expect(text,contains('سياسة الخصوصية'));
  expect(text,contains('Privacy policy'));
  expect(text,contains('1. One'));
  expect(text,contains('2. Two'));
 });
 test('Unsupported nodes and oversized nested structures fail closed',(){
  expect(()=>FableStructuredText.parse({'type':'script','text':'evil'}),
    throwsFormatException);
  expect(()=>FableStructuredText.parse({'type':'doc','content':[
   {'type':'paragraph','content':[{'type':'text','text':List.filled(20001,'a').join()}]}
  ]}),throwsFormatException);
  final nested={'type':'doc','content':[
   {'type':'paragraph','content':[{'type':'text','text':'tiny'}]}
  ]};
  Object? value=nested;
  for(var i=0;i<13;i++)value={'type':'doc','content':[value]};
  expect(()=>FableStructuredText.parse(value),throwsFormatException);
 });
 testWidgets('legal template paragraph and notice show structured content instead of empty text',
 (tester) async{
  const legalTitle='Policy title';
  final blocks=[
   FableContentBlock(id:'a',type:'heading',data:{'text':legalTitle,'level':'1'}),
   FableContentBlock(id:'b',type:'paragraph',data:{'content':doc('Personal information')}),
   FableContentBlock(id:'c',type:'notice',data:{
    'title':'Important','variant':'warning','content':doc('Your rights')}),
   FableContentBlock(id:'d',type:'rich-text',data:{'document':doc('Structured copy')}),
  ];
  await tester.pumpWidget(MaterialApp(home:Scaffold(body:SingleChildScrollView(
   child:Column(children:[for(final block in blocks)
    FablePublishedBlockView(block:block)]),
  ))));
  expect(find.text(legalTitle),findsOneWidget);
  expect(find.textContaining('Personal information'),findsOneWidget);
  expect(find.textContaining('Your rights'),findsOneWidget);
  expect(find.textContaining('Structured copy'),findsOneWidget);
 });
 testWidgets('unverified CTA cannot navigate and media is not invented',(tester)async{
  await tester.pumpWidget(const MaterialApp(home:Scaffold(body:Column(children:[
   FablePublishedBlockView(block:FableContentBlock(
    id:'button1',type:'button',data:{'label':'Open unsafe URL','url':'https://untrusted.invalid'})),
   FablePublishedBlockView(block:FableContentBlock(
    id:'image1',type:'image',data:{'mediaId':'unverified-id','alt':'Unknown'})),
  ]))));
  final btn=tester.widget<OutlinedButton>(
   find.widgetWithText(OutlinedButton,'Open unsafe URL'));
  expect(btn.onPressed,isNull);
  expect(find.textContaining('requires verified integration'),findsOneWidget);
 });
}

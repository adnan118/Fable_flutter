import 'package:material_ui/material_ui.dart';

/// A bounded, inert renderer for Fable ContentEditorSchemaService richText v2.
/// It deliberately never interprets HTML and never follows links from content.
class FableStructuredText {
 FableStructuredText._();
 static const allowedNodes=<String>{
  'doc','paragraph','heading','bulletList','orderedList',
  'listItem','blockquote','hardBreak','text',
 };
 static const allowedMarks=<String>{'bold','italic','underline','strike','link'};
 static TextSpan parse(Object? payload){
  final buffer=<InlineSpan>[];
  var count=0,chars=0;
  void emit(String value,[TextStyle? style]){
   chars+=value.length;
   if(chars>20000)throw const FormatException('Published rich text exceeds display limit');
   buffer.add(TextSpan(text:value,style:style));
  }
  void visit(Object? raw,int depth,{int? listIndex}){
   if(++count>1000||depth>12)
    throw const FormatException('Published rich text structure too deep or large');
   if(raw is! Map||raw['type'] is! String)
    throw const FormatException('Invalid rich text node');
   final type=raw['type'] as String;
   if(!allowedNodes.contains(type))throw const FormatException('Unverified rich text node');
   final content=raw['content'];
   if(content!=null&&(content is! List||content.length>250))
    throw const FormatException('Invalid rich text children');
   if(type=='text'){
    final text=raw['text'];
    if(text is! String)throw const FormatException('Invalid text node');
    var style=const TextStyle();
    final marks=raw['marks'];
    if(marks!=null){
     if(marks is! List||marks.length>8)throw const FormatException('Invalid text marks');
     for(final m in marks){
      if(m is! Map||m['type'] is! String||!allowedMarks.contains(m['type']))
       throw const FormatException('Unknown text mark');
      final mark=m['type'];
      if(mark=='bold')style=style.copyWith(fontWeight:FontWeight.bold);
      if(mark=='italic')style=style.copyWith(fontStyle:FontStyle.italic);
      if(mark=='underline'||mark=='link')
       style=style.copyWith(decoration:TextDecoration.underline);
      if(mark=='strike')style=style.copyWith(decoration:TextDecoration.lineThrough);
      // Link marks are rendered as inert styled text. No untrusted navigation.
     }
    }
    emit(text,style);
    return;
   }
   if(type=='hardBreak'){emit('\n');return;}
   if(type=='listItem')emit(listIndex==null?'• ':'$listIndex. ');
   if(type=='blockquote')emit('“');
   if(content is List){
    for(var i=0;i<content.length;i++){
     visit(content[i],depth+1,listIndex:
       type=='orderedList'?i+1:type=='bulletList'?null:null);
    }
   }
   if(type=='paragraph'||type=='heading'||type=='listItem'||type=='blockquote')
    emit(type=='blockquote'?'”\n':'\n');
  }
  visit(payload,1);
  return TextSpan(children:List.unmodifiable(buffer));
 }
}

class FableStructuredTextView extends StatelessWidget {
 const FableStructuredTextView({super.key,required this.payload});
 final Object? payload;
 @override Widget build(BuildContext context){
  final value=payload;
  if(value is String&&value.length<=20000)return Text(value);
  try {
   final parsed=FableStructuredText.parse(value);
   return Text.rich(parsed);
  }catch(_){
   final ar=Localizations.maybeLocaleOf(context)?.languageCode=='ar';
   return Text(ar?'تعذر عرض هذا المحتوى المنسّق بأمان.':
      'Published rich text could not be displayed safely.');
  }
 }
}

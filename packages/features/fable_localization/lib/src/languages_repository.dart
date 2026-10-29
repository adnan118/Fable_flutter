import 'package:fable_core/fable_core.dart';
class FableLanguage {
 const FableLanguage({required this.code,required this.name,required this.isDefault});
 final String code,name;final bool isDefault;
 static FableLanguage parse(Object? raw){
  if(raw is! Map)throw const FormatException('Language must be an object');
  final code=raw['code'],name=raw['nativeName']??raw['name'];
  if(code is! String||!RegExp(r'^[a-z]{2,3}(?:-[A-Za-z0-9]{2,8}){0,3}$').hasMatch(code)||
    name is! String || name.trim().isEmpty || name.length>100){
   throw const FormatException('Invalid language response');
  }
  return FableLanguage(code:code,name:name,isDefault:raw['isDefault']==true);
 }
}
class FableLanguagesRepository {
 const FableLanguagesRepository(this.gateway);
 final BackendApiGateway gateway;
 Future<List<FableLanguage>> list() async {
  final response=await gateway.execute('languages.list');
  final payload=response.data;
  if(payload is! List||payload.length>200)throw const FormatException('Invalid language catalog');
  return List.unmodifiable(payload.map(FableLanguage.parse));
 }
}

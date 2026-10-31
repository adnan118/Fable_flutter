/// Only Fable's signed inbox can surface these account-security actions.
/// No untrusted URL, JavaScript, deep link, privileged API operation, or
/// password is accepted from the notification payload.
class FableSecurityNoticeAction {
  const FableSecurityNoticeAction(this.id,this.kind,{this.route});
  final String id,kind;
  final String? route;
}
bool isSafeInternalPasswordRoute(Object? candidate){
  if(candidate is! String||candidate.length>240||!candidate.startsWith('/')||
     candidate.startsWith('//')||candidate.contains('..')||
     candidate.contains('?')||candidate.contains('#')||
     !RegExp(r'^/[a-zA-Z0-9_/-]+$').hasMatch(candidate)||
     !candidate.contains('password'))return false;
  return true;
}
List<FableSecurityNoticeAction> readFableSecurityActions(Object? raw,{
  required String notificationId,required bool isFable,
}){
  if(!isFable||raw is! Map ||raw['kind']!='AUTH_FAILED_LIMIT'||
    raw['noticeId']!=notificationId)return const [];
  final actions=raw['actions'];
  if(actions is! List || actions.length>2)return const [];
  final output=<FableSecurityNoticeAction>[],seen=<String>{};
  for(final action in actions){
    if(action is! Map)return const [];
    final id=action['id'],kind=action['kind'];
    if(id is! String||kind is! String||!seen.add(id))return const [];
    if(id=='THIS_WAS_ME'&&kind=='acknowledge-only'){
      output.add(const FableSecurityNoticeAction('THIS_WAS_ME','acknowledge-only'));
    }else if(id=='RESET_PASSWORD'&&kind=='internal-route'&&
      isSafeInternalPasswordRoute(action['route'])){
      output.add(FableSecurityNoticeAction(id,kind,route:action['route'] as String));
    }else return const [];
  }
  return List.unmodifiable(output);
}

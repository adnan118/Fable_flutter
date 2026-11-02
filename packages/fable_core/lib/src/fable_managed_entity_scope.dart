import 'dart:async';
import 'package:flutter/widgets.dart';
import 'fable_session.dart';

/// تلميح سياق للواجهة فقط، يأتي من اختيار مؤكّد من خادم Fable.
/// ليس تفويضاً؛ الخادم يتحقق من العضوية والصلاحيات عند كل طلب.
/// لا تُحقن ترويسة الكيان تلقائياً في جميع الطلبات.
/// راجع docs/integrations/FABLE-FLUTTER-PARITY-MASTER.ar.md
class FableManagedEntitySelection {
 const FableManagedEntitySelection({
  required this.id,required this.access,required this.nameAr,
  required this.nameEn,required this.identityRevision,
 });
 final String id,access,nameAr,nameEn;
 final int identityRevision;
}

/// Volatile selection; intentionally never stored in preferences or sent to
/// unrelated API operations. Identity changes revoke it synchronously.
class FableManagedEntityStore extends ChangeNotifier {
 FableManagedEntityStore({FableSecureSession? session}):
   _session=session??FableSecureSession(){
   _identityEvents=_session.identityEvents.listen((_)=>clear());
 }
 final FableSecureSession _session;
 late final StreamSubscription<FableIdentityEvent> _identityEvents;
 FableManagedEntitySelection? _active;
 String? _backendIdentity;
 int _selectionRevision = 0;
 /// Changes on each activation/clear, including an A → B → A switch.
 /// Lets callers discard late responses without storing roles or secrets.
 int get selectionRevision => _selectionRevision;
 bool isBoundToCredentials(FableSecureSession credentials) =>
   identical(credentials, _session);
 static final _uuid=RegExp(
   r'^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$',
   caseSensitive:false);
 bool get bound =>_backendIdentity!=null;
 void bindBackend(String identity){
   if(identity.trim().isEmpty||identity.length>1024)
     throw ArgumentError('Invalid authenticated Backend identity');
   if(_backendIdentity==identity)return;
   _backendIdentity=identity;
   clear();
 }
 FableManagedEntitySelection? get selected{
   final current=_active;
   return current!=null&&_backendIdentity!=null&&
       current.identityRevision==_session.identityRevision?current:null;
 }
 void activate(FableManagedEntitySelection choice){
   if(_backendIdentity==null||
      choice.identityRevision!=_session.identityRevision)
     throw StateError('Verified entity selection belongs to another Backend or user');
   if(!_uuid.hasMatch(choice.id)||
      !const {'OWNER','MANAGER','VIEWER'}.contains(choice.access)||
      choice.nameAr.isEmpty||choice.nameEn.isEmpty||
      choice.nameAr.length>191||choice.nameEn.length>191)
     throw const FormatException('Invalid managed entity activation result');
   _active=choice;
   _selectionRevision++;
   notifyListeners();
 }
 void clear(){
   if(_active==null)return;
   _active=null;
   _selectionRevision++;
   notifyListeners();
 }
 @override void dispose(){
   unawaited(_identityEvents.cancel());
   super.dispose();
 }
}

/// Feature pages can read the selected Fable entity but must explicitly use
/// a contract-verified, entity-aware repository for scoped requests.
class FableManagedEntityScope extends InheritedNotifier<FableManagedEntityStore>{
 const FableManagedEntityScope({
   super.key,required FableManagedEntityStore store,required super.child,
 }):super(notifier:store);
 static FableManagedEntityStore? maybeOf(BuildContext context)=>
   context.dependOnInheritedWidgetOfExactType<FableManagedEntityScope>()?.notifier;
}

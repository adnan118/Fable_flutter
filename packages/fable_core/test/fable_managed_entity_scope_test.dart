import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fable_core/fable_core.dart';

class _Session extends FableSecureSession {
 _Session(this.events);
 final StreamController<FableIdentityEvent> events;
 int revision=0;
 @override int get identityRevision=>revision;
 @override Stream<FableIdentityEvent> get identityEvents=>events.stream;
 void changeIdentity(){
   revision++;
   events.add(FableIdentityEvent(revision,true));
 }
}
const choice=FableManagedEntitySelection(
 id:'550e8400-e29b-41d4-a716-446655440001',access:'MANAGER',
 nameAr:'كيان',nameEn:'Entity',identityRevision:0,
);
void main(){
 test('managed entity selection requires Fable binding and exact identity epoch',()async{
  final eventStream=StreamController<FableIdentityEvent>.broadcast(sync:true);
  final session=_Session(eventStream);
  final store=FableManagedEntityStore(session:session);
  addTearDown(()async{store.dispose();await eventStream.close();});
  expect(store.selected,isNull);
  expect(()=>store.activate(choice),throwsStateError);
  store.bindBackend('fable-contract-hash|https://api.example.test');
  store.activate(choice);
  expect(store.selected?.access,'MANAGER');
  expect(store.selected?.id,choice.id);
  store.bindBackend('different-contract|https://api.example.test');
  expect(store.selected,isNull);
  store.bindBackend('fable-contract-hash|https://api.example.test');
  store.activate(choice);
  session.changeIdentity();
  expect(store.selected,isNull);
  expect(()=>store.activate(choice),throwsStateError);
 });
 test('role/identity input validation never grants a forged entity',()async{
  final events=StreamController<FableIdentityEvent>.broadcast(sync:true);
  final store=FableManagedEntityStore(session:_Session(events));
  addTearDown(()async{store.dispose();await events.close();});
  store.bindBackend('fable|https://api.example.test');
  expect(()=>store.activate(const FableManagedEntitySelection(
    id:'../profile',access:'OWNER',nameAr:'A',nameEn:'B',identityRevision:0)),
    throwsFormatException);
  expect(()=>store.activate(const FableManagedEntitySelection(
    id:'550e8400-e29b-41d4-a716-446655440001',access:'ADMIN',
    nameAr:'A',nameEn:'B',identityRevision:0)),throwsFormatException);
  expect(store.selected,isNull);
 });
 testWidgets('scope notifies project UI when entity is selected and cleared',
 (tester)async{
  final events=StreamController<FableIdentityEvent>.broadcast(sync:true);
  final store=FableManagedEntityStore(session:_Session(events));
  addTearDown(()async{store.dispose();await events.close();});
  store.bindBackend('fable|https://api.example.test');
  await tester.pumpWidget(MaterialApp(home:FableManagedEntityScope(
    store:store,child:Builder(builder:(context){
      final current=FableManagedEntityScope.maybeOf(context)!.selected;
      return Text(current?.nameEn??'No entity');
    }))));
  expect(find.text('No entity'),findsOneWidget);
  store.activate(choice);
  await tester.pump();
  expect(find.text('Entity'),findsOneWidget);
  store.clear();
  await tester.pump();
  expect(find.text('No entity'),findsOneWidget);
 });
}

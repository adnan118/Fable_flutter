import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:fable_notifications/fable_notifications.dart';

void main(){
 final nav=FableNotificationNavigation.instance;
 tearDown(nav.reset);
 test('push without destination falls back to inbox', () async {
   final routes=<String>[];
   nav.navigateCapability=(id,_)async {routes.add(id);return true;};
   expect(await nav.open({}),true);
   expect(routes,['notifications']);
 });
 test('verified app destination opens only known capability', () async {
   final routes=<String>[];
   nav.navigateCapability=(id,_)async {
     routes.add(id);return id=='content' || id=='notifications';
   };
   expect(await nav.open({'target':'content'}),true);
   expect(routes,['content']);
   expect(await nav.open({'target':'not_installed'}),true);
   expect(routes.last,'notifications');
 });
 test('unverified HTTP URLs fall back to inbox',()async{
   var unsafeCalled=false;
   nav.navigateVerifiedUrl=(url)async{unsafeCalled=true;return true;};
   nav.navigateCapability=(id,_)async=>id=='notifications';
   expect(await nav.open({'url':'http://example.com/admin'}),true);
   expect(unsafeCalled,false);
 });
 test('session deferral resumes on login; clearing pending blocks old session',()async{
   var loggedIn=false;
   nav.isAuthenticated=()async=>loggedIn;
   final routes=<String>[];
   nav.navigateCapability=(id,_)async{routes.add(id);return true;};
   expect(await nav.open({'target':'profile'}),false);
   expect(nav.hasPending,true);
   loggedIn=true;
   expect(await nav.resumeAfterLogin(),true);
   expect(routes,['profile']);
   loggedIn=false;
   expect(await nav.open({'target':'content'}),false);
   nav.clearPending();
   loggedIn=true;
   expect(await nav.resumeAfterLogin(),false);
   expect(routes,['profile']);
 });
 test('stale permission check cannot open earlier notification',()async{
   final older=Completer<bool>();
   final routes=<String>[];
   var calls=0;
   nav.isAuthenticated=(){calls++;return calls==1?older.future:Future.value(true);};
   nav.navigateCapability=(id,_)async{routes.add(id);return true;};
   final old=nav.open({'target':'content'});
   final next=nav.open({'target':'profile'});
   expect(await next,true);
   older.complete(true);
   expect(await old,false);
   expect(routes,['profile']);
 });
 test('inbox preserves only bounded navigation metadata',(){
  final item=FableInboxItem.fromPayload({
   'id':'01234567-89ab-cdef-0123-456789abcdef',
   'title':'Example','body':'View update',
   'data':{'route':'content','url':'https://links.example.com/content/2','secret':1234},
  });
  expect(item.data['route'],'content');
  expect(item.data.containsKey('secret'),false);
 });
}

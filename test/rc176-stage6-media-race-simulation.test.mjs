import test from 'node:test';
import assert from 'node:assert/strict';
import {SimulatedFableServer,SimulatedFlutterClient}
 from '../tools/rc175-stage6-dpop-auth-simulator.mjs';

const setup=()=>{
 const server=new SimulatedFableServer(),client=new SimulatedFlutterClient(server);
 client.login('user-A');
 server.putMedia('file-a','user-A','synthetic-secret');
 server.setGrants('user-A',['media.access','media.read']);
 return {server,client};
};
const pause=()=>{
 let release;
 return {hold:new Promise(resolve=>{release=resolve}),resume:()=>release()};
};
test('RC176 01 permission revoke before pending media response denies bytes',async()=>{
 const {server,client}=setup(),p=pause();
 const pending=client.readMedia('file-a',p.hold);
 server.setGrants('user-A',[]);p.resume();
 await assert.rejects(pending,/MEDIA_FORBIDDEN/);
});
test('RC176 02 logout while media pending invalidates the old read',async()=>{
 const {client}=setup(),p=pause();
 const pending=client.readMedia('file-a',p.hold);
 client.logout();p.resume();
 await assert.rejects(pending,/STALE_IDENTITY/);
});
test('RC176 03 A to B to A race never accepts an earlier A result',async()=>{
 const {client}=setup(),p=pause();
 const pending=client.readMedia('file-a',p.hold);
 client.login('user-B');client.login('user-A');p.resume();
 await assert.rejects(pending,/STALE_IDENTITY/);
});
test('RC176 04 server revocation during pending media blocks response',async()=>{
 const {server,client}=setup(),p=pause(),id=client.session.sessionId;
 const pending=client.readMedia('file-a',p.hold);
 server.revoke(id);p.resume();
 await assert.rejects(pending,/SESSION_UNAUTHORIZED/);
});

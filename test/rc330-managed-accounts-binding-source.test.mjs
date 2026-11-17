import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

const source=readFileSync(new URL(
  '../packages/features/fable_profile/lib/src/managed_accounts_page.dart',
  import.meta.url,
),'utf8');
const section=(from,to)=>source.slice(source.indexOf(from),source.indexOf(to,source.indexOf(from)));

test('RC330 account manager replaces the signed repository and listener on project contract change',()=>{
  assert.ok(source.includes('late FableManagedAccountsRepository _repo;'));
  assert.ok(!source.includes('late final FableManagedAccountsRepository _repo='));
  const rebind=section('didUpdateWidget(covariant FableManagedAccountsPage old)',
    '@override void didChangeAppLifecycleState');
  for(const required of [
    'old.gateway,widget.gateway','old.contract,widget.contract',
    '_bindingEpoch++','_managedStore?.clear()','old.onCleared?.call()',
    '_events?.cancel()','_repo=FableManagedAccountsRepository(widget.gateway,widget.contract)',
    '_entities=null;_invitations=null;_selected=null;_busy=false',
    '_discardLifecycleProof()','_watchIdentity()',
    'WidgetsBinding.instance.addPostFrameCallback',
  ])assert.ok(rebind.includes(required),'missing '+required);
});

test('RC330 pending old-account list and activation cannot be adopted under same numeric session revision',()=>{
  const list=section('Future<void> _reload()async','Future<void> _activate(');
  assert.ok(list.includes('final repo=_repo;'));
  assert.ok(list.includes('final entities=await repo.listMine()'));
  assert.ok(list.includes('identical(repo,_repo)'));
  assert.ok(list.includes('binding!=_bindingEpoch'));
  assert.ok(!list.includes('await _repo.invitationsMine()'));
  const activate=section('Future<void> _activate(', 'Future<bool> _confirm(');
  assert.ok(activate.includes('final binding=_bindingEpoch'));
  assert.ok(activate.includes('binding!=_bindingEpoch'));
  assert.ok(activate.includes('binding==_bindingEpoch'));
});

test('RC330 sensitive managed mutations and OTP cannot resume after gateway replacement',()=>{
  for(const [method,next] of [
    ['_create','_reloadAfterMutation'],['_edit','_invite'],
    ['_invite','_respond'],['_respond','_lifecycleLabel'],
    ['_requestLifecycle','_applyLifecycle'],['_applyLifecycle','@override void dispose'],
  ]){
    const snippet=section('Future<void> '+method+'(',next.startsWith('@')?next:
      next==='_lifecycleLabel'?'String _lifecycleLabel(':
      next==='_reloadAfterMutation'?'Future<void> _reloadAfterMutation(':
      'Future<void> '+next+'(');
    assert.ok(snippet.includes('final binding=_bindingEpoch'),method);
    assert.ok(snippet.includes('binding==_bindingEpoch')||
      snippet.includes('binding!=_bindingEpoch'),method);
  }
  const lifecycle=section('Future<void> _applyLifecycle()', '@override void dispose');
  assert.ok(lifecycle.includes('bool valid()=>binding==_bindingEpoch'));
  assert.ok(lifecycle.includes('contextStillValid:valid'));
});

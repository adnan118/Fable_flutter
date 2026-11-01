import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync,existsSync} from 'node:fs';
import {resolve,dirname} from 'node:path';
import {fileURLToPath} from 'node:url';

const root=resolve(dirname(fileURLToPath(import.meta.url)),'..');
const load=(path)=>readFileSync(resolve(root,path),'utf8');
const shared=JSON.parse(load('docs/integrations/FABLE-BACKEND-WIDE-DECISIONS-RC81.json'));
const auth=JSON.parse(load('docs/integrations/FABLE-AUTH-OPERATIONS-RC80.json'));

test('23 Backend-wide decisions exist without elevating Blueprint to runtime authority',()=>{
 assert.equal(shared.schemaVersion,1);
 assert.equal(shared.decisions.length,23);
 assert.equal(new Set(shared.decisions.map(x=>x.id)).size,23);
 for(const policy of shared.decisions){
   assert.ok(policy.backendSource.startsWith('lib/')||
     policy.backendSource.startsWith('docs/')||
     policy.backendSource.startsWith('src/')||
     policy.backendSource.startsWith('blueprints/'));
   assert.ok(policy.otherBackendRequirement.length>15);
   assert.equal(policy.fullParityVerified,false);
   assert.equal(policy.projectContractVerified,false);
   assert.equal(policy.liveE2EVerified,false);
 }
});
test('Wizard review exposes Fable vs Other policy source and no guessed Fable headers',()=>{
 const wizard=load('tools/flutter-setup-wizard.mjs');
 assert.match(wizard,/سياسات عامة تتجاوز الميزات الفردية/);
 assert.match(wizard,/سياسات جلسات\/OTP\/طرق دخول/);
 assert.match(wizard,/Other Backend: لا ترث أي سياسة من Fable/);
 assert.match(wizard,/لا ننسخ خيارات Redis\/Valkey/);
});
test('Fable password change requires verified operation and clears one identity only',()=>{
 const gateway=load('packages/fable_core/lib/src/fable_auth_gateway.dart');
 const page=load('packages/features/fable_auth/lib/src/change_password_page.dart');
 const login=load('packages/features/fable_auth/lib/src/login_page.dart');
 const changed=auth.operations.find(o=>o.id==='auth.change-password');
 assert.equal(changed.disposition,'SOURCE_IMPLEMENTED_E2E_PENDING');
 assert.equal(changed.realE2EVerified,false);
 assert.match(gateway,/_contract.operations\['auth.change-password'\]/);
 assert.match(gateway,/session.clearSessionIfIdentity\(revision\)/);
 assert.match(gateway,/payload\['changed'\]!=true/);
 assert.match(gateway,/'currentPassword':currentPassword,'newPassword':newPassword/);
 assert.match(page,/Password change could not be confirmed/);
 assert.match(page,/All signed-in devices will be signed out/);
 assert.match(login,/widget.contract.supports\('auth.change-password'\)/);
 for(const path of [...changed.flutterEvidence,...changed.regressionTests])
   assert.equal(existsSync(resolve(root,path)),true);
});
test('Other Backend never receives a fabricated Fable change-password binding',()=>{
 const other=load('packages/fable_core/lib/src/external_auth_gateway.dart');
 assert.doesNotMatch(other,/auth\.change-password/);
 const catalog=load('packages/fable_core/lib/src/external_operation_catalog.dart');
 assert.match(catalog,/operationsHash/);
 assert.match(catalog,/sourceHash/);
});

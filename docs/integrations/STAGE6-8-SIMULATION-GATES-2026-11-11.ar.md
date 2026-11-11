# Fable — المرحلة السادسة: ثماني بوابات قبول بالمحاكاة

**11 نوفمبر 2026 | مسار تطوير فقط | ليس اعتماد تشغيل أو إنتاج**

## قرار الاختبار

بناءً على تعليمات مالك المشروع في 11 نوفمبر، نعتمد محاكاة معزولة ذات اختبارات منفذة بدل انتظار Backend إنتاجي، Android، Xcode، خدمات خارجية أو أجهزة حقيقية. **لا يجوز** تحويل نجاح نموذج Node إلى ادعاء أن Flutter/Dart أو Native قد نُفّذ أو أن طبقة المصادقة محمية إنتاجياً. التوقيع الحقيقي في Node بمفتاح *برمجي تجريبي* لا يثبت AndroidKeyStore أو Secure Enclave.

## تقدم البوابات

| البوابة | المضمون | الحالة والأدلة |
|---|---|---|
| 6.1 | اختيار Fable/Other، عقد المشروع، العزل ومنع ترقية `test-project` | **SIM ACCEPTED — logic/source only:** RC174 PR #89 merged؛ 7/7 pure Node assertions + 8/8 read-only actual Flutter/Dart/native source checks (11 Nov). Full RC174 CLI against complete checkout and `flutter test` not executed |
| 6.2 | DPoP/Auth sender binding، تجديد Session، replay، refresh، logout | **SIM MODEL ACCEPTED:** RC175 16/16 Node cryptographic/model tests (with 6.3 overlap), mock-only credentials and P-256 keys؛ لا يثبت تشغيل Backend أو Native |
| 6.3 | Permissions/Media ACL، عزل مستخدم A/B، نتائج HTTP المتأخرة | **SIM ACCEPTED — model/source only:** RC175 ownership and session tests + RC176 4/4 pending-request revocation/ABA tests and 16/16 source invariants checked through GitHub; full Dart/widget execution not claimed |
| 6.4 | NONE/LOCAL/DRM + encrypted Media/Range/session expiry | **SIM ACCEPTED — model only:** RC177 20/20 executed Node AES-256-GCM, authenticated bounded Range, expired sessions and strict DRM no-fallback; no Flutter/native/backend E2E |
| 6.5 | Offline/SQLite/Drift/sync/identity/collision/background retry | **SIM ACCEPTED — model only:** RC178 23/23 Node cache/queue/ACK/version/idempotency/identity/single-flight/backoff and OS-best-effort mock tests; real Drift/WorkManager/BGTaskScheduler unexecuted |
| 6.6 | Selected providers (Push, Passkeys, social, payments, support) | **SIM ACCEPTED — model only:** Flutter RC179 22/22 Node synthetic provider cases (consent, RP/challenge, nonce, backend financial settlement, support unknown outcome); no Firebase/APNs/Passkey/OAuth/payment SDK live execution |
| 6.7 | Android/iOS platform boundaries and hardware-dependency failure modes | **SIM ACCEPTED — model only:** RC180 16/16 local Node fake MethodChannel/OS scheduler fail-closed cases; byte-exact Git blob; real native signatures/builds not executed |
| 6.8 | Wizard/generator 17-family selection regression and integrated acceptance | **PENDING**: deterministic combined tests, status ledger and release NO-GO |

**Progress: 7/8 development-simulation gates accepted; 6.8 pending.** These are acceptance of *specified simulations* only. A mobile feature remains `complete:false` and `liveE2EVerified:false` until independently verified; no test runner should upgrade those flags from source strings.

## Invariants

- Core independent; all optional mobile families remain 17, the Backend capability count is separate.
- Flutter Auth only uses actual imported and pinned Fable contracts, or independent verified Other Backend contracts. Never infer project ID/hash from the demo fixture.
- Backend remains authority for identity/permission/media; DPoP must bind proof to method, URL, access token, session key, jti and time; client drops late A data after switching to B.
- Never send/decrypt keys, grant permissions, choose financial provider, or activate DRM based on a UI-only local simulation.
- No GitHub Actions, paid cloud, provider secrets or production databases are needed for these simulated development gates. Stage 7 remains **NO-GO**.

## Sources

- RC174: [PR #89](https://github.com/adnan118/Fable_flutter/pull/89).
- RC175: [simulation report](./RC175-STAGE6-SIMULATED-DPOP-AUTH-MEDIA.ar.md).
- Deferred live stages: [Flutter #74](https://github.com/adnan118/Fable_flutter/issues/74), [Flutter #82](https://github.com/adnan118/Fable_flutter/issues/82).

- [RC176 Media response-race/source simulation](./RC176-STAGE6-MEDIA-RACE-SIMULATION.ar.md)

- [RC177 Tier/Range crypto simulation](./RC177-STAGE6-MEDIA-TIER-RANGE-SIMULATION.ar.md)

- [RC178 Offline/Sync model simulation](./RC178-STAGE6-OFFLINE-SYNC-SIMULATION.ar.md)

- [RC179 Optional provider simulations](./RC179-STAGE6-OPTIONAL-PROVIDERS-SIMULATION.ar.md)

- [RC180 Native platform boundary simulator](./RC180-STAGE6-NATIVE-BOUNDARY-SIMULATION.ar.md)

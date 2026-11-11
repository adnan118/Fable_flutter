# Fable — المرحلة السادسة: ثماني بوابات قبول بالمحاكاة

**11 نوفمبر 2026 | مسار تطوير فقط | ليس اعتماد تشغيل أو إنتاج**

## قرار الاختبار

بناءً على تعليمات مالك المشروع في 11 نوفمبر، نعتمد محاكاة معزولة ذات اختبارات منفذة بدل انتظار Backend إنتاجي، Android، Xcode، خدمات خارجية أو أجهزة حقيقية. **لا يجوز** تحويل نجاح نموذج Node إلى ادعاء أن Flutter/Dart أو Native قد نُفّذ أو أن طبقة المصادقة محمية إنتاجياً. التوقيع الحقيقي في Node بمفتاح *برمجي تجريبي* لا يثبت AndroidKeyStore أو Secure Enclave.

## تقدم البوابات

| البوابة | المضمون | الحالة والأدلة |
|---|---|---|
| 6.1 | اختيار Fable/Other، عقد المشروع، العزل ومنع ترقية `test-project` | **SIM ACCEPTED — logic/source only:** RC174 PR #89 merged؛ 7/7 pure Node assertions + 8/8 read-only actual Flutter/Dart/native source checks (11 Nov). Full RC174 CLI against complete checkout and `flutter test` not executed |
| 6.2 | DPoP/Auth sender binding، تجديد Session، replay، refresh، logout | **SIM MODEL ACCEPTED:** RC175 16/16 Node cryptographic/model tests (with 6.3 overlap), mock-only credentials and P-256 keys؛ لا يثبت تشغيل Backend أو Native |
| 6.3 | Permissions/Media ACL، عزل مستخدم A/B، نتائج HTTP المتأخرة | **PARTIAL MODEL:** RC175 has 3 relevant mock scenarios; full source-level media/upload and widget simulation still needed |
| 6.4 | NONE/LOCAL/DRM + encrypted Media/Range/session expiry | **PENDING**: model + source test; no unsafe DRM fallback |
| 6.5 | Offline/SQLite/Drift/sync/identity/collision/background retry | **PENDING**: model with injected clock/storage and no actual OS scheduler |
| 6.6 | Selected providers (Push, Passkeys, social, payments, support) | **PENDING**: safe adapters/provider simulations only where verified contracts exist; unsupported operations remain blocked |
| 6.7 | Android/iOS platform boundaries and hardware-dependency failure modes | **PENDING**: simulate MethodChannel and missing-hardware failure; do NOT report native compiled/device PASS |
| 6.8 | Wizard/generator 17-family selection regression and integrated acceptance | **PENDING**: deterministic combined tests, status ledger and release NO-GO |

**Progress: 2/8 development-simulation gates accepted, 6.3 partial.** These are acceptance of *specified simulations* only. A mobile feature remains `complete:false` and `liveE2EVerified:false` until independently verified; no test runner should upgrade those flags from source strings.

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

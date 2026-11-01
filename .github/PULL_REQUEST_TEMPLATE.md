# مراجعة أي تعديل Flutter / Wizard / Backend Adapter

> قبل الدمج: [السجل الرئيسي](../docs/integrations/FABLE-FLUTTER-PARITY-MASTER.ar.md) · [تعلم Flutter/BLoC](../docs/integrations/FLUTTER-BLOC-LEARNING.ar.md)

## النطاق
- ميزة Flutter (`FEATURE_IDS`):
- Capability و`operationId` من **عقد المشروع الحقيقي**:
- مرجع العقد `projectId` و`contractHash` (ليس سرّاً؛ لا تضع توكنات):
- هل العملية `MOBILE_REQUIRED` أو `ADMIN_ONLY` أو `WEB_ONLY` أو `SERVER_ONLY`؟ السبب:

## قائمة قبول النقل الكامل
- [ ] حصرنا **جميع** عمليات هذه الميزة في Backend المثبت، لا العملية المتغيرة فقط.
- [ ] لكل عملية: Method/Path/Path params/Query/Headers/Auth/MFA/Step-up.
- [ ] Model يحفظ كل DTO Fields وأنواعها/Nullable/Enums/Errors، مع اختبار Response ناقص/مزوّر.
- [ ] Repository + Widget أو BLoC/Cubit يعالجان Loading/Empty/Success/Denied/Validation/Offline/Expired.
- [ ] رفض الطلبات/الردود القديمة بعد Login/Logout/Entity switch و403؛ الصلاحيات من الباك لا من UI.
- [ ] Cache/Offline/Sync/FCM/Realtime/Idempotency متوافقة مع العملية أو موثّق سبب عدم انطباقها.
- [ ] Wizard Fable متوافق مع قرار Backend المصدّر؛ اختبار هوية العقد الموثوقة.
- [ ] Wizard Other Backend مستقل: موثق ما يحتاجه من endpoint وDTO وAuth/Permission/Errors، ولا يَنسخ Fable Path.
- [ ] أُضيف تعليق عربي يشرح القرار المعقد أو رابط docs، وحدثنا دليل BLoC عند استخدام نمط جديد.
- [ ] `node --test test/feature-parity-master.test.mjs` و`node tools/verify-feature-parity-master.mjs` وFlutter CI ناجحة.
- [ ] اختبار حي على خادم حقيقي مع صلاحيات مستخدمين وAndroid/iOS، أو أُبقي `complete=false` مع سبب واضح.
- [ ] تحديث [JSON ledger](../docs/integrations/FABLE-FLUTTER-PARITY-MASTER.json) والجدول العربي و[Issue #15](https://github.com/adnan118/Fable_flutter/issues/15).

## لم يُنفّذ بعد / حالات غير معتمدة
- العملية/السيناريو:
- السبب:
- المخاطر:
- الاختبار المطلوب:
- Backend خارجي: البيانات/المسارات المطلوبة منه:

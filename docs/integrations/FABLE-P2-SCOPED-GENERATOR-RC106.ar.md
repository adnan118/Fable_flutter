# RC106 — توليد ربط العمليات المقيدة بالكيان من عقد Fable الموثق

## القاعدة

هذه أداة Project Wizard إضافية لتوليد **ثوابت Dart للعمليات المصرح بربطها بالكيان**، وليست مولداً لـDTO أو Repository كامل. لا تفترض أي API أو Permission، ولا تغيّر Backend ولا Other Backend، ولا تضيف ترويسة Managed Entity تلقائياً لجميع الطلبات.

## شروط التوليد

لا تعمل على قالب `ci_fable` التجريبي أو مشروع غير مثبت الهوية. تشترط:

1. استيراد عقد Fable عبر Wizard بعد مراجعة المستخدم وتطابق `projectId` و`contractHash` مع قيم مستقلة.
2. بقاء ملف `.fable/frontend-setup.json` مثبتاً باسم المشروع والبصمة الحالية و`projectBound: true`.
3. وجود `.fable/feature-integration-requirements.json` يحتوي العمليات المطلوبة بعناصر `managedEntityScope: true` للعمليات المختارة فقط.
4. وجود العمليات ذاتها في `assets/contracts/contract.json` مع تطابق `operationId` و`method` و`path` و`public: false` ونجاح تحقق `verifyFableContract(mode: project)`.
5. استمرار تفعيل الميزة في قرارات Flutter المحلية؛ إلغاء تفعيل الميزة يمنع توليد ربطها.

## التنفيذ

لمعاينة خطة التوليد دون تعديل المشروع:

```bash
pnpm wizard:scope:generate -- --expected-project-id PROJECT_ID --expected-contract-hash CONTRACT_SHA256
```

لإنشاء ملف الثوابت بعد المراجعة:

```bash
pnpm wizard:scope:generate -- --expected-project-id PROJECT_ID --expected-contract-hash CONTRACT_SHA256 --apply
```

الملف الناتج: `lib/src/generated/managed_scoped_operations.dart`.

يصنّف العمليات بحسب feature/operationId ويضع لكل منها `FableManagedScopedOperation` ثابتاً مقيّداً بالبصمة؛ تستدعيه مستودعات الميزات المخصصة عبر `executeBoundInStore(store, binding)`. لا يُنتج التوليد إلا للعمليات المُحددة صراحة في متطلبات المشروع. الأمثلة الموجودة في الوثائق ليست أدلة على وجود endpoint في Backend.

## حدود التحقق

الاختبارات تحاكي صحة تخطيط وإصدار كود Dart وتمنع توليد مسارات Auth وAdmin والعمليات العامة والمفقودة أو المجهولة، وتمنع استخدام عقد تجريبي أو بدون بصمة مستقلة. هذه الحزمة ليست اختبارات E2E حقيقية لعضويات المستخدمين أو قاعدة البيانات أو الأجهزة، وليست دليلاً على جاهزية DTO أو واجهات مشروع محدد. يحتاج كل مشروع إلى تنفيذ مستودعاته واختبار أدواره وعقوده الحقيقية قبل التسليم.

## الحالة

- RC105: API والتدقيق المصدري تم دمجه في Flutter/main.
- RC106: مولد ثوابت محدد بالمشروع + اختباراته.
- P2: استكمال ملفات DTO/Repository للميزات الخاصة لا يتم تلقائياً من أسماء العمليات وحدها.
- P6: E2E حي على Backend/DB/Android/iOS معلّق.

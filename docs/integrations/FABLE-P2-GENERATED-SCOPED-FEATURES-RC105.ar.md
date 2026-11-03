# RC105 — P2: Executor موحّد لميزات Wizard المرتبطة بالحساب الفرعي

**الأساس:** Flutter/main بعد RC104: `cad8f50b099754595b6f928f7bbf90748feaf744`.
**النطاق:** Flutter Core + Profile + Wizard source audit + CI mocks. **لا تغيير في Backend أو عقود Auth الأربعين**.
**القبول:** SOURCE/SIMULATED ONLY. لا أدّعي اختبار قاعدة بيانات أو جلسات جهاز فعلي أو E2E حياً.

## المشكلة

كان `FableManagedAccountsRepository.executeUsingStore` يتحقق من السياق بعد نتيجة العملية،
لكن تأخر رفض `403` لحساب A كان قادراً على استدعاء `store.clear()` بعد انتقال المستخدم إلى B.
كذلك قد يتغير الاختيار بينما تستدعي طبقة الشبكة `headersFor` أو `accessToken`،
قبل إرسال طلب كتابة A؛ منع قراءة الاستجابة وحده لا يمنع هذا الإرسال المتأخر.

## إصلاح المصدر

1. أُضيف `FableManagedEntityExecutor` إلى `fable_core` للاستخدام الصريح داخل Repository لأي ميزة **يؤكد عقد Fable** أنها تدعم سياق كيان.
2. يثبّت المنفّذ هوية Backend، namespace جلسة المصادقة، `identityRevision`، الكيان المختار و`selectionRevision`، ويرفض نتيجة قديمة عند أي تبديل بما فيه A→B→A.
3. `contextStillValid` يصل إلى `FableAuthGateway.executeInManagedEntity` ثم إلى طبقة `UnifiedApiClient`. تُراجع الصلاحية قبل كل محاولة إرسال/إعادة محاولة، وكذلك بعد استلام الشبكة؛ فلا يرسل POST إذا تغيّر السياق أثناء انتظار الحصول على التوكن.
4. يُصفّر اختيار الحساب بعد رفض `403` أو `MANAGED_ACCOUNT_NOT_FOUND` **فقط إذا كان الرفض يخص الاختيار الجاري نفسه**. رفض حساب A المتأخر لا يمحو B.
5. أُعيد استخدام هذا المنفّذ في Profile عبر `executeUsingStore` مع الاحتفاظ بشرط `FableManagedAccountSelection` المؤكد من استجابة التفعيل. تبقى `executeInContext` القديمة واجهة توافق، وليست الخيار الآمن لميزات Wizard الجديدة.
6. لا تُحقن ترويسة `X-Fable-Managed-Entity-Id` في كل الطلبات. العمليات العامة و`/auth/*` وBackend الآخر محظورة عبر بوابات المصدر السابقة.
7. أضيف فحص `managedAccessContextBindingGaps` لوجود المنفّذ وحمايات النقل واستخدام Profile له، وفحص `managedEntityScoped:true` لكل عملية مصرح بها في `.fable/feature-integration-requirements.json`: يجب أن يظهر الربط ضمن `frontendFile`. لا يُستنتج السياق من اسم Endpoint.

## مثال استخدام للميزات المتولدة — **بعد تحقق عقد Backend**

```dart
// مثال توضيحي فقط. operationId مأخوذ من عقد المشروع الحقيقي.
final executor = FableManagedEntityExecutor(fableGateway, managedStore);
final payload = await executor.execute(
  verifiedScopedOperationId,
  path: verifiedPathParams,
);
```

لا تنشئ عمليات أو ترويسات جديدة. حتى عند نجاح هذا الكود يظل Backend هو سلطة العضوية والأدوار وصلاحيات العملية. عمليات تغيير البيانات غير مؤكدة النتيجة **لا يعاد إرسالها تلقائياً**.

## المحاكاة (ليست E2E حية)

- `packages/fable_core/test/managed_entity_executor_rc105_test.dart`: `Dio` interceptors داخل الذاكرة تحاكي رد A المتأخر (403/200)، A→B→A، تعليق الحصول على التوكن قبل POST، رفض 403 الحالي، نجاح الطلب الصحيح مع ترويسة A، ورفض الجلسة غير المطابقة/المسار العام. لا تحتاج شبكة حية ولا مفاتيح.
- `test/managed-scoped-wizard-rc105.test.mjs`: مشاريع مؤقتة تحاكي إعدادات Fable وOther Backend والعملية `managedEntityScoped`، وتفشل إذا غاب الاستخدام الصريح للمنفّذ. **هذه قراءة مصدر ثابتة**، لا تعادل إثبات استدعاء حقيقي.
- `test/managed-access-context-wizard.test.mjs`: يمنع اختفاء حارس الربط من نسخة Wizard المرجعية.
- GitHub Flutter CI يُشغّل تحليل Flutter واختبارات كل الحزم وبناء Android Debug APK وiOS Simulator. تُسجّل نتائج PR منفصلة عن نتائج main بعد الدمج.

## حدود الضمان والمتبقي

- إذا **أُرسل** طلب قبل تغيير اختيار الكيان، فلا يمكن للعميل سحب أثره من قاعدة البيانات بمجرد تجاهل الرد؛ تحتاج العملية حماية Backend وصلاحيات حديثة وIdempotency/مصالحة عند الحاجة.
- المحاكاة لا تُثبت سلوك OTP/Refresh الحقيقي أو سياسات قاعدة البيانات أو تنفيذ iOS/Android على أجهزة فعلية. هذه حالات P6.
- أي ميزة Wizard مستقبلية تقصد كياناً فرعياً يجب أن تستخدم مصدر العقد المثبت، وتُعرّف `managedEntityScoped:true` وتُجري محاكاة سباقات مستقلة بالإضافة إلى اختبارات P6. لا يجب تعميم هذا الحكم على كل خدمة.
- لا يزال PR الخاص بملف ZIP الشامل في Backend مستقلاً وغير مدمج، كما أن Backend CI لم يتأكد إصلاحه.

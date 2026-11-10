# RC163 — المرحلة الرابعة: تشديد عقد عمليات إدارة الكيانات

**التاريخ:** 2026-11-10. **المجال:** Flutter/Fable managed-entity profile operations. **حالة القبول:** تتطلب CI على رأس الفرع؛ لا يُعد هذا اختبار دخول Android/iOS عبر Render.

## الدليل وسبب الإصلاح

في `FableManagedAccountsRepository._operation` كانت مطابقة المسار والطريقة و`requiresAuth` كافية لإظهار إجراءات الإدارة. في عقد Flutter الموثّق، `FableOperation.enforceAuth` يحدد إن كان شرط المصادقة مثبتًا في بيانات العقد المستورد. قبول `enforceAuth=false` كعملية إدارية يعرّض واجهة Flutter لربط عقد غير محمي. كذلك يجب ألا يختلف مفتاح `operations` الذي يرسله `FableAuthGateway` عن `FableOperation.id`؛ ولا يُسمح بعملية ثانية على المسار والطريقة نفسيهما حتى مع هوية مغايرة.

## التغيير

1. طلب `requiresAuth=true` و`enforceAuth=true` و`credentialHeader==null` في جميع عمليات `managed-entities` المحمية.
2. رفض اختلاف مفتاح خريطة العمليات عن `operation.id` ورفض المسارات/الطرق المكررة المتضاربة، بدل اختيار واحدة صامتًا.
3. إضافة `enforceAuth` إلى `FableManagedScopedOperation.validate` لمنع إرسال رأس `X-Fable-Managed-Entity-Id` عبر عملية لم تُثبت حماية العقد.
4. الحفاظ على مسارات `Other Backend` المستقلة؛ لا يضيف RC163 أي افتراض عن API خارجي.

## الاختبارات

`rc163_managed_operation_verified_auth_test.dart`: اختبارات صحيحة وسلبية لـBearer، `enforceAuth`، Header بديل، اختلاف معرف العملية، تكرار المسار، HTTP method/path غير مطابق، وعمليات managed-scoped غير محمية. يتم التشغيل ضمن اختبار جميع حزم Flutter وCI للبناء الأصلي Android وiOS.

## الحدود والتحقق الخارجي

التحقق هو سياسة مصدر/عقد، ولا يُثبت بأن الصلاحيات تعمل في قاعدة البيانات أو بأن جميع عمليات إدارة الكيانات متوفرة على Render. إعادة استخدام خدمة Render Free المؤقتة `fable-rc151-free-ephemeral-api` لا تتطلب تغيير إعدادات أو أسرار. لقد نجحت على الخادم سابقًا 49 HTTP assertions محلية، لكن لم تُنفّذ بعد جلسة مستخدم موثّقة من Flutter على Android وiOS عبر HTTPS باستخدام عقد مشروع حقيقي وحسابين تجريبيين مؤقتين. **متطلبات مفتوحة:** [Flutter #82](https://github.com/adnan118/Fable_flutter/issues/82)، [Backend session-theft #33](https://github.com/adnan118/Fable/issues/33)، [Backend Support #35](https://github.com/adnan118/Fable/issues/35). المرحلة الرابعة مستمرة وStage 7 NO-GO.

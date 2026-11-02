# RC90 — تدقيق فوري لنقص ربط الميزات المختارة مع Backend

**القرار التنفيذي:** كل ميزة يختارها مطور Flutter وتحتاج Backend يجب أن تظهر له في Terminal بنواقص محددة أثناء تنفيذ الـWizard، أو عبر أمر فحص مستقل. لا تكفي تسمية الميزة أو وجود Repository/Widget لإعلان أنها مربوطة.

## أوامر الاستخدام

```bash
# يعرض تحذيرات لكل الميزات المختارة في مشروع Flutter (لا يغيّر الملفات)
pnpm wizard:check

# يُرجع Exit Code 2 عند وجود أي نقص أو اختبار E2E غير مثبت
pnpm wizard:check:strict

# تقرير JSON لأدوات أخرى أو للإرسال إلى مبرمج Backend
node tools/audit-selected-feature-integration.mjs --json --out .fable/feature-integration-gap-report.json
```

الفحص يعمل كذلك بعد موافقة الـWizard الرئيسي على إنشاء إعداد المشروع، وعند تفعيل ميزة محلية بواسطة `pnpm wizard:frontend`. **الفحص لا يضيف API أو يعدّل عقد Backend تلقائياً**.

## ماذا يظهر في Terminal؟

مثال توضيحي (ليس عقد Backend حقيقياً):

```text
════════ Fable: تدقيق ربط الميزات المختارة بالـBackend ════════
Backend: other | Selected: 3 | MISSING: 1 | PARTIAL: 1

⚠ [PARTIAL] notifications | backend=true | mapped=1
    • REQUIRED_OPERATION_MISSING: notices.markRead PATCH /notices/{id}/read
      ↳ المطلوب: أضف هذه العملية إلى عقد Backend الصحيح ثم استورد العقد
    • OPERATION_EVIDENCE_MISSING: notices.list → responseDto
      ↳ المطلوب: قدّم دليلاً موثقاً للحقل responseDto
    • LIVE_E2E_NOT_VERIFIED: لا يوجد إثبات E2E حي مستقل لهذه الخدمة

✖ [MISSING] payments | backend=true | mapped=0
    • EXTERNAL_API_CATALOG_MISSING: assets/contracts/external-operations.json
      ↳ المطلوب: استورد عقد Backend آخر، مع DTO والصلاحيات والأخطاء
    • PER_FEATURE_REQUIREMENTS_NOT_DECLARED: لا توجد قائمة عمليات معتمدة
      ↳ المطلوب: حدد بدقة وظائف الدفع المطلوبة لهذا المشروع
```

## أنواع النقص التي يحددها

- **Missing:** لا يوجد اختيار Backend، أو عقد خاص به، أو ربط عمليات الخدمة، أو قائمة عمليات الخدمة الفعلية؛ تُكتب أسماء الملفات المطلوب توفيرها بدقة.
- **Partial:** بعض العمليات موجودة/مرتبطة، لكن عمليات أخرى غير موجودة، أو method/path متناقض، أو DTO/Errors/Permissions/FrontendFile/TestFile ناقصة، أو لم تُربط بدور Flutter.
- **Source-mapped, E2E pending:** وجود المسار والتطبيق مصدرياً لا يعني النجاح الحي. الاختبار على Backend/Android/iOS يُعرض كعنصر مستقل غير مكتمل.
- **Client-only:** خدمات لا تحتاج Backend في المشروع لا تُجبر على عقد وهمي. لكن إذا اختير لها Backend في ملف متطلبات مشروعها، تُفحص بنفس الصرامة.

الـWizard لا يستطيع معرفة اسم endpoint غير موجود أصلاً في عقد الخادم؛ في هذه الحالة يوضح **أن اسم المسار/العملية يجب تحديده** بدلاً من اختراع مسار أو تضليل المطور. وعندما يكون هناك عقد مُعلَن يستطيع تحديد `operationId` و`method` و`path` المتعارض أو الناقص.

## ملف المتطلبات المحدد للمشروع

مسار اختيار المطور: `.fable/feature-integration-requirements.json`. لا ينشأ تلقائياً بعقد غير معلوم؛ يملأه المطور بعد استيراد العقد وتحديد احتياجات المشروع. المخطط:

```json
{
  "schemaVersion": 1,
  "kind": "fable.feature-integration-requirements",
  "features": {
    "notifications": {
      "needsBackend": true,
      "operations": [
        {
          "operationId": "notifications.inbox",
          "method": "GET",
          "path": "/notifications/inbox",
          "requestDto": "docs/contracts/notifications-inbox-request.json",
          "responseDto": "docs/contracts/notifications-inbox-response.json",
          "errors": "401,403,429/validation/timeout mapping",
          "permissions": "per-user inbox read policy",
          "frontendFile": "packages/features/fable_notifications/lib/src/inbox_repository.dart",
          "testFile": "packages/features/fable_notifications/test/inbox_other_backend_test.dart"
        }
      ]
    },
    "offline": {"needsBackend": false, "operations": []}
  }
}
```

**هذا المثال ليس مصدراً لمسارات Backend الآخر**؛ لا تنسخ قيم `notifications.inbox` و`/notifications/inbox` إلى تطبيق خارجي قبل مطابقتها مع العقد الحقيقي. إذا استخدمت Fable يجب أن تتطابق مع صادراته، وإذا استخدمت Other Backend يجب أن تكون عملياتها في `assets/contracts/external-operations.json`، ثم أن تكون أدوارها في `assets/config/feature-operations.json`.

### ما الذي يطلبه مطور Flutter من Backend؟

عند ظهور نقص في أي خدمة، يرسل قائمة `missing[]` من تقرير JSON (بها `code` و`operationId` عند وجوده و`detail` و`action`) مع `backendRequirements[]` الخاصة بالميزة، ويسأل مطور Backend عن: عمليات GET/POST/PATCH/DELETE المطلوبة، مخططات DTO، المصادقة/الصلاحيات، معاني أخطاء HTTP، Pagination/Sync/Idempotency عند الحاجة، Event Delivery، وسياسة تعارض البيانات. **لا تُرسل أسراراً أو API Tokens في الملف**.

## كيفية تحديد الاختيارات

يقرأ الفاحص قائمة `.fable/mobile-features.json` والميزات المخصصة في `.fable/project-features.json` والاختيارات المحلية الصريحة من `.fable/frontend-owned-decisions.json`. يعرض فقط المختار، ويستبعد ما ألغاه المستخدم صراحة. يرفض أن يحوّل ميزة Backend-only إلى Client-only بواسطة حقل محلي.

في Fable يعتمد على تدقيق المصدر الحالي `tools/audit-backend-feature-parity.mjs` وعقد المشروع المستورد، ويعلن عدم تثبيت هوية المشروع أو محدودية عقد CI التجريبي. في Other يعتمد على كتالوج العمليات واستيراد الـBinding الخاص بالخادم الآخر، ولا يستخدم مسارات Fable الافتراضية.

## حدود الفحص وشروط الدمج

- التقرير **Fail-closed**: لا يُعلن اكتمال E2E من ملف يدّعي `liveE2EVerified=true`؛ يحتاج تحققاً حقيقياً مستقلاً.
- يعمل `wizard:check` في وضع تحذير ليستطيع المطور رؤية النواقص أثناء البناء. يستعمل `wizard:check:strict` لإيقاف عملية تسليم مشروع عميل يحتوي ميزات ناقصة، بكود خروج 2.
- في CI الخاص بمستودع Fable Flutter العام، تظهر تحذيرات العقد التجريبي وتُختبر سيناريوهات النقص، لكن **لا نلزم Starter التجريبي بمرجع Backend حي لا يملكه**.
- كل ميزة لا تزال في حالة 0/17 live E2E ما لم تُختبر على مشروع حقيقي. هذا لا يرفع تلقائياً عداد Auth أو يلغي الحاجة لمزامنة Backend private أو إصدار ZIP الشامل.

**مصادر الخطة:** [السجل الرئيسي](./FABLE-FLUTTER-PARITY-MASTER.ar.md) · [دليل Wizard](./FRONTEND-SETUP-WIZARD.ar.md) · [RC89 Offline](./FABLE-OFFLINE-RUNTIME-RC89.ar.md).

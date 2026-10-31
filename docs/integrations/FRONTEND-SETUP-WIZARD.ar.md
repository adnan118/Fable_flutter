# Wizard Flutter: استيراد قرارات Backend أو الإدخال اليدوي

## الوضع الأول: استيراد تلقائي من Fable Backend
ينسخ المبرمج حزمة `dist/client-contract` التي يولدها الباك. تتضمن `contract.json` و`openapi.json` و`flutter-handoff.json` و`mobile-core-operations.json` و`frontend-setup.json`. الجزء الأخير سهل القراءة، لكن **لا يكفي وحده للتحقق**.

```bash
# عرض الخطة فقط — لا يغير المشروع
node tools/flutter-setup-wizard.mjs --mode import --source ../backend/dist/client-contract

# تطبيق الخيارات ونقل العقود إلى تطبيق Flutter الحالي
node tools/flutter-setup-wizard.mjs --mode import --source ../backend/dist/client-contract --out . --apply

# التحقق من ربط مشروع محدد — البصمة يجب أن تصلك عبر قناة موثوقة مستقلة عن الملف المستورد
node tools/flutter-setup-wizard.mjs --mode import --source ../backend/dist/client-contract --out . --apply \
  --expected-project-id YOUR_PROJECT_ID --expected-contract-hash YOUR_BACKEND_EXPORT_HASH
```

يُنتج الأمر `assets/config/frontend-setup.json` و`.fable/frontend-setup.json`، ويضبط `assets/config/backend.json` ويستورد ملفات العقود. قرارات الباك **غير قابلة للتعديل في هذا الوضع**: لغات وRTL، طرق الدخول والجلسات، نظام Profiles والحسابات التابعة، أذونات الشاشات، القدرات، ونوع الوصول/الاشتراكات. تتطلب مسارات المصادقة والصلاحيات والاشتراكات فحص Runtime إلى جانب القرار المصدّر.

يمكن تشغيل `node tools/read-session-policy.mjs` لقراءة قرار الجلسات وحده. العقد الصادر عن مشروع تجريبي `test-project` لا يؤهّل تكامل إنتاج حقيقي.

## الوضع الثاني: الإدخال اليدوي
يستخدمه مطور فرونت يريد تعريف مسودة لواجهة تعتمد على Backend آخر أو لم يصل عقده بعد؛ لا تُطبّق هذه المسودة أي صلاحيات أو مصادقة على الخادم:

```bash
node tools/flutter-setup-wizard.mjs --mode manual --interactive --out . --apply
```

أو ينشئ ملف JSON:
```json
{
  "schemaVersion":1,
  "kind":"manual.frontend-setup-decisions",
  "projectId":"my-app",
  "decisions":{
    "project":{"name":"My App"},
    "localization":{"defaultLocale":"ar","supportedLocales":["ar","en"]},
    "authentication":{"identityMode":"email"},
    "accounts":{"identityModel":"single"},
    "commercial":{"mode":"FREE"}
  },
  "steps":[{"id":"identity"},{"id":"authentication"},{"id":"accounts"},{"id":"permissions"},{"id":"commercial"}]
}
```

ثم ينفذ:

```bash
node tools/flutter-setup-wizard.mjs --mode manual --file my-choices.json --out . --apply
```

### إدخال يدوي مع Fable Backend نفسه

في حال أراد المطور كتابة اختياراته يدوياً مع الاحتفاظ بتطابقها مع Fable Backend، يمرر كذلك مسار الحزمة:

```bash
node tools/flutter-setup-wizard.mjs --mode manual --source ../backend/dist/client-contract --file my-choices.json --out . --apply
```

يقارن الـWizard كل اختيار يدوي قدمه المطور بما صرّح به عقد الباك الموثق. أي اختلاف في سياسة الجلسات، أنواع الحسابات، طرق الدخول، اللغات أو الاشتراكات يؤدي إلى رفض التطبيق **بدلاً من السماح بإعداد فرونت مختلف عن الباك**. عند عدم تقديم خيار يدوي، يرثه من العقد. القرارات الخاصة بعرض الواجهة لا تمنح أي صلاحيات إضافية.

## ما الذي يحدث فعلياً؟

- الباك يحدد السياسة والحقيقة، وFlutter يبني **ملف قرارات/خطة تكامل** ويستورد العقود المطلوبة؛ لا يولّد تلقائياً جميع صفحات أو مكونات المنتج من مجرد ملف إعداد.
- مخطط القرارات الستة دليل للمطور ولبقية مولدات الواجهات. يلزم إكمال بناء الشاشات والميزات واختبارات Backend/Frontend الفعلية.
- يجب عدم وضع API keys أو مفاتيح Apple/Google الخاصة أو إعدادات MySQL في أي ملف منتقل إلى Flutter.
- عند تغير Backend بعد التصدير يعاد تصدير العقد واستيراده. سياسة الجلسات وحدها تتوفر للقراءة الفعلية عبر `GET /auth/session-policy`.
- كل العمليات وتفاصيل صلاحيات Roles وManaged Entities تؤخذ من **العقد والـRuntime** ولا تُختلق من أسماء الخيارات.

## ملفات المصدر
- Backend: `lib/frontend-setup-decisions.mjs` و`lib/client-integration-contract.mjs` و`lib/flutter-handoff.mjs`.
- Flutter: `tools/flutter-setup-wizard.mjs` و`tools/verify-fable-contract.mjs` و`packages/fable_core/lib/src/fable_contract.dart`.

**التسليم التنفيذي:** Backend PR #8، Flutter PR #5. لا تعتبر ملفات البداية Fixture إقراراً بالجاهزية للإنتاج.

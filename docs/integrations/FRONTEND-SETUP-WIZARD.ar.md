# Wizard Flutter: استيراد قرارات Backend أو الإدخال اليدوي

## أول سؤال عند تشغيل Wizard — نوع الباك

```bash
pnpm wizard
```

السؤال الأول **دائماً في التشغيل التفاعلي الافتراضي**:

```text
هل الباك المستخدم لهذا المشروع هو Fable؟ (نعم/لا):
```

### إذا كان Backend من Fable

يسأل أولاً: **هل تريد استيراد قرارات Fable Backend المصدّرة؟**.
عند الموافقة على الاستيراد يطلب مسار `dist/client-contract`، ويتحقق من العقد والعمليات، ثم يعرض كل القرارات والفروقات قبل طلب كتابة `اعتمد` أو `APPROVE`. لا يطبق أو يحذف شيئاً دون موافقة. رفض الاستيراد لا يحوّل المشروع إلى Backend آخر ولا يفعّل سياسة جلسات أو أذونات بالتخمين.

### إذا كان Backend آخر وليس Fable

يسأل عن نوع العقد: `openapi` أو `custom`، ثم عن هوية التطبيق واللغات والاختيارات المحلية. **لا يسأل عن تسجيل دخول Google/Apple أو OTP أو عدد الجلسات كإعدادات أمنية مستقلة عن الخادم**؛ يضعها `unverified-external-contract` حتى تقديم عقد خارجي موثّق.

يعرض هذه الخيارات للمراجعة، ثم يطلب موافقتك. بعد الموافقة يسجل:

```json
{
  "schemaVersion": 1,
  "kind": "fable.mobile-backend-configuration",
  "backend": {
    "kind": "other",
    "adapter": "openapi",
    "status": "pending"
  },
  "contractImported": false
}
```

`fable.mobile-backend-configuration` هو **اسم صيغة التهيئة الخاصة بمحرك Flutter**، وليس ادعاءً أن الخادم الخارجي مبني بـFable. الحالة `pending` تعني أنه لا توجد واجهات شبكة أو عمليات Auth مفترضة. لا يكفي وجود ملفات Fable القديمة في `assets/contracts`؛ الاختيار `other` يمنع Flutter من تحميل تلك الملفات أو استخدام مساراتها.

يمكن تجهيز الباك الخارجي بعقد عمليات `external-operations.json` وخريطة ميزات `feature-operations.json` وخريطة Auth `external-auth.json` موثّقة وفق أداة الاستيراد الخارجية؛ **لا يستنتج Wizard مسارات تلك العمليات من أسماء الشاشات أو من Fable**. شاشات خارجية لا تظهر إلا إذا كانت عملياتها موثّقة في كتالوج الباك المختار. شاشة دخول باك خارجي لا تظهر من دون `external-auth.json` مطابق للكتالوج.

**عند الانتقال من Fable إلى باك آخر** يحدّث Wizard تهيئة الاختيار صراحةً إلى `other/pending`، فلا تُستخدم مسارات Fable السابقة. إلغاء المعاينة لا يغير إعدادات المشروع.

### الاختبارات والتشغيل الآلي

- `node tools/flutter-setup-wizard.mjs --mode import --source PATH`: معاينة عقد Fable فقط، دون تعديل.
- `node tools/flutter-setup-wizard.mjs --mode import --source PATH --interactive`: الاستيراد التفاعلي مع الموافقة.
- `--mode manual`: إعداد باك آخر بصورة غير موثقة، وتبقى العمليات محظورة حتى استيراد كتالوج خارجي صالح.
- المزامنة من CI تتطلب `--yes` مع هوية المشروع وبصمة عقد Fable مستقلتين؛ لا يُستخدم هذا المسار لباك آخر.


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

## التمييز الإلزامي بين قدرة الباك وقرار Flutter

تعتمد أداة المزامنة الآن على **تصنيف ثابت مملوك لـFlutter** وليس على استنتاج أسماء الميزات من Backend:

| النوع | الميزات | قرار الحذف |
|---|---|---|
| Backend-only (خادم) | auth, support, social, realtime, messaging, payments, content | يمكن إزالة الحزمة اختيارياً **فقط** عند غياب قدرة الباك، وبعد فحص استيراداتها واستثناء Auth الأساسية |
| Frontend-only (محلي) | deeplinks, offline | لا يحذفها الباك مطلقاً؛ قرارها محلي في Flutter |
| Hybrid (مشترك) | profile, notifications, media, localization, biometrics, location, analytics, access_control | تحافظ المزامنة على حزمها حتى لو لم يفعّل الباك الـAPI المقابل؛ تُخفى العمليات البعيدة غير المدعومة |

**القاعدة:** `Backend disabled` لا يعني `Flutter package unused`. مثال: يظل الوصول إلى الصور المحلية صالحاً ولو كان رفع الوسائط إلى الخادم معطّلاً. وكذلك الإشعارات المحلية والخرائط على الجهاز والـOffline وDeep Links.

يُسجَّل القرار المحلي بصورة مستقلة في:
- `.fable/frontend-owned-decisions.json`
- `assets/config/frontend-owned-decisions.json`

هذا الملف لا يحتوي مفاتيح سرية ولا يمنح صلاحيات على Backend، ولا يعيد استيراد الباك كتابته فوق اختيارات المستخدم.

قراءة قرارات Flutter الخاصة:

```bash
pnpm wizard:frontend
```

لتفعيل Offline محلياً مع المعاينة وطلب كتابة «اعتمد»:

```bash
pnpm wizard:frontend offline on
```

لإيقافها من الواجهة دون حذف الحزمة:

```bash
pnpm wizard:frontend offline off
```

ولإرجاع القرار إلى حالة المراجعة:

```bash
pnpm wizard:frontend offline review
```

القيم `on/off/review` تخص الواجهة **فقط**؛ لا تفعّل Backend Sync ولا تتجاوز أذونات الخادم. ولا تُظهر الأداة واجهة تعتمد على API غائب. كل Hybrid تحتاج ربطاً مستقلاً لمساراتها المحلية والخلفية مع اختبارات حقيقية.

## مطابقة الميزات وإخفاؤها ثم حذف غير المستخدم

ينشر الباك قائمة `decisions.frontendFeatures.enabled` المبنية على الـCapabilities المثبتة. لا يختلق الفرونت قوائم مستقلة؛ الشاشة الرئيسية ومسارات الإشعارات لا تعرض ولا تفتح الميزات الموجودة خارج القائمة.

بعد استيراد العقد:

```bash
# معاينة الميزات التي ستبقى والتي ستخرج من التطبيق (بدون تغيير)
node tools/sync-project-features.mjs --source ../backend/dist/client-contract --out . \
  --expected-project-id REAL_PROJECT_ID --expected-contract-hash VERIFIED_HASH

# تطبيق القائمة الموثقة وإخراج غير المستخدم من سجل Flutter
node tools/flutter-setup-wizard.mjs --mode import \
  --source ../backend/dist/client-contract --out . --apply \
  --expected-project-id REAL_PROJECT_ID --expected-contract-hash VERIFIED_HASH

# حذف حزم المشروع غير المستخدمة فعلياً مع نسخة احتياطية، بعد فحص imports
node tools/flutter-setup-wizard.mjs --mode import \
  --source ../backend/dist/client-contract --out . --apply --prune \
  --expected-project-id REAL_PROJECT_ID --expected-contract-hash VERIFIED_HASH
```

لا يحذف الوضع الأخير ميزات Flutter المحلية ذات القرار المؤجل مثل Offline وDeep Links؛ لا يُسمح بحذفها إلا بمراجعة صريحة مستقلة. ينشئ الوضع الأخير نسخة احتياطية في `.fable/feature-backups` ويسجل الملفات/الحزم المحذوفة والمحجوبة في `.fable/last-feature-sync.json`. ما زال يستخدم `pubspec.yaml` و`lib/src/generated/feature_registry.dart` الملائمين لهذا المشروع. **لا يُزال كود مربوط باعتمادية فعلية**؛ يظهر في `blocked` بدلاً من كسر البناء. تبقى `auth` و`access_control` دائماً، وتبقى حزم الميزات المحلية `deeplinks` و`offline` محفوظة للمراجعة الصريحة؛ ولا يُستدل على عدم حاجة المشروع إليها من غياب Capability في الباك. لا تُفعّل مزامنة Offline مع الخادم دون عقد وعمليات صريحة. الميزات الدومينية التي بناها المبرمج لا تُحذف آلياً.

**قيد مهم:** هذه عملية على **مشروع Flutter موثّق ومولَّد** وليست على قالب Fable Flutter العام أو عقد `test-project`. لا يبدأ الحذف عندما لا توجد هوية مشروع وبصمة عقد مؤكدة ومستقلة. ويمكن استعادة الملفات من النسخة الاحتياطية أو Git.

## ماذا لا تفعل المزامنة؟

لا تستبدل الصلاحيات الفعلية: الـRole والـPermissions وحالة الاشتراك تؤخذ من طلبات Backend الحالية. ولا يمكن اعتبار ظهور شاشة دليلاً على سماح تنفيذ عملية. إغلاق الميزة في Dashboard أو Flutter لا يمنع الوصول إلى API من دون Backend Guard.

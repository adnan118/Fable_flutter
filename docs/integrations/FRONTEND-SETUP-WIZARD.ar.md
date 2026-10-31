# Wizard Flutter: استيراد قرارات Backend أو الإدخال اليدوي

## التشغيل الافتراضي من أول سؤال (موصى به)

من جذر مشروع Flutter شغّل:

```bash
node tools/flutter-setup-wizard.mjs
```

أول سؤال يظهر قبل إعداد أي ميزة:

```text
هل تريد استيراد قرارات Fable Backend الآن؟ (نعم/لا) [نعم]:
```

- إذا اخترت **نعم**، يسأل عن مسار مجلد `dist/client-contract` الذي صدّره الباك تلقائيًا بنهاية `pnpm fable init`.
- يتحقق من عقد الباك، وتطابقه مع Flutter Handoff وبصمة الملفات. ثم يطبع **شجرة القرارات الكاملة** في التيرمنال: تعريف المشروع واللغات وRTL والمصادقة/الجلسات والحسابات المتعددة والميزات والاشتراكات والصلاحيات، وخطوات الفرونت والفروقات عن أي استيراد سابق.
- قبل تعديل ملف واحد يطلب منك كتابة **`اعتمد`** أو **`APPROVE`** حرفيًا. الضغط على Enter أو كتابة «لا» أو «نعم» لا يوافق.
- عند الرفض لا يكتب أي ملف؛ وعند الموافقة ينسخ العقد الموثق ويحفظ القرارات. إن كنت قد مررت بصمة المشروع المستقلة، ينفّذ أيضاً مزامنة الميزات؛ أما الحذف المادي للحزم فلا يحدث تلقائياً بل يحتاج `--prune` وفحص الاعتماديات ونسخة احتياطية.
- إذا اخترت **لا**، يبدأ إعداد Flutter اليدوي، ويعرض اختياراتك قبل طلب الموافقة.

إذا كنت تريد القراءة فقط دون فتح وضع الأسئلة أو تعديل ملفات:

```bash
node tools/flutter-setup-wizard.mjs --mode import --source ../backend/dist/client-contract
```

وللتشغيل التفاعلي مع مسار معروف:

```bash
node tools/flutter-setup-wizard.mjs --mode import --source ../backend/dist/client-contract --interactive
```

**التشغيل الآلي في CI فقط:** استعمل `--mode import --source ... --apply --yes` مع `--expected-project-id` و`--expected-contract-hash` مستقلين وموثوقين؛ وإلا يرفض الكتابة دون سؤال تفاعلي. لا تعدّ بصمة تُقرأ من الملف المراد اعتماده مصدر تحقق مستقلاً. هذه ليست موافقة إنتاج على عمليات API حتى يتم اختبار الخادم الفعلي.

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

ينشئ الوضع الأخير نسخة احتياطية في `.fable/feature-backups` ويسجل الملفات/الحزم المحذوفة والمحجوبة في `.fable/last-feature-sync.json`. ما زال يستخدم `pubspec.yaml` و`lib/src/generated/feature_registry.dart` الملائمين لهذا المشروع. **لا يُزال كود مربوط باعتمادية فعلية**؛ يظهر في `blocked` بدلاً من كسر البناء. تبقى `auth` و`access_control` دائماً، وتحتاج الميزة المحلية `deeplinks` قراراً من الفرونت، بينما Offline Sync يتطلب عقد الباك عند استخدامه. الميزات الدومينية التي بناها المبرمج لا تُحذف آلياً.

**قيد مهم:** هذه عملية على **مشروع Flutter موثّق ومولَّد** وليست على قالب Fable Flutter العام أو عقد `test-project`. لا يبدأ الحذف عندما لا توجد هوية مشروع وبصمة عقد مؤكدة ومستقلة. ويمكن استعادة الملفات من النسخة الاحتياطية أو Git.

## ماذا لا تفعل المزامنة؟

لا تستبدل الصلاحيات الفعلية: الـRole والـPermissions وحالة الاشتراك تؤخذ من طلبات Backend الحالية. ولا يمكن اعتبار ظهور شاشة دليلاً على سماح تنفيذ عملية. إغلاق الميزة في Dashboard أو Flutter لا يمنع الوصول إلى API من دون Backend Guard.

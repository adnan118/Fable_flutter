# ADR RC88 — قرار Fable Offline + Background Sync (معتمد للتخطيط فقط)

**الحالة:** APPROVED_FOR_PLAN / DOCUMENTATION_ONLY  
**تاريخ القرار:** 2026-11-02  
**النطاق:** Fable Flutter Core + Android/iOS Adapters + Wizard + Backend Fable/Other  
**نوع التغيير في هذه الدفعة:** توثيق فقط. **لا تعديل كود، لا تفعيل Plugin، لا إنشاء مسار API، لا تغيير إعداد مشروع، ولا ادعاء نجاح E2E.**

## القرار المعتمد

1. **Offline = ON** للخيار المرجعي الذي اعتمده المستخدم لمشروع Fable Mobile. التخزين المحلي المخطط: **SQLite + Drift**. هذا **لا** يعني إجبار كل تطبيق يُولَّد بواسطة Wizard على Offline: يظل قابلاً للاختيار لكل مشروع عبر Wizard.
2. **Sync policy = FOREGROUND_PLUS_BACKGROUND_BEST_EFFORT**: المزامنة عند تشغيل التطبيق، عند العودة إلى الواجهة، وبعد استعادة اتصال موثوق/بطلب المستخدم، مع *محاولات* إضافية في الخلفية عندما يتيح النظام ذلك. لا ضمان لكل إشارة تغيير اتصال أو فتح، وتُطبَّق قيود الشبكة والمصادقة.
3. محرك Sync واحد محايد عن نظام التشغيل وعن مزود Backend، ويملك قواعد حفظ التغييرات، حل التعارض، القابلية للاستئناف، وإزالة التكرار. التفويض للجدولة والتنفيذ الخلفي يتم عبر Platform Adapter متخصص.
4. Backend هو مصدر الحقيقة للحجز والدفع والأسعار والمخزون والرصيد والصلاحيات وصحة الجلسات. لا يوجد قبول مالي أو نجاح عملية على أساس Cache محلي أو Push فقط.
5. **لا تنفيذ الآن.** جميع المتطلبات التالية هي عقد وتصميم مطلوب للمراجعة لاحقاً؛ لا تُعدّ عمليات نقل/واجهات منفذة أو متحققة على Backend حقيقي.

## سلوك مشترك إلزامي للمحرك

- عند فتح التطبيق أو استعادته (foreground / resumed): قراءة قائمة عمليات محلية معلّقة، التحقق من حالة تسجيل الدخول وصلاحية Identity/Installation، الاتصال بالخادم، تنفيذ المصادقات وإعادة التحقق، ثم سحب التغييرات وعرض حالة البيانات. منع التزامن المتعدد لنفس User/Entity/Resource عبر single-flight/unique-work، مع إلغاء المهام عند Logout وتبديل الحساب.
- على فقد الشبكة: إبقاء نسخ GET المسموح تخزينها محلياً وتمييزها كـ«قديمة/غير مؤكدة»؛ حفظ تعديلات المستخدم في Queue **فقط إذا** كان هناك عقد Backend يجيز Offline Mutations لتلك العملية. لا تُنشأ وهمياً سجلات حجز/دفع نهائية.
- على استعادة الشبكة: تشغيل opportunistic sync عند نشاط التطبيق؛ في الخلفية فقط عند فرصة من النظام. Retry exponential backoff + jitter، مع سقف محاولات، فحص الاستجابة، TTL، وترميز سبب الفشل. لا حلقة retry مستمرة.
- كل عملية كتابة مؤهلة: UUID/idempotencyKey ثابت طوال إعادة المحاولة، هوية الحساب/الكيان، نوع العملية، نسخة السجل أو ETag ووقت التعديل من الخادم، طلب DTO من العقد الأصلي، سياسة ترتيب Dependencies، وحالة ack/conflict. حذف سجل Queue **فقط بعد إقرار خادم صالح**؛ تعامل واضح مع HTTP timeout المجهول و409/412/429 و401/403/5xx.
- فصل وحماية التخزين حسب User/ManagedEntity/BackendProject. تنظيف أو عزل الصفوف الحساسة عند Logout/حذف الحساب/تبديل Backend، وعدم نسخ Access/Refresh Token أو OTP إلى Drift. مفاتيح الأسرار من مخزن آمن على الجهاز، مع مراجعة تشفير الحقول الحساسة وسياسة Data Retention قبل التنفيذ.
- قرار النزاع الافتراضي **لا تطغَ على نسخة الخادم بصمت**. لكل Resource: SERVER_WINS أو CLIENT_WINS أو MANUAL_REVIEW أو MERGE وفق عقد الخادم، مع نسخة ووقت موثوقين. العمليات المالية/الحجوزات ذات الأسعار المتغيرة تتطلب re-fetch/revalidation قبل Commit الخادم.
- UI states موحّدة: `online`، `offline_cached`، `sync_pending`، `sync_in_progress`، `sync_failed_retryable`، `sync_conflict`، `revalidation_required`، `auth_required`. تعرض آخر مزامنة مؤكدة، وعدد العمليات المعلّقة، وأخطاء قابلة للفهم، وزر إعادة محاولة عند السماح. لا تُظهر كلمة «تم» قبل ACK من Backend.
- Push/inbox/realtime هي **إشارات تحديث** إن توفرت، وليست دليلاً على أن البيانات المتزامنة اكتملت. عند استلام إشارة: علّم النسخة المحلية stale ثم fetch ضمن الصلاحيات والعقد حين يسمح النظام.

## Android — متطلبات Platform Adapter عند التنفيذ

- استخدام **Android WorkManager** للمهام الدورية/المؤجلة القابلة للاستئناف، مع Network Constraints وBattery/Storage Constraints المناسبة، وUnique Work وتنسيق التوازي وBackoff. لا تُعادل جدولة WorkManager تشغيل Service دائمة.
- Periodic Work الحد الأدنى المعروف **15 دقيقة**، لكنه ليس SLA أو وعداً بالعمل كل 15 دقيقة؛ يتأخر بسبب Doze/قيود البطارية/الصانع/التطبيق والإصدار.
- جدولة عمل إضافي بعد نجاح كتابة محلية أو نشاط التطبيق، مع تجنب تكرار jobs والبيانات. Foreground Service فقط لأعمال مستوفية شروط النوع والشفافية وسياسات Android، **لا** كحل افتراضي لإبقاء المزامنة دائمة.
- فحص الاستعادة بعد قتل العملية، إعادة تشغيل الجهاز، ترقية التطبيق، تغيّر الشبكة، قيود Battery Saver، وتبديل الحساب. لا يفترض استمرار Flutter isolate ولا وجود متغيرات ذاكرة بعد إعادة التشغيل.

مراجع Android الرسمية:
- https://developer.android.com/develop/background-work/background-tasks/persistent
- https://developer.android.com/develop/background-work/background-tasks/persistent/getting-started/define-work

## iOS — متطلبات Platform Adapter عند التنفيذ

- استخدام **BGTaskScheduler** للأعمال المسموحة: **BGAppRefreshTask** لعمل سريع لتحديث البيانات، و**BGProcessingTask** لأعمال مناسبة أطول. تسجيل Task Identifiers والـBackground Modes الضرورية فقط مع expiration/cancellation handler وcheckpoint لعملية الاستئناف.
- يحدد iOS توقيت التنفيذ ومدة السماح؛ لا توجد مزامنة مستمرة ولا ضمان للبدء كل N دقائق، أو عند إغلاق التطبيق قسرياً. ولا يُعامل Silent Push كتنفيذ مضمون.
- نقل الملفات الطويلة عبر **Background URLSession** عندما يناسب عقد الوسائط ونوع الرفع/التنزيل؛ لا يُفترض استمرار كود Dart أو تفعيل خدمة عامة دائمة. عند Force Quit من المستخدم تكون قدرات الاستئناف الخلفي محدودة، ويجب إجراء reconciliation عند فتح التطبيق.
- اختبار Background App Refresh مع تفعيلها/تعطيلها، Low Power Mode، Force Quit، تقييد الشبكة، انتهاء المهلة، تعليق التطبيق وإعادة تشغيله. تستمر العمليات المحلية المعلّقة حتى فرصة استئناف صحيحة.

مراجع Apple الرسمية:
- https://developer.apple.com/documentation/uikit/using-background-tasks-to-update-your-app
- https://developer.apple.com/documentation/BackgroundTasks
- https://developer.apple.com/documentation/foundation/urlsessionconfiguration/background(withidentifier:)

## Backend Fable — ما يجب إثباته قبل تفعيل Sync

- لا نفترض وجود `/sync` أو أي Endpoint خفي. يُستورد **عقد المشروع الحقيقي المولّد والمثبت**، ويُسجَّل لكل Capability/Operation هل تسمح Cache GET، أم Delta Read، أم Offline Write، أم تتطلب إعادة تحقق/Online-Only.
- لكل عملية GET قابلة للمزامنة: method/path الفعليان، DTO، pagination/cursor أو deltaToken إن وجد، ETag/version/updatedAt أو بديل معتمد، حدود TTL، سياسة الحذف والتغييرات المنطقية (tombstones)، Scope الكيان والحساب، الفلترة والصلاحيات.
- لكل POST/PATCH/DELETE يسمح بتخزينها: سياسة idempotency وفترة حفظ المفتاح وdedupe في الخادم، شروط precondition/version وطرق الإبلاغ عن 409/412، ترتيب العمليات المترابطة، ACK وآلية reconciliation بعد Timeout/unknown outcome، وحدود 429/Retry-After.
- حماية HTTP Auth/Token rotation/forced password change/Session revocation، صلاحيات كل عملية، Managed Entity/RBAC، Error Codes وProblem Details، حدود معدل الطلبات وعدم تسريب البيانات. لا تكرار تنفيذ عند 401/403 قبل تجديد مصادقة موثّق.
- أحداث تغيّر الأسعار/المخزون والحجوزات يمكن أن تسرع الإبطال والكاش فقط. واجهة السعر أو الحجز محلياً لا تصبح «تأكيداً» إلا بعد revalidation على الخادم؛ لا Queue للدفع أو حجز نهائي افتراضياً.
- التفاوض على قدرات الخادم يكون من العقد أو Endpoint مثبت **إن وجد**، وليس من اسم قدرة عامة أو وجود Package في Flutter.
- لا يُؤشر أي عمود backendSyncSupported=true قبل مراجعة Controller/Service/DTO/Permissions/Errors واختبار تكامل حي.

## Backend آخر (Other Backend) — عقد مستقل إلزامي

- البدء بـ`other/pending` وحجب Offline Mutation Sync حتى استيراد عقد موثّق ومنفصل (OpenAPI أو Custom)؛ **لا** إعادة استخدام مسارات، headers، رموز الأخطاء، أو سياسات Fable تلقائياً.
- يتضمن العقد: base URL وعمليات method/path، auth/session model، DTO schemas وnullability، GET cache/pagination/delta، record version/timestamps/tombstones، idempotency/duplicate behavior، mutation acknowledgment، 409/412 conflicts، 401/403/429/5xx، Retry-After، صلاحيات الأدوار والكيانات، التزامن بين الحسابات، ومخاطر حذف البيانات.
- يصدر Adapter جدول دعم per-operation: `READ_CACHE`، `READ_DELTA`، `OFFLINE_CREATE`، `OFFLINE_UPDATE`، `OFFLINE_DELETE`، `ONLINE_ONLY`، `UNSUPPORTED` مع Evidence واختبارات. لا تستخدم Default Mapping للعمليات التي لم يصدق عليها Backend.
- إن كان الخادم لا يضمن idempotent writes أو يفتقر إلى إصدارات وتعارضات قابلة للتحقق: **اسمح بالقراءة من Cache فقط إن سمحت السياسة، وارفض إرسال كتابات معلّقة تلقائياً** حتى يتوفر عقد بديل آمن.
- Push وFCM والترجمة وإشعارات الأجهزة وOffline لا تثبت من أسماء الميزات، ولا تؤخذ من إعدادات Fable السابقة.

## Wizard — قرارات مطلوب إضافتها عند مرحلة التنفيذ، لم تُضف برمجياً

**السؤال الأول لا يتغير:** `Fable Backend` أم `Other Backend`؟ ثم استيراد العقد الصحيح/ترك الحالة Pending. بعده القرارات التالية محلية يختارها المشروع:

| مفتاح تخطيطي (غير منفذ حالياً) | القيمة المعتمدة أو القاعدة |
|---|---|
| `offline.enabled` | **true** في القرار المرجعي الحالي؛ قابل للتغيير في مشاريع أخرى |
| `offline.database` | `sqlite_drift` عند التفعيل |
| `sync.policy` | **`foreground_plus_background_best_effort`** |
| `sync.onAppStart` / `sync.onResume` | true من حيث التصميم، مع dedupe/retry guards |
| `sync.onConnectivityAvailable` | attempt only when eligible; no guaranteed callback |
| `sync.backgroundScheduler.android` | `workmanager` (قيد اعتماد النسخة/التكامل قبل التنفيذ) |
| `sync.backgroundScheduler.ios` | `bg_task_scheduler`، وخيار URLSession لنقل الوسائط المناسب |
| `sync.offlineWrites` | **per-operation opt-in after validated server contract**؛ ليس true عاماً |
| `sync.conflictPolicy` | per resource, fail-closed on unknown |
| `sync.financialOperations` | `online_revalidation_required` |
| `sync.statusUI` | حالات موحّدة ومؤشر آخر مزامنة مؤكدة |

- إذا اختير `Offline=NO`: لا إنشاء DB/Queue/Background Sync بسبب القرار الحالي، إلا إذا امتلكت ميزة أخرى حاجة محلية مستقلة مثبتة.
- إذا اختير Offline=YES: يطلب Wizard تحديد أصناف GET المحلية والموارد القابلة للكتابة، retention/TTL/cache size وسياسات logout/conflict؛ يعرض المتطلبات الفعلية للباك المختار ويضع غير المدعوم في `pending_contract`.
- اختيار `foreground_plus_background_best_effort` لا يسمح للـWizard بوعد المزامنة كل 5/15/30 دقيقة، ولا بإخفاء قيود iOS. يوضح صراحة أن الخلفية إضافة غير مضمونة.
- الإعدادات المحلية من قرارات Flutter-owned لا تُكتب فوق سياسات Auth/Permissions/Financial الخاصة بالباك. يجب عرض Plan Diff وموافقة المستخدم قبل تغيير أي ملف.
- لا يجوز لمولد التطبيقات استنتاج Offline Sync لكل ميزة من مجرد وجود API؛ يلتزم بوضعها كـ`not_reviewed` حتى استكمال عقدها واختباراتها.

## مصفوفة التحقق قبل اعتماد التنفيذ مستقبلاً

| حالة الاختبار | Android | iOS | Backend Fable | Other Backend |
|---|---|---|---|---|
| Open/Resume ينفذ بعد التأكد من العقد | مطلوب | مطلوب | عقد مشروع مثبت | عقد مستقل مثبت |
| Offline GET Cache & stale UI | مطلوب | مطلوب | سياسة TTL وصلاحيات | سياسة TTL وصلاحيات |
| Queue mutation عند توفر idempotency صريح فقط | مطلوب | مطلوب | عملية مختبرة/ACK | عملية مختبرة/ACK |
| تعارض 409/412 وفقد ACK وإعادة المحاولة | مطلوب | مطلوب | اختبارات Race/Idempotency | اختبارات Contract |
| 401/403/Revoke/Logout وتبديل الحساب | مطلوب | مطلوب | اختبار Session/RBAC | عقد Auth مستقل |
| تأخير الخلفية وبطارية منخفضة وForce Quit | مطلوب | مطلوب | لا تأثير على صحة البيانات | لا تأثير على صحة البيانات |
| تأكيد الأسعار والحجوزات والدفع | Online-only | Online-only | revalidation قبل Commit | revalidation قبل Commit |
| إيقاف/استئناف ومراقبة لا يكرر الطلب | مطلوب | مطلوب | dedupe + audit | dedupe + audit |

## حالة التسليم والحدود

- **قرار تخطيطي معتمد**؛ لا يتم إنشاء أي API/DTO/Queue/Adapter/Plugin/Wizard UI أو تعديل الإعدادات الآن.
- **Live E2E:** لا يوجد اعتماد جديد؛ يستمر عدّاد `0/17` ميزات Flutter E2E. حالة Auth `9/40` source-reviewed ليست مرتبطة بهذا القرار ولا تتغير.
- تحضير التنفيذ في مرحلة مستقلة بعد تدقيق العقد مع Backend Fable أو Other Backend، ثم مراجعة الحواجز الأمنية والخصوصية واختبارات على Android/iOS.
- القرار لا يُغيّر خطّة إصلاح CI الخاص أو الـZIP؛ سجل التقدم الرئيسي [Issue #15](https://github.com/adnan118/Fable_flutter/issues/15).

## مراجع قواعد الأنظمة

- Apple: [Using background tasks to update your app](https://developer.apple.com/documentation/uikit/using-background-tasks-to-update-your-app)
- Apple: [Background Tasks](https://developer.apple.com/documentation/BackgroundTasks)
- Apple: [Background URLSession](https://developer.apple.com/documentation/foundation/urlsessionconfiguration/background(withidentifier:))
- Android: [Task scheduling / WorkManager](https://developer.android.com/develop/background-work/background-tasks/persistent)
- Android: [Define work requests](https://developer.android.com/develop/background-work/background-tasks/persistent/getting-started/define-work)

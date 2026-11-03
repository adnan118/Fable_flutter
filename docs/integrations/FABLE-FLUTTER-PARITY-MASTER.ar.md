> **RC108 — P3 Notifications (2026-11-03):** تُربط الملاحة الناشئة من Push/Inbox بإصدار هوية الجلسة، وتُلغى عمليات فتح الإشعار المتأخرة عند تبديل المستخدم أثناء `await` أو تحميل بيانات التطبيق. يبقى فتح التنقل المؤجل بعد Login ممكنًا، لكن تحت تحقق جديد. **محاكاة مصدر فقط؛ P6 FCM/APNs/Backend/device E2E غير مثبتة.** [التفاصيل](./FABLE-P3-NOTIFICATION-IDENTITY-RC108.ar.md).
> **RC107 — مولّد ثوابت الحساب الفرعي (2026-11-03):** دُمج تصميم مولّد `managedEntityScope:true` مع قاعدة RC106 المدمجة، وأضيف منع استبدال ملف مشروع مُعدَّل أو تعطيل ميزة بسبب تكرارها في السجلات. يظل ذلك Source/Simulated فقط؛ P6 حي مؤجل. [الدليل](./FABLE-P2-SCOPED-GENERATOR-REVIEW-RC107.ar.md).
> **RC106 — حماية النقل بعد RC105 (2026-11-03):** يصير رفض 403 المتأخر لحساب A غير قادر على إلغاء اختيار B، ويرفض العميل إرسال Mutation مقيّدة إذا تغيّر الحساب أثناء انتظار الاعتمادات أو Retry. اختبارات المحاكاة لا تغلق P6. [الدليل](./FABLE-P2-SCOPED-TRANSPORT-RACE-RC106.ar.md).
# السجل الرئيسي الثابت — مطابقة Fable Backend ↔ Flutter ↔ Wizard ↔ Other Backend

> **RC105 — الربط الصريح لعمليات المشروع ضمن الحساب المُدار (2026-11-03):** أُضيف `FableManagedScopedOperation` المستند حصراً إلى عقد Fable المصدَّر (operationId/method/path/contractHash)، و`executeBoundInStore` للتحقق من المخزن الجاري وإسقاط الردود المتأخرة عند تغيّر الكيان. في تدقيق Wizard، لا يكفي وجود حزمة Flutter أو اسم عملية؛ يجب أن يكون `managedEntityScope:true` اختياراً صريحاً مع دليل مصدر واختبار وعملية مطابقة، ولا يُورَّث هذا الاختيار إلى Other Backend أو Web/Admin. **لا يُنشئ RC105 مستودعات الميزات المخصصة تلقائياً، ولا يُثبت E2E حيّاً.** [دليل RC105](./FABLE-P2-SCOPED-FEATURE-BINDING-RC105.ar.md).

> **RC102 — حماية صفحة أعضاء الكيان والدعوات (2026-11-03):** في طبقة Flutter فصلنا صلاحية صفحة إدارة أعضاء الكيان عن مجرد ثبات Login: تحمل الصفحة نفس `FableManagedEntityStore` و`selectionRevision` وتُسقط بياناتها وأزرارها عند تغيير الكيان حتى مع A→B→A. وبعد تأكيد حذف عضو أو إلغاء دعوة يُعاد فحص السياق قبل DELETE؛ وعند الاستئناف يُطلب إثبات عضوية ودور حديث من Backend. أُضيف تدقيق ذلك للـWizard. **هذه حماية مصدر واختبارات محاكاة، لا شهادة E2E حية**. [دليل RC102](./FABLE-P2-MANAGED-MEMBERS-RC102.ar.md).

> **RC101 — تكامل سياق Managed Accounts وAccess Control (2026-11-02):** وحّدنا namespace جلسة Fable بين App Store وبوابات Auth المستقلة للميزات؛ أصبح تبديل الكيان يبطل Snapshot الصلاحيات فوراً ويعيد قراءة صلاحيات المستخدم العامة، مع إبقاء OWNER/MANAGER/VIEWER منفصلة عن صلاحيات المستخدم العامة. أضيف فحص Wizard يمنع تمرير مشروع مختار فيه Profile + Access Control مع Managed Entities دون هذا الربط. العمليات المقيّدة بالسياق يجب أن تستخدم `executeUsingStore`؛ رفض 403 أو `MANAGED_ACCOUNT_NOT_FOUND` يمسح الاختيار، واستئناف التطبيق يعيد التحقق من عضوية ودور الكيان. **لا تغيير في Backend، ولا ادعاء E2E حي.** [دليل RC101](./FABLE-P2-MANAGED-ACCESS-INTEGRATION-RC101.ar.md).

> **RC90 — التدقيق في Terminal:** بمجرد اعتماد خدمات Flutter أو تغيير اختياراتها، يعرض الـWizard تقرير نقص الربط **لكل خدمة مختارة** (Fable أو Backend آخر) بحسب العمليات المعروفة: Missing/Partial/Source-mapped E2E Pending. الفحص المستقل: `pnpm wizard:check` أو `pnpm wizard:check:strict`، مع تقرير JSON اختياري. لا نختلق مسارات Backend غير معلنة ولا نعتبر نجاح CI اكتمالاً حياً. [دليل RC90](./FABLE-SELECTED-FEATURE-GAPS-RC90.ar.md).

> **قرار RC88 المعتمد للتخطيط فقط (2026-11-02):** Offline مفعّل في إعداد Fable المرجعي مع SQLite/Drift، والمزامنة عند فتح/استعادة التطبيق ومحاولات خلفية Best Effort عبر Android/iOS وفق قيودهما. **لم نغير أي سلوك تنفيذي، ولم نفعّل الـWizard برمجياً؛ لا موعد خلفياً مضموناً ولا عمليات كتابة Offline دون عقد Backend.** التفاصيل والمتطلبات لـFable/Other والـWizard في [ADR RC88](./FABLE-OFFLINE-BACKGROUND-SYNC-ADR-RC88.ar.md).  


> **مرجع الخطة الموحّد RC80، وآخر دفعة تدقيق RC86 — 2026-11-01.**
> الباك المرجعي وقت الفحص: `adnan118/Fable@226cbcdc542ebe9c005d7445d84cc0ec10631932`.
> الفرونت المرجعي وقت الفحص: `adnan118/Fable_flutter@94a63b77565ae7ee796e5ecbcf42aac8eb9ea7a7` (بعد RC79).
> **هذا تقرير مصدر وعقود وفحوص CI، وليس اعتماد تشغيل حي أو تكامل إنتاج.**
> يرجى تحديثه مع كل PR يغلق فجوة، ولا يُستبدَل بسجلات تقدم عابرة.

## RC86 — ربط مصدر الريبوين وإصدار حزمة مصدرية شاملة

- وثقنا **بصمة Git لعقد Backend Auth** ومطابقته مع جرد عمليات Flutter: **40/40 تطابق معرف/طريقة/مسار** في Snapshot المراجع؛ هذا لا يثبت نقل تفاصيل جميع DTO/الواجهات.
- أضفنا `verify-cross-repo-source-pair.mjs` و`cross-repo-source-pair-rc86.test.mjs` للفحص دون تخمين Backend غير Fable؛ و`build-rc86-source-archive.py` لإصدار ZIP كاملة من الريبوين داخل CI الخاص بـBackend، مع استبعاد الأسرار وبصمات SHA256.
- **العداد ثابت:** 9/40 `SOURCE_IMPLEMENTED_E2E_PENDING`، 31 `NOT_DECIDED`، 0/17 E2E حقيقي؛ لم يُغلق أي Workstream دون اختبارات المشروع والأجهزة.
- [دليل المزامنة وإصدار ZIP](./FABLE-CROSS-REPO-SYNC-RC86.ar.md) · [سجل البصمات الآلي](./FABLE-CROSS-REPO-SOURCE-PAIR-RC86.json).

---

## RC85 — عمليتا OTP/2FA كاملتان على مستوى مراجعة المصدر

- **Fable RC66:** مراجعة وفصل `auth.2fa.login.request` و`auth.2fa.login.complete`؛ قبل إرسال `twoFactorToken` أو OTP يتحقق Flutter من `operationId/method/path/auth`، ويفحص طريقة التحقق والقناة والمهل وUUID.
- **معلومات الجهاز:** `deviceName` و`appVersion` اختياريان، يُتحقق منهما قبل Login ويُعاد استخدامهما في إكمال 2FA؛ لا يُستنبط GPS/IP أو اسم هاتف غير موثوق. رسائل الحد الفاشل وجهاز آخر يصدرها Backend عبر Outbox، مع بقاء FCM اختيارياً وفق القدرة المثبتة.
- **Other Backend:** `ExternalAuthBinding` الحالي لا يملك عقد MFA عاماً. لا نعرض 2FA لـOther تلقائياً؛ تسجيل المتطلبات والـWizard ما زال مفتوحاً لحين Adapter وعقد واختبارات مستقلة.
- **الإحصاء:** **9/40** `SOURCE_IMPLEMENTED_E2E_PENDING`، و**31/40** `NOT_DECIDED`، و**0/17 E2E**. نجاح مصدر/CI لا يعني اختبار OTP أو Push على جهازين حقيقيين.
- [دليل RC85 التفصيلي](./FABLE-AUTH-BASELINE-RC85.ar.md) · [جرد عمليات Auth](./FABLE-AUTH-OPERATIONS-RC80.json).

---

## RC84 — قفل تغيير كلمة المرور والتحقق من انتهاء الجلسة وRefresh Replay

- **بناء على سلوك Fable RC66 الحقيقي**: Login العادي و2FA يعيدان `mustChangePassword`؛ في حال تفعيل القفل يُرجع JwtAuthGuard `AUTH_PASSWORD_CHANGE_REQUIRED` / 403 للمسارات المحمية، باستثناء التغيير والخروج. طبّقنا عرضاً مقيداً وخيارات Change Password/Logout، مع منع ادعاء صلاحية Sessions العادية.
- Gateway يرفض حفظ اعتماد جديد إن غاب `mustChangePassword` Boolean أو `expiresAt` UTC صالح ومستقبلي؛ ويحتفظ بالجلسة المحلية عند Refresh 409 داخل Grace أو 503 مؤقت، بلا تكرار Refresh token قديم. عند 401 نهائي يبطل الاعتماد الخاص بنفس الهوية فقط.
- أضيفت اختبارات للمسار العادي، و2FA، واستعادة جلسة محفوظة، وReplay وExpiry؛ مع شرح التعليقات بالعربية.
- **الإحصاء ثابت:** 7/40 `SOURCE_IMPLEMENTED_E2E_PENDING`، 33 `NOT_DECIDED`، و**0/17 ميزات معتمدة E2E**؛ لا تعني تقوية Login/Refresh اكتساب عملية جديدة.
- **مفتوح:** Backend مولّد حقيقي/MySQL، جهازان، ملكية Identity والأحداث الأمنية، Android/iOS Release، عقد Other Backend مستقل، والـWizard الفعلي.
- [دليل RC84 التفصيلي](./FABLE-AUTH-BASELINE-RC84.ar.md) · [الدفعة السابقة RC83](./FABLE-AUTH-BASELINE-RC83.ar.md).

---

## RC83 — تدقيق أساس Auth وتثبيت عقد الجلسات

- **الجديد على فرع RC83:** تدقيق `auth.login`, `auth.refresh`, `auth.sessions`, `auth.session-policy` مقابل طريقة ومسار ومصادقة Fable الحقيقية؛ منع الاتصال عند اختلاف العقد، وحماية Refresh Token، وعرض سياسة الأجهزة من Runtime لا من Wizard، ونقل حالة أمن الجلسة إلى DTO وواجهة المراجعة.
- **الإحصاء المرحلي:** 7 من 40 عملية Auth لديها تطبيق/مراجعة مصدرية واختبارات مكتوبة، و33 عملية `NOT_DECIDED`؛ ما زال عدد ميزات Flutter المعتمدة E2E **0 من 17**. لا تساوي كتابة الاختبار نجاح CI؛ ولا يساوي نجاح CI اعتماد Backend حقيقي.
- **مرجع الفحص والتصميم:** [RC83 التفصيلي](./FABLE-AUTH-BASELINE-RC83.ar.md) و[جرد العمليات الـ40](./FABLE-AUTH-OPERATIONS-RC80.json).
- **الخطوات المفتوحة:** تشغيل اختبارات CI، اختبار توليد عقد مشروع فايبل فعلي مع DB/جهازين Android+iOS، 401/409/429 و2FA/Refresh Replay/Session Limits، وربط عمليات Other Backend في Wizard بشكل مستقل. لا إعلان اكتمال Auth قبل تحققها.

---

## 1. المرجعية وكيف لا نعود إلى دوامة الإصلاحات

- **المصدر الآلي:** [FABLE-FLUTTER-PARITY-MASTER.json](./FABLE-FLUTTER-PARITY-MASTER.json) = 17 ميزة مرجعية، مع ملفات تنفيذ حقيقية ومتطلبات Backend خارجي ونواقص. لا توجد ميزة عليها `complete=true` أو `liveE2EVerified=true`.
- **جرد Auth التفصيلي:** [FABLE-AUTH-OPERATIONS-RC80.json](./FABLE-AUTH-OPERATIONS-RC80.json) = 40 عملية بأسمائها وأساليبها ومساراتها والصلاحيات. أغلبها `NOT_DECIDED`، و7 عمليات (RC81: `auth.change-password`؛ RC82: `auth.logout`, `auth.session.timezone`؛ RC83: `auth.login`, `auth.refresh`, `auth.sessions`, `auth.session-policy`) أصبحت `SOURCE_IMPLEMENTED_E2E_PENDING` فقط؛ و33 عملية أخرى ما زالت `NOT_DECIDED`. يحظر CI إعلان اكتمال دون دليل E2E.
- **RC82 أساس Auth:** [فروق Logout وSession Timezone ومتطلبات Other Backend](./FABLE-AUTH-BASELINE-RC82.ar.md). **RC83:** [Login/Refresh/Sessions/Runtime Session Policy ومطابقة الباك الآخر](./FABLE-AUTH-BASELINE-RC83.ar.md).
- **23 قراراً عاماً يؤثر على جميع الميزات:** [الجرد الآلي](./FABLE-BACKEND-WIDE-DECISIONS-RC81.json) و[الشرح بالعربية](./FABLE-BACKEND-WIDE-DECISIONS-RC81.ar.md). هذه السياسات تشمل هوية المستخدم والجلسات وHTTP والتكرار الآمن وحفظ البيانات والصلاحيات والكاش؛ منها ما يُستورد من العقد ومنها ما يجب قراءته من Runtime أو يبقى Backend-only.
- **الفحص:** `node tools/verify-feature-parity-master.mjs` يحرس عدد الميزات والملفات وملكية القرار والـWizard/Other Backend. عند توفر نسخة محلية من Fable Backend نفّذ `node tools/verify-feature-parity-master.mjs --backend-root ../Fable --output ./parity-review.json` لفهرسة **كل عملية في كل Manifest**؛ كل عملية تظهر `NOT_DECIDED` حتى يراجعها المسؤول يدوياً. الخيار `--require-exhaustive` يُبقي بوابة إكمال النقل حمراء حتى يتوفر إثبات عمليات كامل.
- **مرجع النواقص على GitHub:** [Issue #15](https://github.com/adnan118/Fable_flutter/issues/15) لا يُغلق بالتقدم في عدد PR؛ يُغلق فقط بالاختبارات الحية لجميع الميزات المطلوبة في مشروع محدد.
- **التوثيق التعليمي:** [FLUTTER-BLOC-LEARNING.ar.md](./FLUTTER-BLOC-LEARNING.ar.md)، و[Wizard](./FRONTEND-SETUP-WIZARD.ar.md).
- **قاعدة التقدم:** لا ترفع رتبة الميزة بمجرد وجود `Repository` أو شاشة أو `flutter analyze` ناجح؛ مخرجات CI تُثبت أن الشيفرة تبني ونجحت الاختبارات المكتوبة فقط.
- كل PR مستقبلي يجب أن يذكر: **الميزة → عملية Backend → Flutter Model/Repository/UI/BLoC → Wizard Fable/Other → العقد الخارجي المطلوب → الصلاحيات/الأخطاء/الإشعارات/Offline → اختبارات**. إذا غاب حقل، يتم تسجيله `GAP` لا `DONE`.

## 2. لماذا لا تكفي عبارة «17 ميزة موجودة»

`FEATURE_IDS` يحدد 17 **عائلة واجهة**. Backend يحتوي تقريباً 50 Capability Manifest في `blueprints/capabilities`؛ ليس معنى ذلك أن كل Cap مثبتة في المشروع ولا أن كل عملية يجب أن تصبح شاشة موبايل. أمثلة من Manifest على `main`:

| Capability بالباك | عدد العمليات المسجلة في Manifest | القرار قبل النقل |
|---|---:|---|
| `auth` | 40 | تدقيق Login/Refresh/Sessions/2FA/OTP/Email/Phone/Password/Social؛ الفصل بين موبايل و`/auth/web/*` والإدارة |
| `managed-accounts` | 18 | ربط جميع حالات OWNER/MANAGER/VIEWER والعضوية والكيان العام، لا `list/activate` فقط |
| `financial-platform` | 46 | فصل المستخدم عن عمليات الأدمن والـWebhooks؛ عدم اعتبار قراءة Payment كاملة |
| `content-pages` | 19 | قراءة ونشر ومحرر Admin وقبول الموافقة؛ **Issue #12 غير معتمد** |
| `media` | 16 | `prepare/status/chunk/parts/complete/abort` والمشاهدة المحمية |
| `location-platform` | 15 | الخرائط/المسارات/التحويل/السياج/المؤشرات حسب مشروع العميل |
| `access-control` | 6 | `permissions.me` لا يغني عن منح/إسناد/سحب الأدوار |
| `passkeys` | 6 | تسجيل/تحقق/حذف مع تمييز Web-only |
| `notifications` + `push-notifications` | 3 + 3 | Inbox/Read وتسجيل الجهاز وإبطاله وعقود العميل، ثم FCM فعلي |
| `languages` | 2 | لائحة اللغات ليست نظام ترجمة واجهة ومحتوى كامل |
| `realtime-communications` | 3 | LiveKit/Join/Disconnect ≠ SSE لتحديث المحتوى |
| `phone-messages` | 2 | Webhooks واردة؛ ليست عقد إرسال رسائل من الموبايل |

**قاعدة المقارنة:** راجع جميع المسارات وفق `method + path + operationId + auth + role + request/response DTO + errors`. صنّف كل واحد `MOBILE_REQUIRED / ADMIN_ONLY / WEB_ONLY / SERVER_ONLY / NOT_INSTALLED / UNDECIDED` مع السبب والمرجع. عند عدم وجود عقد حقيقي مُثبت للمشروع تبقى `UNDECIDED` ولا تعلن `100%`.

## 3. الإحصاء الحالي للفرونت (من دون ادعاء E2E)

العلامة **مصدر وشاشة** تعني وجود شيفرة وشاشات لبعض العمليات؛ **Repo/Widget** لا تعني اكتمال سير العمل؛ **محلي** يعتمد على Flutter. جميع الصفوف غير مكتملة على مستوى اعتماد المشروع الفعلي.

| الميزة / ملكية القرار | ما نُفّذ ويمكن إثبات مصدره | ما لم يثبت أو يجب إكماله |
|---|---|---|
| **Auth** — Server | Login/Refresh وجلسات الموبايل جزئياً؛ **RC81** تغيير كلمة المرور، **RC82** تأكيد Logout وتحديث المنطقة الزمنية، **RC83** تدقيق طريقة/مسار/مصادقة Login/Refresh/Sessions/Session-policy وعرض سياسة Runtime وحالة أمن الجلسة | **7 من 40** عمليات لديها شيفرة/اختبارات مصدرية بانتظار تشغيل التحقق؛ **33** لم تُحسم، وE2E/Other/Wizard غير معتمدة |
| **Profile** — Hybrid | الحساب الأساسي/اسم العرض؛ RC71 تفاصيل الكيان وتعديله؛ RC78 إنشاء الكيان والدعوات العامة ومدير/مشاهد؛ RC79 سياق الكيان المتطاير؛ أعضاء/دعوات/OTP متوفرة في المصدر | الـ18 عملية وسلوك العضويات والكيانات الحقيقية، تفعيل سياق الكيان في **كل** عملية مشروع تحتاجه، مستخدمون حقيقيون وصلاحيات Admin/multi-profile |
| **Notifications** — Hybrid | Inbox/Read، ربط تنقل إشعار، تسجيل Push وتخزين التوكن وربطه بجلسة من بعض الأجزاء | ترحيب/سياسة/جهاز جديد/حد فشل ضمن DB/Outbox/FCM، إلغاء التوكن واللغة والخلفية/المقدمة وPush فعلي |
| **Media** — Hybrid | Repository للرفع والأجزاء والحالة والقراءة وواجهة رفع | كل 16 عملية بما فيها protected playback/refresh/end، التخزين R2 وتجربة استئناف، أذونات وحصص وعمل على الأجهزة |
| **Localization** — Hybrid | RC77 حفظ اختيار لغة الواجهة، سياسة اللغات المولدة وشاشة اختيار، قائمة اللغات ونصوص مزامنة | تعريب/ترجمة كل شاشة ومحتوى ديناميكي وRTL وأخطاء ومزامنة Offline عبر جميع الميزات |
| **Support** — Server | حزمة UI/Repository محدودة | لا Manifest باسم Support في Fable العام؛ يجب الحصول على عقد المشروع الفعلي قبل بناء دورة التذاكر والردود والتصعيد |
| **Social** — Server | Provider adapter/Widgets لـGoogle وApple وربط الحساب | SDK/native callback وnonce/state وLink/Unlink وMFA وتصادم البريد وWizard بحسب تمكين الخادم |
| **Biometrics** — Hybrid | Adapter للـPasskeys وWidgets | تسجيل وحذف Passkeys على أجهزة حقيقية، تحديات WebAuthn، الفصل بين بصمة محلية ومصادقة خادم |
| **Realtime** — Server | SSE لتغييرات عامة ومنسق تحقّق | RTC/LiveKit وWebSocket والمصادقة والاستئناف/التراجع عن الصلاحية وBackground حسب العقد |
| **Deeplinks** — Client | سياسة رابط وDispatcher محلي | Universal/App Links والتوثيق على النطاق وتأجيل المصادقة وإجراء التحقق من روابط إشعارات |
| **Messaging** — Server | Repository/Widgets محدودة | لا نعامل Webhooks WhatsApp الواردة كـSend API؛ يلزم عقد قائمة/إرسال/قراءة/حذف ورفع مرفقات وPermissions |
| **Location** — Hybrid | Repository/Widgets | 15 عملية خدمات موقع، صلاحيات/خريطة/خصوصية/خلفية/سياج/خرائط Native واختبار جهاز |
| **Payments** — Server | Adapter/Widgets لحالة Payment وبعض العقود | 46 عملية Finance؛ Checkout/Refund/Capture/UNCERTAIN/Provider/Store billing وAdmin منفصل وE2E حقيقي |
| **Offline** — Client | طابور تفاعلات محلي وحالات Offline UI | **SQLite + Drift** ووضع Wizard الاختياري وكاش GET/طوابير الكتابة حسب عملية الباك، حل التعارض وإعادة التحقق المالي |
| **Analytics** — Hybrid | Repository لجمع أحداث محدود | موافقة الخصوصية، عقود أحداث/أهداف/Reports حقيقية، لا افتراض أن Monitoring داخلي = Analytics عميل |
| **Content** — Server | عرض وقراءة صفحات منشورة وقبول نسخة، Renderer نص منظم | بلوكات المحتوى الكاملة حسب العقد، المحرر حسب الدور، Issue #12 ونشر الخصوصية المجدول مع اختبار MySQL/Worker |
| **Access Control** — Hybrid | Snapshot، `AccessScope`، منع UI عند غياب المنح وتحديث بعد رفض الطلب | كافة عمليات Roles وإدارة الإسناد إن كان التطبيق إدارياً، صلاحيات الكيان، إبطال الـGrant والمراقبة الفعلية |

**خلاصة رقمية ذات معنى:** 17 ميزة معرفة؛ 6 فيها شاشات/مصادر لبعض المسارات، 8 فيها Repository وواجهة جزئية، 1 Repository فقط (Analytics)، و2 محلية (Offline وDeeplinks). **0 من 17 حاصلة على اعتماد E2E شامل**. لا تحوّل هذا الإحصاء إلى نسبة «اكتمال»؛ تفاوت العمليات كبير (Auth 40 وLanguages 2).

## 4. الباك الآخر — متطلبات واضحة ولا مسارات Fable مخفية

### الأولوية الأولى في الـWizard

1. **هل Backend هو Fable؟** هذا أول سؤال.
2. **Fable:** استيراد `dist/client-contract` مع بصمة المشروع `projectId` و`contractHash` من قناة مستقلة، عرض الفروقات، ثم طلب موافقة. الخيارات الأمنية (الجلسات وطرق الدخول والـRoles والـProfiles واللغات) يحددها الباك، ولا يسمح بإعادة تعريفها في Flutter على هواه.
3. **Other Backend:** `openapi` أو `custom`، يبدأ **pending** وليس جاهزاً. لا يفعّل Login/OTP/Google/Apple/FCM/Payments/Role UI من التخمين. يستورد كتالوج عمليات حقيقي ثم يطلب خريطة لكل ميزة وتحقق من هوية المصدر.
4. **الاختيارات الخاصة بFlutter:** الثيم/الأيقونات/Offline/التخزين المحلي/واجهة المستخدم واللغة المرئية لا يحذفها غياب Capability بالسيرفر؛ أما مزايا الشبكة فتحكمها القدرة المثبتة.
5. **عند تغيير Backend:** امنع استخدام عقد Fable القديم، وامسح/اعزل السياقات والكاش والتوكنات والـPush والـOffline namespace. لا تنقل صلاحيات مشرف/مالك بين الخادمين.

### ما يجب أن يقدمه Backend الآخر (حسب النوع)

| ميزة | الحد الأدنى قبل إظهار واجهتها العاملة |
|---|---|
| Auth | endpoints صريحة + Auth scheme + طلب/استجابة/الأخطاء + سياسة الجلسات وOTP/Providers إن كان مدعوماً + خريطة حقول JSON |
| Profile/Accounts | GET/PATCH Profile؛ subaccounts/roles/invites/context إن وُجدت، ومعرّف كيان وصلاحيات دقيقة |
| Notifications/Push | Inbox/Read، Token register/unregister، أنواع الأحداث وTTL واللغة وربط الجهاز |
| Media | Upload contract (single/parts/resume/abort) وDownload/Playback ACL والحجم والصيغ |
| Localization | supported tags, default, RTL, revision, fallback، وترجمة النصوص الديناميكية |
| Support/Messaging | list/create/reply/read/status، أذونات، ملفات، pagination وأخطاء |
| Social/Passkeys | Provider SDK flow أو WebAuthn challenge/verify وتطابق أصل التطبيق والجهاز |
| Realtime | transport، channel permissions، reconnect/cursor، auth refresh |
| Location | capabilities/providers/geocode/nearby/route، سياسة الخصوصية والصلاحيات |
| Payments | provider checkout/status/idempotency/UNCERTAIN/refund/currency، webhook server validation |
| Content | published page/version/blocks/consent + صلاحيات التحرير إن كانت الإدارة داخل التطبيق |
| Access Control | per-operation permission snapshot/roles/revocation ومنع منح الصلاحية بواسطة UI |
| Offline/Deeplinks/Analytics | Offline delta/versions/conflict إذا كان يدعم Sync؛ رابط عميق مرخّص؛ Analytics بموافقة المستخدم؛ وإلا تبقى هذه إمكانات محلية أو غير مفعّلة |

**الملفات المطلوبة عند الاستيراد (حسب الموجود في الشيفرة):**
- `assets/contracts/external-operations.json`: `schemaVersion=1`, `kind=fable.external-operation-catalog` (اسم تنسيق Flutter)، `adapter=openapi|custom`, `sourceHash`, `operationsHash`, `baseUrl` آمن، وعمليات `operationId/method/path/auth`.
- `assets/config/feature-operations.json`: `kind=fable.feature-operation-bindings` مع خريطة عمليات مصرح بها لكل `feature` و`role` و`sourceHash/operationsHash` المطابقين.
- `assets/config/external-auth.json`: `kind=fable.external-auth-binding` وفيه Login إلزامي، Refresh/Logout اختياريان بحسب العقد، وJSON field selectors محددة.
- `assets/config/profile-fields.json` إذا كان Profile خارجي: `displayName/email/avatarUrl`، مطابقة عملية `profile.read` الموثقة.
- **حالة اليوم:** يوجد أساس `ExternalLoginPage` و`ExternalProfilePage` وخريطة عمليات آمنة، لكن ليس هناك 17 مسار External كامل. **لا يجوز نقل UI Fable إلى Other كما هو**؛ يجب Adapter وMapping وContract Tests مخصصان.

## 5. سجل الثغرات والتعارضات

| الشدة | الدليل / الخطر | المعالجة المطلوبة |
|---|---|---|
| **حرج — اعتماد** | Backend [PR #13](https://github.com/adnan118/Fable/pull/13) و[Issue #12](https://github.com/adnan118/Fable/issues/12) لم ينجح لهما CI تشغيلي؛ نشر الخصوصية المجدول/القبول/الإشعار لم يُختبر على DB/Worker حي | لا تدمج/تطلق السياسة قبل اختبار MySQL/Outbox/FCM وتزامن الإصدارات |
| **حرج — Auth** | 40 عملية Auth في Manifest؛ مصادر Flutter لا تعني اكتمال 40 عملية؛ PRs Backend [#5](https://github.com/adnan118/Fable/pull/5) و[#6](https://github.com/adnan118/Fable/pull/6) غير مدمجين (منع drift وعزل Cache المصادقة) | مراجعة جميع العمليات وDTOs/UX/Session/Step-up؛ تشغيل اختبارات الباك على Runner سليم |
| **عالٍ — مالية وإشعارات** | Backend [#7](https://github.com/adnan118/Fable/pull/7) مفتوح للتدقيق حول provider uncertainty وFCM؛ وفارق كبير بين Payment read و46 عملية مالية | ضبط سيناريو UNCERTAIN، عدم تكرار التنفيذ، إغلاق مسارات الإدارة عن العميل، واختبار Provider حقيقي |
| **عالٍ — تكامل** | عقد `ci_fable` الافتراضي يحوي 9 عمليات Demo فقط، لا يعكس كل قدرات مشروع فعلي | استيراد عقد مشروع مولد بهوية مثبتة؛ تقرير كل عملية `MAPPED/EXCLUDED/MISSING` |
| **عالٍ — سياق وصلاحيات** | RC79 يجعل الكيان المختار متاحاً محلياً، لكن لا يربطه آلياً بعمليات المشروع | Gate مستقل بكل Repository، Cache partitioning، اختبارات Revocation وحسابات متعددة |
| **عالٍ — Other Backend** | External Auth + Profile وبعض الربط موجود؛ باقي الميزات تحتاج Adapter وDTO/UI مخصصين | تعاقد صريح `other` للـWizard، تدقيق كل حقل/Role/Error/Transport قبل إظهاره |
| **متوسط — وثائق** | دليل RC68 سابق على RC71–RC79؛ لا يصلح كحالة حالية | هذا السجل يحل مكانه كمرجع أحدث؛ التاريخ/baseline في كل تعديل |
| **متوسط — تعليم Flutter** | UI الحالية تستخدم StatefulWidget/Repositories في أجزاء كثيرة؛ لا تفترض Bloc مكتمل أو موحداً | اعتماد أسلوب تعليمي تدريجي واختبارات مستقلة، مع تعليق عربي عند حدود Auth/Backend/Identity |

## 6. بوابة نقل **أي ميزة بالكامل** (تعريف لا يقبل الاختصار)

لا تكتفِ باسم الميزة. أكمل لكل `operationId`:

1. **اكتشاف:** هل Capability مثبتة في المشروع أم في Blueprint العام فقط؟ هل هذه العملية للموبايل أم Admin/Web/Server؟ سجّل السبب، ولا تحذفها من الإحصاء.
2. **عقد كامل:** `method/path/query/path params/headers/body/response` بكل الحقول والأنواع وNullable وEnums والمصفوفات والحجم والصفحات والوقت والعملة.
3. **أمان:** Auth/OTP/MFA/step-up/Role/EntityScope/Provider signature/Origin/Rate-limit/idempotency؛ كل منح صلاحية من الباك.
4. **Frontend:** Model immutable + Repository/API Gateway + states/errors + شاشات إدخال/قراءة/تأكيد وEmpty/Loading/Denied/Offline/Expired.
5. **BLoC/Cubit حيث يناسب:** أحداث/حالات/انتقال، والتخلص من استجابات قديمة بعد Logout/Account switch. لا تضف BLoC شكلياً لمجرّد الظهور.
6. **التزامن:** Caching/Offline/Sync/FCM/Realtime/invalidation مع عدم إعادة العمليات المالية غير الآمنة.
7. **Wizard Fable:** قرارات Backend كما صدّرها، وتحقق من أن كل عملية عرضتها الواجهة مثبتة في العقد المختار.
8. **Wizard Other:** وثّق بالاسم كل طلب API وحقول Response/Errors/Privileges المطلوبة، واربطها بكتالوج Other الفعلي؛ لا تنسخ Path من Fable.
9. **اختبارات:** unit+widget+contract+mutation/concurrency+failed login/offline/403/409/429+Android+iOS + E2E حقيقي بشاهد يوضح المشروع والدور والحالة.
10. **تعليقات عربية وروابط docs:** عند كل حد أمان أو اختيار تصميم صعب؛ راجع [دليل Flutter/BLoC](./FLUTTER-BLOC-LEARNING.ar.md).
11. **المخرجات:** تحديث هذا السجل والـJSON وIssue #15، وذكر **قائمة العمليات المتبقية** بوضوح. لا تستبدلها بعبارة «الميزات أصبحت كاملة».

## 7. أوامر استعمال السجل

```bash
# من جذر Fable_flutter: فحص ثبات 17 ميزة ووجود الملفات ومطالبات الاكتمال
node --test test/feature-parity-master.test.mjs
node tools/verify-feature-parity-master.mjs

# من جذر Fable_flutter مع نسخة محلية من Backend Fable المراجع
node tools/verify-feature-parity-master.mjs --backend-root ../Fable --output ./parity-review.json

# صرامة اعتماد العمليات: مقصود أن تفشل إلى أن تصنف جميع العمليات فعلياً
node tools/verify-feature-parity-master.mjs --backend-root ../Fable --require-exhaustive
```

**ملاحظة:** `--backend-root` يقرأ مصدر Blueprint الحالي كله ويخرج تقريراً بكل Operation، لكنه لا يؤكد أن العملية مثبتة في عقد المشروع الفعلي؛ يجب مقارنة النتيجة مع تصدير `dist/client-contract` المثبت ببصمة مستقلة. كما أنه لا يصنّف تلقائياً المسار بأنه «منقول بالكامل» لمجرد وجود نصّه في Flutter.

**الترتيب القادم:** إغلاق فجوات Auth عملية عملية أولاً (بما فيها أساس 2FA/Sessions والعمليات الغائبة)، ثم Profile/Managed Entities حسب السياق والصلاحيات، Notifications/Content القانونية، Localization، Media، ثم باقي القدرات والأدوار والواجهات — مع تثبيت الفحوص في كل دفعة.

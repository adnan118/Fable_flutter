# خطة المطابقة التفصيلية: Backend ↔ Fable Flutter

## لماذا نحتاج هذا الفحص؟
وجود ميزة في Preset أو ظهور زر في الواجهة لا يعني نقل كل طلبات واستجابات وأخطاء وصلاحيات Backend إلى Flutter. لهذا فصلنا ثلاثة مستويات:

1. **قرار الميزة**: هل الباك فعّلها لهذا المشروع؟ (`frontendSetup.decisions.frontendFeatures`)
2. **وجود الربط في الكود**: هل يوجد استدعاء لعملية Backend ذات `operationId` موثق؟
3. **التكامل الكامل**: هل يوجد Model/Repository/UI/Permissions/Errors/Offline/Tests حقيقية ومتوافقة مع العقد؟

الأداة `node tools/audit-backend-feature-parity.mjs` تقرأ العقود المستوردة وتكتب `.fable/feature-parity-report.json`.

حالات التقرير:
- `SOURCE_WIRED_NOT_LIVE_TESTED`: وُجد المرجع في ملف كود معروف، لا يعني اكتمال الواجهة أو اختبار الطلب على الخادم.
- `NOT_MAPPED`: لا يوجد تنفيذ موثوق محدد في سجل المطابقة.
- `MAPPING_STALE`: مرجع التنفيذ لم يعد موجوداً/لا يطابق عملية Backend.
- `NOT_FOR_FLUTTER`: عملية Web-only معلومة.

**الأداة لا تعلن إطلاقاً عن Production Ready** بمجرد وجود كود.

## تقدم تنفيذ Auth — إدارة الجلسات (بعد فصل القرارات المحلية)

**نُفّذ في الكود:**
- نموذج `FableActiveSession` يقرأ ويصادق على الحقول العامة التي يصدرها `GET /auth/sessions` مثل الهوية، والجهاز الحالي، ونوع المنصة، والتواريخ، ويرفض السجلات الفاسدة والمتكررة.
- `FableAuthGateway.listActiveSessions()` يجلب الجلسات من الخادم عبر Operation ID المعلن، لا من كاش التوكن المحلي.
- `FableSessionsPage` تعرض الأجهزة النشطة، وتحدّث القائمة، وتقرأ `GET /auth/session-policy` عند توفره وتعرض سياسة الخادم الفعلية دون اختراع سياسة افتراضية.
- شاشة Login تفتح إدارة الجلسات **بعد نجاح المصادقة فقط** عند وجود العملية في العقد.
- تقرير المطابقة يميز بين وجود Gateway ووجود UI وعدم اكتمال اختبار Runtime. أُضيفت اختبارات التحقق من بيانات الجلسات.

**غير مكتمل عمداً، ولا يجوز إظهاره كميزة عاملة:**
- إلغاء جهاز آخر / مجموعة أجهزة / تسجيل الخروج من الكل؛ هذه العمليات تتطلب Security Step-up من Backend، وتحتاج نقل عقد إثبات التحدي والرأس الأمني والتحقق من رد الخادم.
- إبطال Push token للجلسة الملغاة، ومزامنة حدث فقدان الهوية مع إشعارات التطبيق.
- اختبارات E2E فعلية على خادم مولّد مع أجهزة متعددة وAndroid/iOS.

## قاعدة الحذف النهائية

ملف `tools/frontend-feature-ownership.mjs` مملوك لFlutter، وليس للباك. كل Feature مصنفة `server` أو `hybrid` أو `client`. حزم `hybrid` و`client` لا تحذف بسبب تعطيل API في الباك، حتى لو لم تُعرض الشاشة التي تعتمد على API. اختياراتها المستقلة محفوظة في `.fable/frontend-owned-decisions.json`، ويُعرض الفرق في تيرمنال Wizard قبل الموافقة.

## نقطة البداية — Auth/Session

يعلن Backend Capability Auth RC66 نحو 40 عملية، منها:
- Login/Refresh/Logout + Logout All.
- إدارة الأجهزة والجلسات (سرد، إلغاء جهاز، إلغاء مجموعة، السياسات والمنطقة الزمنية).
- Local identity، Username، الحساب الأساسي.
- OTP عام ومصادق عليه، Password reset، تغيير Email/Phone.
- 2FA تفعيل/تعطيل وإكمال تسجيل الدخول.
- Google/Apple login/link/unlink، Challenge.
- Web Cookie flows (لا تنقل إلى تطبيق Flutter Bearer كما هي).

ما نعرف أنه موجود بالكود الحالي:
- تسجيل الدخول بالبيانات وRefresh rotation.
- 2FA على مرحلتين في صفحة Login/موصل Auth.
- Logout الحالي وقراءة حساب Fable الأساسي واسم العرض.
- استدعاء سرد الجلسات وقراءة السياسة الفعلية.
- Provider adapter لـGoogle/Apple في حزمة `fable_social`.
- Passkey adapter في `fable_biometrics` (تحقق من عقد Capability مستقل).

ما لا يجوز اعتباره مكتملًا بمجرد وجود هذه العناصر:
- واجهة عرض الأجهزة والجلسات أصبحت مرتبطة بعقد Backend؛ تبقى واجهات الإلغاء مع Step-up Proof قيد العمل.
- شاشات 2FA Enable/Disable وإدارة قنوات OTP.
- جميع مسارات Email/Phone/Username Security وPassword Policy.
- الربط/فك الربط الاجتماعي، معالجة Same-email link_required على واجهة نهائية.
- حقوق Managed Accounts وتعدد Profiles في UI/Navigation.
- اختبارات جهازين حقيقيين، التزامن، Refresh replay، انتهاء الجلسة، وتسجيل Push token.

## عملية المطابقة المطلوبة لكل Feature

لا تعتبر الميزة منقولة بالكامل حتى يراجع المبرمج **كل `operationId`** ويثبت:
- عقد الطلب والمعلمات والرؤوس وBearer/Cookies/2FA وأكواد الأخطاء.
- نموذج البيانات والحقول وحالات Nullable/Enum والمتغيرات المالية أو المحجوبة.
- Repository/API Gateway وCache/Offline/Sync وتنبيهات التغيير.
- الشاشات والنماذج ومراجعة الصلاحيات والـRole-Based Layout.
- اختبارات وحدة وتكامل ضد Backend تجريبي، ثم اختبار Android وiOS.
- قرار واضح للمزايا الخاصة بـWeb أو Admin أو Backend only، فلا تُنشأ لها شاشات زائفة.

بعد Auth: Accounts/Profiles/Managed Entities ثم Localization ثم Notifications ثم Media ثم بقية القدرات بحسب عقود المشاريع المصدرة. يجب الحفاظ على هذا الترتيب لأن كل ميزة تستند إلى السابقة.

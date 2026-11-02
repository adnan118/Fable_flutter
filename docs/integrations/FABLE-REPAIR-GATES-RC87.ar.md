# خطة الإصلاح التنفيذية — Fable Backend ↔ Flutter — RC87

> **المرجع الحاكم:** `adnan118/Fable` (خاص) و`adnan118/Fable_flutter` (عام). هذه وثيقة بوابات لا إعلان اكتمال. نفّذها بالترتيب ولا تُسقط أي عملية فرعية أثناء الانتقال.

## جرد مثبت قبل البدء

| البند | وضع المراجعة | معيار الإغلاق |
|---|---|---|
| Backend main وقت تدقيق RC86 | `226cbcdc542ebe9c005d7445d84cc0ec10631932` | لا تغيير غير مراجع داخل `Fable-Backend-RC66/` |
| Flutter RC86 main | `9bd524a70f3cb32699ab712dded25f62b71b7e30` | CI ثلاث وظائف ناجحة |
| Backend Blueprint Capabilities | 50 manifest موجودة عند التدقيق | تعداد ثابت وقراءة manifest لكل قدرة، لا مجرد تعداد مجلدات |
| Auth method/path operation inventory | 40 عملية متطابقة | تطابق `id+method+path` مع مراجعة DTO/الأخطاء والسياسات منفصلة |
| Auth source reviewed | 9/40 | الباقي 31: لا يرقّى أي بند دون فحص Controller+Service+DTO+Tests+واجهة |
| Full live E2E | 0/17 | مشروع مولّد حقيقي + API + DB + اختبارات Android/iOS المتفق عليها |

## P0 — إصلاح إصدار الحزمة والمزامنة الآمنة

**المشكلة المكتشفة:** CI في ريبو Backend الخاص يفشل قبل بدء Job Steps، حتى لو كانت مهام Flutter سليمة؛ لا توجد سجلات تساعد على اتهام كود التغليف. كما أن فحص RC86 كان يطابق Auth دون قفل بقية مصدر Backend.

**تنفيذ RC87 في Flutter:**

1. حارس Git يتحقق من أن SHA المدققة سلفاً هي سلف لنسخة Backend الحالية **وأن جميع الملفات تحت `Fable-Backend-RC66/` بقيت بلا تغيير**، حتى مع تحديث Workflows والتوثيق الخارجي. يجب على CI سحب تاريخ Backend بـ`fetch-depth: 0`.
2. إلزام جميع الـ50 Capability Manifests ورفض غياب واحد أو تغيّر العدد دون مراجعة. لا يعني هذا أن 50 Capability لديها 50 شاشة أو تكامل Flutter معتمد.
3. عندما يوجد سجل `docs/RC86-SOURCE-PAIR.json` في Backend الخاص، يلزم التطابق الحرفي مع SHA الخاصة بـFlutter checkout.
4. ZIP من `git ls-files` فقط، بعد التأكد من **نظافة شجرة Git**؛ لا يجوز أن تحمل ZIP ملفاً عُدل محلياً ثم تنسبه إلى commit سابق.
5. حماية أسماء الملفات الحساسة والمفاتيح، وSHA256 لكل ملف في ZIP وCRC، وسجل أسماء الملفات المستبعدة وSHA للريبوين، وقفل منع النشر في مستودع Flutter العام.
6. اختبارات آلية على Git fixtures وهمية لتغيير مصدر Backend، وتزوير Flutter pin، وإفساد SHA256، وإدخال `.env` و`google-services.json`، وتعديل ملفات متتبعة دون commit.
7. **بقاء Backend PR #14 مفتوحاً** حتى تتاح CI الخاصة أو يوجد دليل بديل معتمد؛ فشل التشغيل قبل الخطوات لا يُعد نجاحاً ولا فشلاً وظيفياً للـZIP.

**تشخيص GitHub Actions للريبو الخاص:** فحص `Settings → Actions → General`، و`Billing & licensing → Actions` للرصيد/الحدود، وصلاحية تشغيل private GitHub-hosted runner. شغّل Workflow اختبار بسيطاً بلا Checkout لمقارنة الفشل. إن بقي بلا Steps أو Logs، تعامل معه كعائق حساب/Runner واطلب الدعم، لا كاختبار للمصدر. يجب الحفاظ على سرية Backend. 

## P1 — إغلاق المصادقة Fable ميزة بميزة، لا مسارات متناثرة

ابدأ بعد قبول P0 أو إذا بقي عائق CI موثقاً مع استمرار العمل على فروع غير مدمجة:

- **OTP و2FA:** لكل عملية `request/verify/complete/resend` موجودة فعلاً في Backend، استخرج Controller وDTO وService وrate-limit وexpiry وerror codes وpermission/public. لا تُنشئ مسار `resend` أو حد محاولات من افتراض. في Flutter أضف Gateway وBLoC/State والواجهات والأخطاء والاختبارات المرتبطة بعقد العملية ذاته. اختبر إعادة إرسال بعد cooldown، وانتهاء Challenge، وتضارب الأجهزة، وفقد الشبكة، ونجاح/فشل الطلب.
- **Password reset/change + step-up:** افصل العمليات العامة عن المشروطة بجلسة؛ لا تسرب كشف وجود الحساب. تحقق من استهلاك OTP وعدم إعادة استخدام الرمز ومن سياسة كلمة المرور وإبطال الجلسات ومنع الدخول عند `mustChangePassword`.
- **الجلسات والتنبيهات:** طابق `new device`, `failed attempts at threshold`, `account-created`, `privacy-updated` من Domain Outbox؛ سجل النتيجة في Inbox أولاً، واربط FCM فقط عندما تكون Capability مثبّتة والتوكن مسجلاً ومربوطاً بالجلسة. `THIS_WAS_ME` إقرار فقط؛ `RESET_PASSWORD` يفتح مساراً مسجلاً موثوقاً.
- كل عملية تنال وصفاً مستقلاً: `BACKEND_SOURCE_REVIEWED`, `DTO_ERROR_UI_REVIEWED`, `WIZARD_MAPPED`, `EXTERNAL_MAPPED`, `LIVE_E2E_ACCEPTED`، ولا تغيّر `0/17` دون أدلة حية.

## P2 — Other Backend وWizard

**السؤال الأول في Wizard:** Fable Backend أم Backend آخر؟ لا تُظهر ميزات Auth أو Firebase أو Push أو مدير الصلاحيات ما لم يعلن العقد выбран أنها مدعومة. تمييز البيانات الثابتة (إعداد المشروع) عن القيم الديناميكية/القدرات المحكومة بالخادم. لكل عملية نُقلت إلى Flutter، أنشئ قائمة إلزامية لما يجب على Backend الآخر تقديمه: method/path, DTO, auth scheme, errors, permissions, pagination, delivery, nullability, idempotency, contract tests. لم يكتمل ربط MFA الخارجي بعد.

## P3 — Offline/Sync والميزات الأخرى

Offline اختياري في Wizard: إن اختير يُحدد Drift + SQLite وسلوك GET، العمليات المعدّلة POST/PATCH/DELETE، وسياسة conflict/retry/financial revalidation؛ لا تُسجّل عملية مالية في طابور دون عقد صريح. تتبع كل واحدة من عائلات Flutter الـ17 منفردة بمصفوفة parity مع Backend المصدر المختار، وليس بعدد الحزم المسجلة. الإغلاق بعد اختبارات مشروع مولد + Android/iOS حقيقية + API/DB/FCM حقيقي حيث يلزم.

## شروط الدمج والتسليم

- **Flutter:** لا Merge قبل نجاح Source Gate والاختبارات المستقلة وFlutter Analyzer وAndroid Debug وiOS Simulator في SHA المحددة؛ بعد الدمج تحقق من `main` CI أيضاً.
- **Backend:** لا Merge قبل CI الخاص أو بديل تحقق مستقل معتمد ومثبت؛ لا تضع GitHub token خاصاً أو Backend source في public repo.
- **ZIP:** تسليم نسخة شاملة تحمل SHAs و`SOURCE-PAIR/PAIR-MANIFEST.json` و`SHA256SUMS.txt` وملف ZIP checksum؛ يجب تحقق الأداة من نظافة Git ومطابقة Backend source. حزمة أدوات إنشاء ZIP **ليست** ZIP الكود المزدوج نفسها.
- **سجل دائم:** تحديث Issue #15 وروابط PR لكل دفعة، مع السبب إذا أُجل بند، وموافقة صريحة على تشغيل E2E الحقيقي قبل نقله إلى `ACCEPTED`.

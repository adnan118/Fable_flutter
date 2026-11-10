# RC160 — قبول اتصال عميل Flutter الفعلي بخادم Render عبر HTTPS (سلبي فقط)

**المرحلة الرابعة** — اختبار قابل للتنفيذ دون حسابات تجريبية دائمة، ودون منافذ Debug عامة أو بيانات عملاء.

## لماذا؟

نجح RC155 في 49 فحص HTTP حقيقيًا **من داخل** حاوية Render باستخدام حسابين وهميين. ونجح RC159 في فحص خمس واجهات عبر HTTPS **من عميل Dart مستقل** خارج الحاوية. لكن الاختبار الثاني لم يكن من مكتبة `UnifiedApiClient` المستخدمة في تطبيق Flutter، ولم يثبت أن استيراد عقد Fable وتشغيل محوّل `FableTransportAdapter` وإرسال الطلبات الفعلية يعمل عبر الشبكة.

## ما يضيفه RC160

ملف `packages/fable_core/test/rc160_real_https_invalid_bearer_test.dart` يستخدم:

- `FableContract.fromMaps` لتحليل الملفات البنيوية الموجودة فعلًا في Flutter. قبل التنفيذ، يتأكد من أن `contract.project.id == "test-project"` ولا يقدمها كاستيراد مشروع حقيقي.
- `UnifiedApiClient` الفعلي، و`FableTransportAdapter` الافتراضي، و`Dio` و`IOHttpClientAdapter` الذي يحترم إعداد Proxy المشغّل ويتحقق من TLS بواسطة النظام، دون تعطيل التحقق من الشهادة.
- جلسة *اختبار محلية داخل الذاكرة* تحمل **Bearer غير صالح عمدًا**، من دون تخزين توكن أو إنشاء حساب.
- استدعاء عمليتي `account.me` و`auth.sessions` عبر HTTPS من GitHub runner مستقل، مع توقع `HTTP 401` لكل منهما. اختبار كل عملية منفصل ولا يُعاد إرسال POST أو DELETE؛ ولا يسمح أي مسار سوى HTTPS إلى عنوان Render التجريبي.
- وضع opt-in فقط: `--dart-define=FABLE_RC160_REAL_HTTPS=true`. في CI الاعتيادي لا تنفّذ الاختبارات شبكة خارجية؛ تبقى الملفات صالحة للتحليل دون الاعتماد على توفر Render.
- Workflow منفصل يتحقق أولًا من سلامة العقد المصدرية، ثم يجري فحصًا تمهيديًا مستقلًا بـ`curl` عبر HTTPS وشهادة صالحة و`HTTP 200` إلزامي (دون اتباع redirects)، ثم يشغّل هذا الاختبار الحقيقي داخل حزمة `fable_core`. فحوص RC159 المستقلة نجحت مسبقًا في 9 نوفمبر، لكنها أظهرت انقطاعًا عارضًا في اتصال Dart عند إعادة تشغيلها في RC160 يوم 10 نوفمبر؛ ولا يعد ذلك نتيجة Flutter.

## حدود هذه النتيجة

**لا تُعتمد ضمن RC160** جلسة تسجيل دخول حقيقية من Android/iPhone، ولا تثبيت عقد مشروع Backend غير تجريبي، ولا Media upload من التطبيق، ولا مقاومة سرقة توكن صالح. في Render، ينشئ RC155 حسابين وهميين داخل الحاوية ثم يحذفهما ولا يسجل كلمات المرور أو التوكنات؛ لا توجد قناة آمنة من المشغّل الخارجي لتسلمهما، لذلك لن ينشئ RC160 منفذ إنشاء مستخدم دائم أو يضع أسرارًا في المستودع.

**معيار النجاح**: `RC160_FLUTTER_GATEWAY_EXTERNAL_PASS` من تشغيل GitHub Actions الناجح على SHA دقيق، ونجاح اختبارات Flutter الأساسية وAndroid وiOS من RC49 قبل الدمج.

**المتبقي**: [#82](https://github.com/adnan118/Fable_flutter/issues/82) اختبار موبايل مُصادق عليه بمشروع مُثبت عبر HTTPS، [#33](https://github.com/adnan118/Fable/issues/33) خطر نسخ Bearer ومعرّف التثبيت، [#35](https://github.com/adnan118/Fable/issues/35) Support، S3/DRM، MySQL 8.4، وبقية القدرات الـ17. المرحلة السابعة لا تزال NO-GO.

## دليل التنفيذ الأول — 10 نوفمبر 2026

- في البداية فشل تحليل Dart بسبب استخدام getter غير موجود `HttpOverrides.global`؛ صُحّح إلى `HttpOverrides.current` مع إعادة سياسة الشبكة بعد الاختبار.
- تعثر تشغيل تمهيدي آخر بسبب انتهاء مهلة `dart:io` لعنوان Render على مشغّل خارجي قبل بدء Flutter. أضفنا فحص `curl` تمهيديًا باستخدام TLS صحيح و`HTTP 200` إلزامي، دون bypass للشهادة أو تتبع للتحويلات.
- **نجح التشغيل الفعلي** [GitHub Actions #42774659208](https://github.com/adnan118/Fable_flutter/actions/runs/42774659208) على `dccbdeab4d950fda3d5305545c894e5074210053`: `dart analyze` بلا أخطاء؛ `RC160_CURL_TLS_PREFLIGHT_OK`؛ `account.me HTTP 401`؛ `auth.sessions HTTP 401`؛ `RC160_FLUTTER_GATEWAY_EXTERNAL_PASS`؛ و`All tests passed!`.
- هذه أدلة تشغيل **الخادم الخارجي ومكتبة Flutter** من CI، وليست دليل قبول Flutter Android/iOS مصادقًا عليه أو اختبار User A/B عبر نفس الجهاز. لا نحسب `test-project` عقدًا مثبتًا.

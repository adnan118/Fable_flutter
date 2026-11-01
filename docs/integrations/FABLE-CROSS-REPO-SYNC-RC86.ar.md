# RC86 — مزامنة ريبو Backend Fable وFlutter وإصدار ZIP شاملة

## الهدف وحدود المزامنة

نثبت نسخة Backend Fable الخاصة ونسخة Flutter العامة كبصمتين مستقلتين، ثم نراجع تطابق **40 عملية Auth** بين `Fable-Backend-RC66/blueprints/capabilities/auth/manifest.json` وجرد Flutter `FABLE-AUTH-OPERATIONS-RC80.json`: معرف العملية `id`، وطريقة HTTP `method`، والمسار `path`.

نجحت المطابقة المصدرية الأولية لجميع عمليات Auth الأربعين؛ **9 منها فقط** لديها مراجعة/شيفرة واختبارات Flutter مصدرية، و**31** ما تزال `NOT_DECIDED`. ما زال **0/17 ميزة معتمدة E2E**. تطابق المسارات لا يثبت مطابقة جميع DTO/الأخطاء/الصلاحيات/الواجهات أو تشغيل قاعدة البيانات والأجهزة. لا يتم نقل أي مسار خاص بـFable إلى Backend آخر.

## بصمات نسخة المصدر

| الريبو | سياسة الوصول | الحالة عند بدء RC86 |
|---|---|---|
| `adnan118/Fable` | **خاص** | `226cbcdc542ebe9c005d7445d84cc0ec10631932` |
| `adnan118/Fable_flutter` | عام | `368cae59e78b4e9244845c344c45aa83804f7b28` |
| Blueprint Auth في Backend | Git Blob SHA-1 | `c300b2ca68172799d005cb5432b8a32e121102d7` |

هذه البصمات هي **نسخ وقت تدقيق المصدر**؛ قد تتغير SHA للفرعين بعد إضافة إجراءات التغليف والتوثيق، لذلك تُثبت ZIP النهائية SHA الفعلية لكل ريبو وقت تشغيل CI، وتتحقق من بقاء Blob عقد Auth نفسه دون تغيير غير مدقق.

## آلية المزامنة والاختبار

- `docs/integrations/FABLE-CROSS-REPO-SOURCE-PAIR-RC86.json`: السجل المقروء آلياً، وبصمة المصدر، وفصل Source Review عن E2E.
- `tools/verify-cross-repo-source-pair.mjs`: عند تشغيله من Flutter وحده، يتحقق من اتساق السجلات والأعداد ولا يدّعي فحص Backend الخاص. عند `--backend-root`، يتحقق من Git Blob وعقد العمليات الأربعين مباشرةً من Backend.
- `test/cross-repo-source-pair-rc86.test.mjs`: اختبارات تمنع المزامنة مع SHA غير متفق عليه أو الادعاء كذباً باكتمال Backend الآخر والـWizard أو E2E.
- فحوص Flutter ترفض أي تراجع في سجل مزامنة المصدر؛ فحوص Backend الخاصة تتحقق من الريبوين معاً قبل إصدار الحزمة.
- تتضمن الحزمة النهائية جرد جميع ملفات المصادر المتتبعة وإصدار Git لكل ريبو، وبصمات SHA256 لكل ملف مضمن، وسجل المزامنة وملف التدقيق.

## إنشاء ZIP بأمان

**مكان الإصدار:** GitHub Actions في الريبو **الخاص** `adnan118/Fable` فقط، لأن ZIP تتضمن الكود الكامل للـBackend الخاص. لا تُنشأ Release عامة ولا تُرفع ملفات Backend إلى ريبو Flutter.

عند النجاح ينتج ملف `Fable-Backend_Fable-Flutter_RC86-full-source.zip` ضمن Artifact خاص. توجد داخله:

```text
Fable-Backend/              # كود Backend الخاص، الملفات المتتبعة في Git
Fable-Flutter/              # كود Flutter العام، الملفات المتتبعة في Git
SOURCE-PAIR/
  PAIR-MANIFEST.json       # Git SHA لكل ريبو، أعداد الملفات، استثناءات الأمان
  SOURCE-PAIR-VERIFICATION.json
  SHA256SUMS.txt           # البصمة لكل ملف مصدر ضمن ZIP
  README-AR.txt
```

تُستبعد بيئات الأسرار `.env`، مفاتيح التوقيع `.pem/.p12/.jks` وما شابه، الملفات الخاصة بالسيرفرات والجهاز مثل `node_modules/.git/.dart_tool`، وإعدادات Firebase المحلية التي قد تحمل معلومات خاصة. `.env.example` وملفات المثال غير السرية تبقى بحسب السياسة.

يُصدَر أيضاً ملف `.zip.sha256` للتحقق من ZIP كاملة، ويجري فكها واختبار CRC في CI. تنزيل Artifact من GitHub يكون من **Actions → RC86 synchronized Backend+Flutter source ZIP → أحدث تشغيل ناجح → Artifacts**. يحتاج المستخدم صلاحية الوصول إلى ريبو Backend الخاص، والحزمة متاحة خلال فترة الاحتفاظ المُعلنة في Workflow.

## لماذا لا نعتبر هذه الخطوة إغلاق Auth؟

- الحزمة تشمل **كامل الملفات المصدرية المتتبعة** من الريبوين؛ لا تعني أن كل ميزات Backend نقلت كاملة إلى واجهات Flutter أو Wizard.
- متطلبات Backend غير Fable تظل بعقد مستقل؛ لا ينشأ له 2FA/Firebase/Password Reset افتراضي.
- يتطلب الاعتماد النهائي تشغيل مشروع Backend مولّد مع MySQL، واختبارات جهازي Android/iOS حقيقيين، وإجراءات Replay، وFCM وOTP والأوفلاين، وقياس نتائج كل ميزة طبقاً للسجل الرئيسي.

[Issue #15](https://github.com/adnan118/Fable_flutter/issues/15) يبقى مفتوحاً حتى انتهاء الفجوات الفعلية.

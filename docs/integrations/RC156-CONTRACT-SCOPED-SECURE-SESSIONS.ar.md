# RC156 — عزل مفاتيح الجلسة بين عقود Backend المختلفة

**التاريخ:** 2026-11-09  
**المرحلة:** الرابعة — Auth/Access Control مع فصل Fable وOther Backend.

## اكتشاف أمني قابل لإعادة الإنتاج

كان `FableAuthGateway.sessionNamespaceFor` يشتق اسم مخزن التوكن من `origin|projectName` فقط. اسم المشروع المعروض **ليس** مُعرّفًا فريدًا؛ يستطيع مشروعان Backend مختلفان حمل الاسم نفسه والاستضافة على الخادم نفسه، ما يجعل المخزن و`identityEvents` مشتركين خطأً.

كذلك كان `ExternalAuthGateway.secureSessionFor` يشتق مفاتيح Other Backend من `origin|adapter` فقط، مع أن عقد OpenAPI/Custom قد يتبدل بالكامل مع بقاء الاستضافة والمحوّل كما هما.

## إصلاح RC156

- Fable: نطاق `Keychain/Keystore` صار SHA-256 مختصرًا لـ`origin|projectName|contractHash`.
- Other Backend: النطاق صار SHA-256 مختصرًا لـ`origin|adapter|sourceHash|operationsHash`، وهذه البصمات مستخرجة من الكتالوج المستورد والمتحقق منه.
- لا تغيّر المسارات، لا تُشغّل موفري هوية جدد، ولا تنسخ أي توكن أو معرّف جهاز داخل الإخراج أو السجلات.
- لا تخزّن الجلسة في SharedPreferences؛ `FlutterSecureStorage` ما زال مصدر كلمات الوصول وتجديدها.
- `installationId` ليس إثباتًا للجهاز، ولا تحل هذه الخطوة مشكلة سرقة Access Token ومعرّف التثبيت معًا الموثقة في Backend [#33](https://github.com/adnan118/Fable/issues/33).
- **لا تجري ترحيلًا صامتًا** لمفاتيح الجلسات القديمة المبنية على اسم المشروع؛ قد تكون مشتركة مسبقًا بين مشروعين. بعد تحديث التطبيق قد يلزم تسجيل الدخول من جديد. ستبقى مفاتيح قديمة غير مستخدمة في المخزن الآمن إلى أن يعتمد المشروع سياسة إزالة آمنة مرتبطة بالمستخدم/الجهاز، ولا ينبغي قراءتها أو استعارتها.

## اختبارات Flutter الجديدة

`packages/fable_core/test/rc156_contract_bound_session_namespace_test.dart`:

1. مشروعان Fable لهما `origin` واسم عرض متطابقان لكن `contractHash` مختلف: نطاقان منفصلان ولا يُعاد استخدام النطاق القديم.
2. استيراد Fable نفسه على `origin` نفسه: النطاق نفسه؛ تغيير الأصل أو اسم المشروع يعزله.
3. Other Backend مع `origin` و`adapter` نفسيهما: تغيير `sourceHash` أو `operationsHash` يعزل الجلسة؛ الاستيراد المطابق يعيد استخدام النطاق نفسه.
4. لا يمكن لأي Fable/Other Backend مشاركة نطاق هوية بالصدفة حتى مع استضافة مشتركة.

يجب إثبات Flutter Analyze + اختبارات الحزم + Android Debug + محاكيَي iOS 27 في CI على التزام PR نفسه قبل الدمج.

## حدود القبول

هذه **حماية محلية لعزل الجلسات حسب العقد**، وليست اختبار HTTP متكاملًا على جهاز Flutter أو حلًا لسرقة التوكن الصحيح. عقد `ci_fable` ما يزال fixture اختبار فقط؛ يبقى ربط مشروع Backend مُثبت عبر HTTPS، وSupport، وS3/DRM والقدرات الـ17 في جدول المرحلة الرابعة. المرحلة السابعة **NO-GO**.

## CI forensic note — initial RC156 attempt

- Initial run [42673224145](https://github.com/adnan118/Fable_flutter/actions/runs/42673224145) failed Dart analysis due to a **test-only** positional `expect(..., reason)` argument. Fixed to a named `reason:` argument before the next run.
- The subsequent run [42673681426](https://github.com/adnan118/Fable_flutter/actions/runs/42673681426) reported **SUCCESS** for Flutter analyze/application/feature-package tests and Android debug APK, but the **overall workflow was failure** and no `ios-unsigned` job appeared in the returned GitHub job records. The native iOS check therefore remains **unverified** for that exact commit; passing Android/Flutter is insufficient to merge this PR.
- Re-run on a new exact head is required; treat macOS availability/workflow scheduling as infrastructure until a separate log demonstrates a code error. No code or release claims are inferred from a missing job.

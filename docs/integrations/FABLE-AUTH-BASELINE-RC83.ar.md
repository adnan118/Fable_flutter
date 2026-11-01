# RC83 — إغلاق أساس Auth: Login / Refresh / Sessions / Session Policy

**المراجع الثابتة:** [Issue #15](https://github.com/adnan118/Fable_flutter/issues/15) · [السجل الرئيسي](./FABLE-FLUTTER-PARITY-MASTER.ar.md) · [جرد الأربعين عملية](./FABLE-AUTH-OPERATIONS-RC80.json) · [القرارات العامة](./FABLE-BACKEND-WIDE-DECISIONS-RC81.ar.md) · [مقدمة BLoC](./FLUTTER-BLOC-LEARNING.ar.md).

**قاعدة الاعتماد:** هذا فحص لشيفرة Fable RC66 ولعقدها المرجعي ومصدر Flutter، وليس اختباراً على Backend مشروع مولّد مع قاعدة بيانات حقيقية. المصدر المرجعي للباك: `adnan118/Fable@226cbcdc542ebe9c005d7445d84cc0ec10631932`. لا نعتبر Source/CI دليلاً على E2E.

## 1. السلسلة المعمارية والحدود الأمنية

`FableLoginPage` ← `FableAuthGateway` ← `FableApiClient` ← `FableTransportAdapter` ← Backend.

- `FableAuthGateway` هو Adapter خاص فقط بعقد Fable. لا نضيف له أي مسار أو سلوك لـOther Backend.
- `FableApiClient` يقرأ `operationId` من العقد المستورد ويمنع تجاوز HTTPS/Origin وصلاحيات `Authorization`. في RC83 أضفنا طبقة تحقق **دلالية**: يجب أن تتطابق الطريقة والمسار وكون العملية عامة/محمية وأن يكون العقد `enforceAuth`، وألا تحمل `credentialHeader` مخصصاً قبل إرسال أي أسرار.
- `FableSecureSession` يعزل التوكن حسب نطاق Backend، ويحفظ `installationId` محلياً؛ تبديل الهوية يبطل الكتابة/الردود المتأخرة. لا تنشئ الواجهة Session لمجرد وجود توكن على القرص.
- `Other Backend` يعمل من خلال `ExternalOperationCatalog` و`ExternalAuthGateway` ومخططات `external-auth.json`. لا يُفعّل من مجرد وجود اسم `login` أو `sessions`.

## 2. المطابقة العملية للعملية

| عملية Fable | العقد المرجعي | سلوك Flutter بعد RC83 | متبقٍ لا يجوز تجاهله |
|---|---|---|---|
| `auth.login` | `POST /auth/login` عام، `identifier/password/clientType/installationId`، بيانات جهاز اختيارية؛ قد يعيد `requiresTwoFactor` بدلاً من Tokens | التحقق الصارم من تعريف العملية قبل إرسال كلمة المرور، ثم بوابة 2FA وصلاحية الهوية قبل حفظ التوكن | الحقول `assuranceLevel/authenticationMethods/mustChangePassword/expiresAt/timeZone/user` لا يكتمل تمثيلها؛ `deviceName/appVersion` لا يمرران بعد؛ أخطاء الإقفال وFCM وBackend حي |
| `auth.refresh` | `POST /auth/refresh` عام، Refresh 64 Base64url، `installationId`، تدوير/Replay Grace | لا استدعاء إلا عند تطابق العقد؛ حفظ tokens بنمط compare-and-swap؛ GET يعاد فقط بعد تجديد مؤكد، Mutation لا تعاد تلقائياً | اختبار `AUTH_REFRESH_ALREADY_ROTATED` وReplay Detection والتحويل بين حسابين/جهازين على MySQL حقيقي، مصدر انتهاء الصلاحية |
| `auth.sessions` | `GET /auth/sessions` Bearer؛ قائمة جلسات الخادم الفعلية فقط | رفض العملية إذا اختلف المسار/الطريقة/حماية Bearer؛ منع العناصر غير الصحيحة وتكرار UUID، تم الاحتفاظ بـ`securityState` وإظهار تنبيه الجلسة المشبوهة | التحقق من تزامن الإلغاء والتحديث وStep-up ومن مخطط حالات الأمان وإمكانية تنفيذها على Android/iOS |
| `auth.session-policy` | `GET /auth/session-policy` عام، سلطة التشغيل من Environment | مطابقة عقد GET العام؛ لا تخمين عند غياب `onePerInstallation`، عرض `maxActive/overflow/onePerInstallation` من رد runtime | تغيير السياسة أثناء العمل، أثر `reject-new/revoke-oldest` على الأجهزة، وE2E حقيقي |

**تفاصيل Backend:** `Fable-Backend-RC66/src/platform/auth/auth.controller.ts`, `auth.service.ts`, `dto/login.dto.ts`, `dto/refresh.dto.ts`.

## 3. قرارات عابرة للميزات يجب احترامها

1. **سياسة الجلسات Runtime:** `mode=single` يفرض جلسة واحدة. في `multi`: `maxActive=0` يعني بلا حد عددي؛ `overflow=reject-new` يرفض جهازاً جديداً عند بلوغ الحد؛ `revoke-oldest` قد يُبطل جلسة أقدم؛ `onePerInstallation` يقيّد جلسات نفس تثبيت التطبيق. هذه قرارات Backend وليست خيارات Theme.
2. **Auth Transport:** Flutter يستخدم Bearer و`clientType=flutter` مع Installation ID. الويب يستخدم Cookies وCSRF منفصلين، ولا يجوز نقله إلى الموبايل أو اعتماد سلوكه تلقائياً.
3. **Refresh Rotation:** إذا أعاد Backend `AUTH_REFRESH_ALREADY_ROTATED` / HTTP 409 فهو ليس ترخيصاً لتكرار Refresh Token القديم. إذا كشف Replay غير موثوق فقد يبطل الخادم الجلسة. لا نكرر mutations المدفوعة أو الأمنية بعد 401.
4. **الأجهزة والإشعارات:** `deviceName/platform/appVersion` و`timeZone` بيانات سياقية، قد تؤثر على إشعار جهاز جديد ومحاولات تسجيل الدخول الفاشلة؛ يجب ألا يُخترع مصدرها ولا يُطلب موقع حساس بلا موافقة.
5. **هوية الحساب:** User وProfile وManaged Entity مفاهيم مختلفة. لا نرسل رأس الكيان المدار إلى Auth. و`securityState` معلومات من الخادم لا تُستخدم كبديل عن فحص تفويض جديد.

## 4. Backend آخر — متطلبات قابلة للتحقق في Wizard

| العملية | ما يجب أن يقدمه Backend الآخر |
|---|---|
| Login | `operationId + method + path` وطريقة الاعتماد، أسماء حقول الطلب/الاستجابة، دليل نجاح الدخول، 2FA إن وجد، وأخطاء 401/409/429 وسياسات الأجهزة |
| Refresh | بيان ما إذا كان النظام Rotating Bearer أو Single Bearer أو Cookie، سياسة انتهاء/دوران/Replay، عملية مستقلة إن وجدت، وField Selectors حقيقية |
| Sessions | عملية محمية + خريطة الحقول والتواريخ/تحديد الجهاز الحالي وحالات الأمان، أو إعلان عدم الدعم وإخفاء الواجهة |
| Session Policy | مصدر Runtime موثوق أو إعلان أن السياسة غير مكشوفة؛ لا ننسخ `maxActive` الافتراضي أو عناوين Fable |

**قواعد Wizard:** سؤال «هل الباك Fable؟» أولاً. في Fable نستورد عقد مشروع مولّد مثبت البصمة، مع Runtime Policy منفصل عن إعدادات البناء. في Other نستخدم `assets/contracts/external-operations.json`, `assets/config/external-auth.json` وخريطة Features مستقلة. إذا نقص العقد تبقى العملية `pending` ولا نعرض وظيفة شبكة وهمية. تغيير الباك يزيل الربط القديم ويعزل التوكنات والكاش والـOffline والـPush.

## 5. اختبارات المصدر وما لم يُختبر

- `packages/fable_core/test/auth_baseline_rc83_contract_test.dart`: العقود غير المطابقة للـLogin/Refresh/Sessions/Policy، منع الاتصال عند الخطأ، بيانات Login وRefresh، تجديد التوكن دون تبديل الهوية، غياب سياسة Installation.
- `packages/fable_core/test/active_sessions_contract_test.dart`: DTO جلسة آمن، `securityState` مسموح/غير مسموح.
- اختبارات سابقة لا تُلغى: `auth_gateway_identity_regression_test.dart`, `session_concurrency_test.dart`, `session_policy_contract_test.dart`، واختبارات Widgets.

**البوابات المفتوحة:** عقد مشروع Fable مولّد حقيقي وبصمته، Backend+MySQL، سيناريوهَا جهازين وRefresh Replay/Grace، 2FA/Failed-login Limit وFCM، تحقق صلاحيات وStep-up على أجهزة Android/iOS، ومشروع Other Backend منفصل بعقد كامل. إحصاء العمليات وفق الجرد هو **7 لها شيفرة/مراجعة واختبارات مصدرية** مقابل **33 لم تتخذ قراراً نهائياً**، و**0 اعتماد E2E حي**. هذا لا يعني اكتمال Auth، ولا اكتمال ربط Wizard الحقيقي.

## 6. تبسيط للمراجعة أثناء تعلّم BLoC

Widget تعرض `loading/error/success` ولا تتخذ قرار «التوكن صالح» بنفسها. Gateway يُنفّذ عملية من العقد ويحمي هوية الجلسة، وSession تحفظ الاعتماد بسرية. عند الانتقال إلى Cubit/BLoC نضع عمليات الدخول/الخروج وتحديث الجلسات في حالات واضحة، لا ننقل كلمة المرور/Refresh Token إلى State أو Logging. راجع [دليل Flutter/BLoC بالعربية](./FLUTTER-BLOC-LEARNING.ar.md).

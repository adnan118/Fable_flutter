# RC81 — سجل قرارات Fable العامة + أول عملية من خطة إغلاق Auth

**المرجع المركزي:** [سجل الميزات](./FABLE-FLUTTER-PARITY-MASTER.ar.md) · [قائمة Auth الأربعين](./FABLE-AUTH-OPERATIONS-RC80.json) · [قرارات Fable العامة في JSON](./FABLE-BACKEND-WIDE-DECISIONS-RC81.json) · [دليل Flutter/BLoC](./FLUTTER-BLOC-LEARNING.ar.md).

## لماذا يوجد هذا السجل؟
ليس كل قرار Fable عبارة عن Feature يمكن نقله بصورة مباشرة: الباك لديه قواعد تصميم وإعداد وتشغيل موزعة على `lib/decision-guidance.mjs` و`lib/frontend-setup-decisions.mjs` و`lib/http-policy.mjs` و`src/core/http/request-policy.ts` و`data-ownership-policy.mjs` وغيرها. وبعضها يُستخدم في **جميع** الميزات (النقل والجلسات وتخزين الاعتماد واختيار اللغة والوقت وتكرار الطلب)، وبعضها قرار **بنية خلفية فقط** (Redis/Valkey/MySQL/Secrets) فلا يجب نسخه للعميل.

جردنا **23 سياسة/قراراً عابراً للميزات**. ليس هذا إثباتاً لجرد كل قرار في مولّد Backend؛ بل بداية ملزمة قابلة للتطوير، مع الاحتفاظ بـ`fullParityVerified=false` لكل بند.

## ثلاثة مستويات لسلطة القرار

| المستوى | مثال | ما يفعله Flutter والـWizard |
|---|---|---|
| مشروع Backend الذي اختير | Fable: `identityModel`, `managedAccounts`, `authentication.otp`, `localization`, `commercial`، بناءً على `dist/client-contract` | يستورد عقد المشروع مع بصمة مستقلة؛ يعرض القرارات للمراجعة ولا يخترع إعدادات |
| حالة تشغيل Backend الحقيقية | `/auth/session-policy`، صلاحيات المستخدم، الاشتراكات، استحقاق الدفع، سياسة تغيير كلمة المرور عند التنفيذ | يقرأ الحالة التشغيلية عبر عملية مصرح بها، ولا يعتبر قرار البناء دليلاً مستمراً |
| قواعد عابرة للميزات أو خاصة بالخادم | Retry/Idempotency/If-Match/Time Zone/Error Envelopes/Cache/Retention؛ أو نوع Redis/Valkey وMySQL | ينفّذ فقط الأجزاء المطلوبة للعميل؛ البنية والأسرار لا تُرسل إلى Flutter |

## متى قد يظهر تعارض؟
- سياسة `sessions` المصدّرة من الـWizard لا تعلو على `GET /auth/session-policy` في التشغيل؛ وإذا خالفتها يقدّم Runtime ولا يمنح التطبيق جلسات إضافية.
- `User` هوية أمنية؛ `Profile` بيانات تخصص، و`Managed Entity` كيان يملكه المستخدم. `OWNER` لا يمكن منحه بالدعوة. عمر الاسترجاع والتعطيل والحذف يخضعان للباك.
- الويب يستخدم Cookies/CSRF؛ تطبيق Flutter في Fable يستخدم Bearer وSecure Storage. `Origin` أو `X-Time-Zone` أو عنوان IP لا يثبت هوية المستخدم.
- `Idempotency-Key` ليس Header عاماً يضاف عشوائياً، و`If-Match` لا يُرسل على GET؛ لا يجوز Retry مالي أو حساس عندما تكون نتيجة العملية مجهولة.
- Cache السيرفر ليس Offline Cache تطبيقاً. لا يُسمح بحفظ بيانات مستخدم آخر بعد تبديل الحساب أو النسخة أو اللغة، ولا باستخدام DB Cache لمصدر صلاحيات.
- أي Capability موجودة في مخططات Fable العامة ليست مثبّتة بالضرورة في مشروع العميل. عقد المشروع المصدّر، ثم صلاحيات Runtime، هما مصدر الحقيقة.

## Backend الآخر وWizard الآخر
اختيار `other` لا يعني تبني تصميم Fable: يجب أن يقدّم باكه من `openapi` أو `custom` كتالوجاً مستقلاً يثبت عملية الطلب وAuth scheme وDTOs وResponse errors وSession lifetime/rotation وPermission scopes. ثم يربط `feature-operations` والـDTO mappings المتوافقة معه. كل قرار عام غير موجود في عقد الآخر يتخذ حالة `UNVERIFIED`، ولا يُستورد من Fable خلسة.

مخرجات مراجعة `tools/flutter-setup-wizard.mjs` أصبحت تذكر هذه القرارات عند كلا المسارين. هذا **تحذير وتحليل** وليس إضافة تلقائية لHeaders أو أسرار أو اعتماد عمليات غير موجودة.

## أول عملية يجري نقلها بالترتيب: auth.change-password

**المصدر المحدد:** `src/platform/auth/auth.controller.ts` و`dto/change-password.dto.ts` و`auth.service.ts` في Backend، مع `auth.change-password POST /auth/change-password` في Blueprint manifest.

- **طلب:** Bearer عبر عقد Fable المُثبت، `currentPassword` و`newPassword`، كلتاهما String غير فارغ. لا تُرسل `X-Fable-Managed-Entity-Id` ولا أسرار في السجل أو Snackbar.
- **قاعدة عمل:** يتحقق الخادم من كلمة المرور القديمة ثم السياسة الفعلية: الطول/التعقيد/تاريخ الإعادة وربطها بالهوية. **لا** يفرض Flutter سياسة محلية من التخمين.
- **أخطاء:** `AUTH_CURRENT_PASSWORD_INVALID`، أخطاء `AUTH_PASSWORD_*`، `AUTH_PASSWORD_STATE_CHANGED`، 401/403، 429، انقطاع الشبكة أو 5xx. لا تعرض رسائل الخادم غير الموثوقة أو كلمات المرور.
- **نجاح:** يتطلب Body `changed:true`، وبعده يبطل Backend كل جلسات المستخدم (من ضمنها الحالية) وتحديات الدخول المعلقة. Flutter يزيل اعتماد الجلسة الحالية إذا **لم تتغير هوية المستخدم** أثناء الطلب؛ يطلب تسجيل دخول جديداً. يمنع إظهار نجاح قبل رد موثوق أو إعادة إرسال POST تلقائياً بعد فشل نقل مجهول.
- **واجهة:** تظهر فقط لمستخدم مسجل دخولاً، وعندما يحتوي عقد Fable على عملية تغيير كلمة المرور. حقول Current/New/Confirm محمية؛ لا يُعرض زر لباك آخر بالافتراض.
- **التحقق بالمصدر:** اختبارات Gateway وWidget للتحقق من جسم POST، الرد المزيف، الهوية المتغيرة، غياب العملية، وعدم تكرار Mutation.
- **ما لم يُغلق:** اختبارات Android/iOS الحقيقية، سياسة كلمة المرور من Backend فعلي، جلستان حقيقيتان وقاعدة بيانات/عزل، إشعارات الأمان، وسلوك أخطاء الشبكة المتزامنة، وربط نظام `other` إذا قدّم عقداً مماثلاً. لذلك الحالة `SOURCE_IMPLEMENTED_E2E_PENDING` وليس `DONE`.

### ما يجب أن يقدمه Backend خارجي لتفعيل Change Password
لا بد من `POST/PUT` محمي محدد بالاسم (ليس بالضرورة `/auth/change-password`)، وتسمية حقلي كلمة المرور، وطريقة المصادقة و2FA/Step-up إن كانت لازمة، وResponse مؤكّد لا يُخلط مع مجرد قبول الطلب، وأكواد أخطاء سياسة كلمة المرور والمعدل، وسياسة إلغاء جميع/بعض الجلسات ومصير التوكن بعد النجاح. إذا لم يقدّم هذه المتطلبات، **لا** تعرض الواجهة أو تستنتج نجاحاً.

## سجل العمل القادم
اعتمد ترتيب [قائمة Auth الأربعين](./FABLE-AUTH-OPERATIONS-RC80.json): تصنيف كل عملية وبند استثناء للويب/الإدارة، ثم مراجعة واجهة/Repository/Models/Errors/Role/Wizard لكل عملية Mobile. لا تنتقل إلى إعلان Auth كاملة قبل ضبط تغيير كلمة المرور والاسترداد والهوية و2FA/Sessions/Providers وE2E؛ Profile ثم Notifications وContent هي المراحل التالية.

**القاعدة في الأكواد:** تعليقات بالعربية توضح لماذا فُرض شرط أمان أو ترتيب معيّن، أو رابط للملف؛ واستعمل `Cubit/BLoC` فقط عندما تتطلب إدارة الحالات ذلك، لا لمجرد نقل HTTP من Widget إلى Widget.

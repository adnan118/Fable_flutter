# RC84 — فرض تغيير كلمة المرور، انتهاء الجلسات وRefresh Replay

**المرجع التنفيذي:** [Issue #15](https://github.com/adnan118/Fable_flutter/issues/15) · [RC83](./FABLE-AUTH-BASELINE-RC83.ar.md) · [قرارات Backend الـ23](./FABLE-BACKEND-WIDE-DECISIONS-RC81.ar.md) · [جرد Auth الأربعين](./FABLE-AUTH-OPERATIONS-RC80.json) · [دليل Flutter/BLoC](./FLUTTER-BLOC-LEARNING.ar.md).

**الأساس:** `adnan118/Fable@226cbcdc542ebe9c005d7445d84cc0ec10631932` وملفات `Fable-Backend-RC66/src/platform/auth/auth.service.ts` و`jwt-auth.guard.ts`. هذه مراجعة مصدر واختبارات Mock؛ ليست تشغيل Backend مولّد مع MySQL أو E2E حياً.

## 1) قرار Backend العام الذي يغيّر السلوك

- `issueSessionForUser` يعيد `mustChangePassword` (Boolean) و`expiresAt` عند Login العادي وبعد إكمال العامل الثاني. لا يعني إصدار Access/Refresh أن كل شاشات الحساب متاحة.
- `JwtAuthGuard` يعيد `AUTH_PASSWORD_CHANGE_REQUIRED` / 403 للمسارات المحمية غير المسموح بها عند فرض تغيير كلمة المرور. المساران اللذان يسمح بهما على هذا المستوى هما `auth.change-password` و`auth.logout` المعلّمان بسياسة `PasswordChangeAllowed`.
- `auth.change-password` عند تأكيد `changed:true` يبطل **كل جلسات المستخدم**. يزيل Flutter اعتماد الجلسة القديمة مع مراعاة Identity Revision، ولا يحاول إبقاء المستخدم في شاشة أجهزة مفتوحة.
- `auth.refresh` يدوّر Refresh Token؛ إعادة استخدام رمز بعد دورانه على **نفس التثبيت ضمن grace** قد تعيد `AUTH_REFRESH_ALREADY_ROTATED` / 409، وهذا ليس تصريحاً لإعادة إرسال الرمز القديم. إعادة استخدام غير موثوقة قد تعيد `AUTH_REFRESH_REPLAY_DETECTED` / 401 وتبطل الجلسة على الخادم.
- `expiresAt` في العقد المراجع هو **انتهاء AuthSession/Refresh Session**؛ لا يُفترض أنه تاريخ انتهاء Access JWT أو بديل عن الخادم. تحقّق Flutter من صيغته UTC ومقارنته بساعة الجهاز هو حارس مصدر إضافي، ولا يثبت صلاحية التوكن على الخادم.

## 2) التنفيذ في Flutter

| الحالة | السلوك الجديد | الحدود المفتوحة |
|---|---|---|
| Login و`mustChangePassword:true` | يقرأ Gateway القرار من استجابة Fable؛ تعرض الشاشة مطالبة بتغيير كلمة المرور، وتخفي `My active devices & sessions`، وتُبقي Logout متاحاً | من دون `auth.change-password` مؤكدة في العقد لا تُعرض عملية وهمية؛ على المستخدم تسجيل الخروج أو طلب الدعم |
| إكمال 2FA | `completeSecondFactor` يعيد `FableLoginOutcome` يحوي قرار تغيير كلمة المرور، ويطبّق القيد ذاته بعد العامل الثاني | اختبارات Native 2FA/OTP وحقول الأخرى قيد العمل |
| جلسة محفوظة | إذا ردت قراءة جلسات Fable بخطأ محدد `403 AUTH_PASSWORD_CHANGE_REQUIRED` يحتفظ العميل بالتوكن، ويعرض تغيير كلمة المرور بدلاً من الادعاء بأن صلاحية الدخول عادية | فقط إن كانت العملية مفعلة ومعلنة بالعقد؛ عند عدم توفر القراءة، لا نعلن صلاحية الجلسة |
| انتهاء الجلسة | يُرفض حفظ توكن من استجابة جديدة لا تحوي `expiresAt` صالحاً في المستقبل بتنسيق UTC، أو لا تحوي `mustChangePassword` بوصفه Boolean عند إنشاء جلسة جديدة | مزامنة وقت الأجهزة والعميل عبر OS/Backend حي وتاريخ ترقية التطبيق لم تثبت |
| Refresh Replay | 409 لا يُعيد طلب Refresh، ولا يمحو توكنات صالحة لمجرد عدم تزامن الطلب؛ 401 نهائي يُزيل الاعتماد المشروط بنفس الهوية؛ 503 لا يُبطل جلسة | Real DB replay/grace/multiple requests ومخاطر إعادة تشغيل التطبيق تحتاج E2E |

**تعليقات الكود:** الشرح بالعربية في `packages/fable_core/lib/src/fable_auth_gateway.dart` و`packages/features/fable_auth/lib/src/login_page.dart`. يمكن الرجوع إلى [FLUTTER-BLOC-LEARNING.ar.md](./FLUTTER-BLOC-LEARNING.ar.md) لشرح الفصل بين Widget وRepository/Gateway والحالة. لم ننقل كلمات المرور أو Refresh Tokens إلى Cubit/BLoC.

## 3) Backend غير Fable والـWizard

هذه السياسة تخص Fable وحده. لا تُفسَّر أي استجابة `403` من Backend آخر على أنها فرض تغيير كلمة المرور من دون عقد **مستقل** يحدد كود الخطأ وسلوك السماح أثناء القفل. عند اختيار Backend آخر، يجب تأكيد:

1. مسار تسجيل الدخول وFields المطلوبة، ومعنى نجاح الدخول وهل توجد حالة `passwordChangeRequired`/إجراءات تقييدية مكافئة.
2. مسار تغيير كلمة المرور المحمي، وكيفية استعادة المسار، ومتى تبطل الجلسات الأخرى، ومن يحق له تخطي قفل الدخول.
3. العقد الخاص بـ`refresh`، وهل التوكن فردي الاستعمال، وماذا يعني 401/403/409، ومتى يجوز طلب تسجيل الدخول دون إعادة محاولات آلية.
4. شكل `expiresAt`، مصدر الوقت، وحدود TTL؛ لا يفرض Flutter عقد Fable على Backend آخر.
5. **Wizard:** خطوة اختيار Backend أولاً؛ إذا كان Fable يستورد عقد مشروع مولّد موثوق؛ وإن كان Other يبقى في `pending` حتى إثبات Field Mappings وError Mappings والمصادقة وسلوك قفل الحساب.

لا تُعرض أزرار الحساب العام أو إدارة الأجهزة عند وجود قفل تغيير كلمة المرور إلا بعد مراجعة صلاحياتها وعقدها. لا نعتمد شاشة Login على أنها مصادقة كاملة لمجرد استلام Bearer.

## 4) الاختبارات وبوابات القبول

- `packages/fable_core/test/auth_rc84_password_and_replay_test.dart`: حالة إلزام تغيير كلمة المرور، غياب Boolean، غياب/انتهاء `expiresAt`، Refresh 409/401/503 من دون إعادة طلب الرمز القديم.
- `packages/fable_core/test/fable_second_factor_login_test.dart`: عودة قرار تغيير كلمة المرور بعد إكمال العامل الثاني.
- `packages/features/fable_auth/test/mandatory_password_change_page_test.dart`: ظهور القيد وتوقف عرض الأجهزة بعد Login، واستعادة Session تحفظ التوكن عند 403 المحدد.
- اختبارات RC83/RC82 السابقة تبقى إلزامية ولا تلغى، بما فيها concurrent identity changes.

**بوابات اعتماد لم تُغلق:** Backend مشروع مولّد وبصمته، MySQL+Redis حسب استخدام المشروع، جهازان، اختبار Rotation Grace وReplay الحقيقي وTTL/Clock Drift، إشعارات قفل/جهاز جديد/حد فشل، Android/iOS Release على أجهزة حقيقية، مستقل Other Backend/Wizard وحالات التنقل في كل ميزة. كود `AUTH_PASSWORD_CHANGE_REQUIRED` يخص Fable، ولا يُستنسخ تلقائياً.

**الإحصاء:** لا نرفع عدّاد العمليات لمجرد تقوية عملية موجودة: **7/40 عمليات موثقة مصدرياً**؛ **33/40 `NOT_DECIDED`**؛ **0 ميزات مكتملة E2E من أصل 17**. PR وCI مصدر لا إصدار إنتاج.

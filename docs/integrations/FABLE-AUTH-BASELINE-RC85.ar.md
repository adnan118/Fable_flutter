# RC85 — نقل 2FA Login بالكامل ضمن حدود Flutter المصدرية

**المرجع:** [سجل التنفيذ Issue #15](https://github.com/adnan118/Fable_flutter/issues/15) · [السجل الرئيسي](./FABLE-FLUTTER-PARITY-MASTER.ar.md) · [جرد 40 عملية](./FABLE-AUTH-OPERATIONS-RC80.json) · [قرارات Backend العامة](./FABLE-BACKEND-WIDE-DECISIONS-RC81.ar.md) · [Flutter/BLoC](./FLUTTER-BLOC-LEARNING.ar.md).

**مصدر Backend:** `adnan118/Fable@226cbcdc542ebe9c005d7445d84cc0ec10631932`، خصوصاً `auth.controller.ts`, `auth.service.ts`, `otp.service.ts` و`dto/two-factor-login.dto.ts` في `Fable-Backend-RC66/src/platform/auth/`. لا نعتبر اختبار الموك أو نجاح CI اعتماداً حياً.

## 1. الفرق بين العمليات الثلاث

| المرحلة | العقد | ما يفعله الخادم | ما يفعله Flutter |
|---|---|---|---|
| Login / العامل الأول | `POST /auth/login` | يفحص هوية/كلمة مرور وسياسة المحاولات؛ إذا 2FA مفعّلة يعيد `requiresTwoFactor:true` مع `twoFactorToken`, `methods`, `expiresAt`، **ولا يُنشئ Session** | لا يحفظ التوكن في Secure Storage ولا يعتبر المستخدم داخلاً؛ يحتفظ بالتحدي في الذاكرة |
| طلب OTP | `POST /auth/2fa/login/request` | يقيد الطلب بـ`twoFactorToken` و`installationId`، ويختار قناة `EMAIL/PHONE` بعد فحص الطرق المعلنة ويطبّق سياسات Resend | يستعمل فقط مسار Fable العام الصحيح من العقد؛ يتحقق من UUID v4 والطريقة والقناة والمهل؛ يعرض طريقة الإرسال والوجهة المقنّعة والمدة |
| إكمال OTP | `POST /auth/2fa/login/complete` | يستهلك إثبات العامل الأول وOTP وفق صلاحية/محاولات/هوية الجهاز، ويُنشئ جلسة واحدة بعد النجاح | يرفض تحدي UUID غير مطابق، ويتحقق من Session كاملة و`mustChangePassword` و`expiresAt` قبل حفظ التوكن؛ يحافظ على هوية الحساب |

**حقول طلب OTP:** `twoFactorToken`, `clientType=flutter`, `installationId`، و`preferredChannel` اختيارية من الطرق التي أعلنها الخادم (وليس من أزرار ثابتة بالواجهة).

**حقول رد OTP:** `challengeId` UUID v4، `requiresTwoFactor`، `method` واحدة من `EMAIL_OTP` أو `PHONE_OTP`، `channel` المطابقة لها، `expiresAt` لصلاحية OTP، `twoFactorExpiresAt` للتحدي الأول، `destination` مقنّعة اختيارية، و`transport` معلومة عن قناة التوصيل. لا تستخدم الواجهة `debugOtp` حتى لو أرسله Backend تطويري.

**حقول الإكمال:** `twoFactorToken`, `challengeId`, `code` من 4–10 أرقام، `installationId`, `clientType`، وبقية بيانات الجهاز الاختيارية `deviceName`, `platform`, `appVersion` التي بدأت مع العامل الأول. رد النجاح يخضع لحفظ الجلسة الآمن بعد العاملين؛ لا تتاح جلسات عادية عند `mustChangePassword`.

## 2. قرار الجهاز والإصدار

- تدعم `FableAuthGateway.login` الحقول الاختيارية `deviceName` (حد 191) و`appVersion` (حد 64). البيانات الخاصة بواجهة الجهاز ليست هوية مصادقة؛ `installationId` المستقل هو الحقل المرتبط بالجلسة.
- `FableLoginPage` تقبل `deviceName` اختياري تمرره الطبقة التي تجمع البيانات بموافقة المستخدم، و`appVersion` من Bootstrap أو `--dart-define=FABLE_APP_VERSION=1.2.3`. لا نختلق اسم جهاز ولا مدينة أو GPS، ولا نرسل IP الخام.
- عند وجود 2FA، تحتفظ `FableSecondFactorChallenge` بمعلومات الجهاز الموثقة وتستخدمها بعد إكمال OTP. `request` لا يرسل بيانات غير موجودة في DTO الخاص به.
- لا يضيف Flutter إشعارات أمنية وهمية: Backend يُنشئ **Outbox** عند الترحيب وتسجيل جهاز آخر وحد المحاولات الفاشلة؛ الإشعارات الداخلية مستقلة عن Firebase، وتعتمد FCM على تثبيت قدرات `notifications` و`push-notifications` وتسجيل الجهاز. تفاصيل الربط في [وثيقة حساب وأمان Backend](https://github.com/adnan118/Fable/blob/main/Fable-Backend-RC66/docs/ACCOUNT-SECURITY-NOTICES-RC67.ar.md). أزرار «هذه محاولتي/استعادة كلمة المرور» موجودة في `fable_notifications`، لكنها لا ترفع القفل الأمني ولا تتجاوز 2FA.

## 3. متطلبات Backend آخر وWizard

`ExternalAuthBinding` الحالي يدعم خرائط Login/Refresh/Logout فقط. **لا ندّعي أنه يدعم MFA عامة**. في حالة Backend غير Fable، لا يجوز فتح واجهات Fable للـOTP بناء على أسماء المسارات، ويظل دعم 2FA لدى Backend الآخر **غير متاح حتى يُستورد عقد كامل** يبين:

1. هل يحتاج العامل الأول إلى 2FA؟ وما شكل رد تحدي العامل الأول والطرق المتاحة ومدته ومجال الهوية؟
2. عمليات إرسال/إعادة إرسال OTP وإكماله، وطريقة Authorization، وحقول Request/Response، وحد الإعادات ومحاولات التحقق وأخطاء 400/401/403/409/429/503.
3. ربط الإثبات بحساب/تثبيت/جلسة وتغيير كلمة المرور أثناء التحدي، ومنع إعادة استخدام OTP.
4. سياسة تخزين Credential/Expiry واشتراطات Native Providers لو كانت المصادقة عبر Google/Apple/Passkeys بدلاً من OTP.
5. ما إن كان Backend الآخر يدعم `deviceName`, `appVersion` أو أمن الإشعارات، وعقودها المستقلة. لا نرسل أي حقل غير معلن.

**قبول Wizard:** يبدأ بسؤال نوع Backend. في Fable، يستورد عمليتي 2FA المعلنَتين ضمن عقد مشروع موقّع/مثبّت ويُظهر الاختيار فقط إن كان متوافقاً. أما Other، فيجب أن تبقى 2FA بحالة `unmapped` ولا يُعلن اكتمال Auth للـWizard قبل دعم Adapter مستقل واختبار إكماله فعلياً.

## 4. اختبارات ومخاطر

- `packages/fable_core/test/auth_rc85_two_factor_contract_test.dart`: مطابقة طريقة ومسار وعامة العمليات، أن لا تُرسل الأسرار عند خطأ العقد، صحة طرق التحقق المُعلنة، UUID v4، بيانات الجهاز، فصل التوكن عن OTP، وتطابق رد قناة الإرسال والمهل.
- `packages/fable_core/test/fable_second_factor_login_test.dart`: مسار العامل الأول ثم طلب OTP ثم إكماله، تغيير الهوية أثناء التحدي، وعقد غير مكتمل لا ينشئ جلسة.
- الحالات المفتوحة: اختبارات MySQL/OTP Outbox/FCM الحية، المحاولات القصوى وإعادة الإرسال، تبديل جهاز/تثبيت وكلمة المرور بين العاملين، انتهاء الصلاحية مع اختلاف ساعة الجهاز، Android/iOS Native OTP Autofill والتعريب/الأجهزة، عقود Other Backend وWizard المستقلة.

## 5. سجل الإنجاز

- **9 عمليات من 40** لديها تنفيذ واختبارات مصدرية موثقة: 7 من RC84 وعمليتَا 2FA الجديدتان.
- **31 عملية** `NOT_DECIDED`، و**0 ميزة معتمدة E2E من 17**.
- هذه المرحلة تغلق **جرد مصادر عمليتي 2FA فقط**، وليس اختبار خدمة OTP الحقيقية ولا كامل المصادقة أو إشعارات الأمن أو Adapter لـOther Backend.

# RC93 — تطبيق المصادقة الثنائية وتغيير البريد والهاتف في Fable Mobile

**المصدر المرجعي:** Backend الخاص `adnan118/Fable`، SHA `226cbcdc542ebe9c005d7445d84cc0ec10631932`. **Flutter:** المصدر RC92 الأساسي SHA `34775c768986fa12494fcc1e9b0e805fe7c36880`، وRC93 مستقل حتى نجاح CI. ليس اختبار E2E على بيئة حقيقية.

## التدفقات الموثّقة

| Feature | Backend RC66 | العقد المصدرّي |
|---|---|---|
| Two-factor Status | `GET /auth/2fa/status` | `enabled:bool`, `enabledAt:Date|null`, `methods:EMAIL_OTP/PHONE_OTP[]`؛ لا نفترض توفر طريقة غير معلنة |
| Enable 2FA | `POST /auth/2fa/enable` | `challengeId` UUIDv4 بعد OTP غرض `TWO_FACTOR`، `enabled:true`, `enabledAt`, `revokedOtherSessions:int` |
| Disable 2FA | `POST /auth/2fa/disable` | إثبات `TWO_FACTOR` جديد ومستهلك مرة واحدة؛ `enabled:false`, `revokedOtherSessions:int` |
| Change Email | `POST /auth/contact/email/change` | `challengeId` موثّق بغرض `CHANGE_EMAIL` إلى البريد الجديد، `newEmail` متطابق، و`securityChallengeId` عند الحاجة |
| Change Phone | `POST /auth/contact/phone/change` | `CHANGE_PHONE` إلى الرقم الجديد بصيغة E.164، مع `securityChallengeId` مستقل عند طلب الخادم |

**عمليات التحقق اللازمة:** `POST /auth/otp/request` و`POST /auth/otp/verify` للمستخدم الموثق. يختار الخادم طريقة الإرسال وفق قناة موثّقة لغرض `TWO_FACTOR`. تغيير البريد والهاتف يُرسل OTP إلى **الوجهة الجديدة** فقط. التحقق ذو الغرض `TWO_FACTOR` لا يصلح لغرض `CHANGE_EMAIL` أو `CHANGE_PHONE` أو `SENSITIVE_ACTION`. طول رمز `VerifyOtpDto` هو 6–10؛ رمز 2FA أثناء تسجيل الدخول له DTO آخر بطول 4–10.

### الضمانات المطبّقة في Flutter

- `packages/fable_core/lib/src/fable_auth_security.dart`: قراءة الحالة، طلب OTP بغرض محدد، التحقق من الرمز، والتفعيل والتعطيل الموثّق.
- `packages/fable_core/lib/src/fable_auth_contact.dart`: تغيير البريد والهاتف فقط بعد تطابق الوجهة مع طلب OTP، وإرسال إثبات `SENSITIVE_ACTION` المنفصل عند توفره وعندما يطلبه Backend.
- `packages/fable_core/lib/src/fable_auth_security_types.dart`: تحدد `FableSecurityOtpPurpose` وهوية Gateway والجلسة وطلب إثبات/نتيجة التغيير. لا تُخزَّن رموز OTP أو الإثباتات في SQLite/Preferences.
- `packages/features/fable_auth/lib/src/security_settings_page.dart`: واجهة Fable محمية في إعدادات أمان الحساب، تظهر فقط إذا نُشرت العمليات المناسبة في عقد المشروع. إذا طلب الخادم حديث المصادقة (403)، تُعرض عملية OTP أمنية ثانية ولا تُعاد المحاولة تلقائياً دون تأكيد.
- `packages/features/fable_auth/lib/src/sessions_page.dart`: بوابة وصول إلى إعدادات الأمان عندما يتوفر عقدها. لا تستخدم طرق Fable عند اختيار `Other Backend`.
- فاحص RC90 يتعرف على عمليات RC93 ومراجع الكود/الشاشة. أي Endpoint/DTO/إثبات مفقود يظهر كنقص في Terminal.

**لا نجاح وهمياً:** نجاح طلب OTP لا يثبت وصول SMS/Email، ولا تصبح 2FA مفعّلة أو جهة الاتصال محدثة قبل استجابة الخادم التي تؤكد الحالة والعدد. الاستجابة غير المتوقعة/انقطاع الاتصال تبقي النتيجة مجهولة وتحتاج إعادة قراءة حالة الحساب، لا إعادة إرسال العمليات بلا حدود.

## ما لا يزال مفتوحاً

- ربط Backend Fable مولّد حقيقي وعقده الموقّع وأجهزة Android/iOS؛ اختبار الغرض والوجهة والرمز الخاطئ/المنتهي/المستخدم سابقاً و429 و503 وحدث تغيير الحساب.
- اختبارات AAL2 وحالة `AUTH_RECENT_AUTH_REQUIRED` و`AUTH_INDEPENDENT_FACTOR_REQUIRED` على الجهاز والـBackend الحقيقي، وفحص أن عامل OTP مستقل فعلاً عن عامل الدخول الأساسي.
- اختبار إبطال جلسات الأجهزة الأخرى وتسجيل Push Token/إلغاء التسجيل وبقاء جلسة المستخدم الحالي حسب سياسة Backend.
- `Other Backend` يحتاج عقده ومصادقة/Token/Proof منفصلين، مع UI ورسائل خطأ متطابقة. لا تنسخ Endpoints المذكورة أعلاه.
- توطين صفحة إعدادات الأمان لكل لغات المشروع والتحقق من قابلية الاستخدام/إمكانية الوصول عبر أجهزة مختلفة.

**الحالة المصدرية بعد دمج RC93 المشروط بنجاح CI:** 22/40 Auth SOURCE_IMPLEMENTED_E2E_PENDING و18/40 NOT_DECIDED، 0/17 عائلات E2E حية. Backend main/PR #14 لا يتغيران إلا في **تثبيت مرجع Flutter** بعد الدمج. إصلاح Actions الخاص وإنتاج ZIP كاملة ما زالا مستقلين.

[خريطة كل العائلات](./FABLE-FULL-DELIVERY-ROADMAP-RC92.ar.md) · [ملف Auth](./FABLE-AUTH-OPERATIONS-RC80.json) · [مراجعة RC90 في Terminal](./FABLE-SELECTED-FEATURE-GAPS-RC90.ar.md)

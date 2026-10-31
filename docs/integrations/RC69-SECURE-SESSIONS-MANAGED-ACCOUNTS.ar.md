# RC69: إغلاق Auth Security Step-up والكيانات المُدارة — تنفيذ وقيود

**المصدر:** `main` لـFlutter بعد RC68، مع عقد Fable Backend الصحيح. هذا تنفيذ مصدر واختبارات آلية، ولا يوصف بـProduction-ready دون اختبار حي.

## 1. إلغاء الجلسات بإثبات Backend

- يعتمد `FableAuthGateway` على **المسار والطريقة المتطابقين مع العقد المستورد** وليس على `operationId` مفترض.
- عرض الأجهزة الفعلي من `GET /auth/sessions`؛ العمليات الحساسة: `POST /auth/sessions/{id}/revoke` و`POST /auth/logout-all`.
- يلزم التأكيد قبل الإلغاء؛ يرسل الخادم نجاحه أو رفضه. إن أعاد `AUTH_RECENT_AUTH_REQUIRED` يطلب التطبيق `SENSITIVE_ACTION` OTP عبر `POST /auth/otp/request` ثم يتحقق منه عبر `POST /auth/otp/verify`، ويضع `X-Security-Challenge-Id` في **عملية الإلغاء المحمية فقط**. لا يُخزَّن OTP ولا يُرسل إلى باك آخر.
- عند `AUTH_INDEPENDENT_FACTOR_REQUIRED` لا يتجاوز التطبيق المتطلب.
- إلغاء كل الأجهزة يُنهي الهوية المحلية بعد التأكيد الناجح من الخادم. يلزم التحقق من مسار إزالة Push Token المحلي في المشروع الذي يفعّل Firebase؛ الخادم يتحكم بإبطال تسجيل الأجهزة عبر أحداثه.
- يلزم فحص عملية `revoke-selected` على مشروع حقيقي قبل جعلها خياراً جماعياً في الواجهة.

## 2. Managed Accounts

المصدر النهائي في الباك الاختياري `managed-accounts`. لا تعرض Flutter شاشة الكيانات بمجرد أن المستودع يحوي هذا الـBlueprint؛ لا تظهر إلا إذا كان **العقد المستورد للمشروع** يعلن `GET /managed-entities`.

النقل الفعلي في `fable_profile`:

- `listMine`: قراءة كيانات المستخدم دون افتراض صلاحية من جانب Flutter.
- `activate`: استدعاء `POST /managed-entities/{id}/activate` ثم التحقق من `managedEntityId` و`access` واسم/قيمة `X-Fable-Managed-Entity-Id` القادمة من الخادم.
- `create`: إنشاء كيان بنوع يحدده المستخدم؛ Backend يتحقق من الأنواع والحد التجاري. `PRIVATE` و`INVITE_ONLY` و`PUBLIC` خيارات العرض التي يفحصها Backend.
- `myInvitations`, `accept`, `decline`, `invite`: عمليات دعوات مؤهلة بالعقد، مع حظر `OWNER` في دعوة عضو.
- `executeInContext`: لا يحقن رأس الكيان في كل الطلبات؛ الاستعمال فقط لعملية مشروع محمية يحددها المبرمج صراحةً، ثم الخادم يتحقق من العضوية في كل مرة.
- تغيير الحساب أو الهوية يلغي السياق المحلي. لا تُخزّن عضوية/دور أو Credential خاصة بالكيان.

**بقية دورة Managed Accounts** مثل `disable/enable/delete-request/restore` و`member.remove` تتطلب نقل كل تفاصيل عقود OTP (قد يكون `TWO_FACTOR` أو `SENSITIVE_ACTION` وفق حساب المستخدم) والصلاحيات؛ لا تُعرض أزرار لها حتى توثيق رحلة الإثبات. لا يجوز محاولة مسارات تخمينية أو تمرير OTP لنوع إثبات خاطئ.

## 3. Other Backend

عندما يختار Wizard نوع `other`:

- لا يحمل `FableContract`، ولا تظهر `FableManagedAccountsPage` أو `FableSessionsPage` الخاصة بـFable.
- رأس `X-Security-Challenge-Id` ورأس `X-Fable-Managed-Entity-Id` مرفوضان على Transport خارجي في الكود.
- لكل Backend آخر كتالوج Operation وخريطة أدوار ومصادقة منفصلتان يجب التحقق منهما؛ لا تستخدم هذه الموصلات الخاصة بفايبل كبديل.

## 4. اختبارات الإغلاق

- `packages/fable_core/test/sensitive_session_contract_test.dart`: طلب OTP والتحقق ثم الإلغاء، رفض الإثبات على مسارات أخرى، عدم تخريب الهوية بعد Logout-All.
- `packages/features/fable_profile/test/managed_accounts_repository_test.dart`: السرد والتفعيل ومطابقة الرأس، تبدل الهوية، وحظر العقود غير الموجودة والردود المزورة.
- `flutter analyze` و`flutter test` لجميع الحزم، ثم `flutter build apk --debug` و`flutter build ios --simulator` تحت CI.

**حدود لا يمكن تجاوزها بتعديل الكود فقط:** العقد المرفق في `ci_fable` تجريبي ويحوي 9 عمليات Auth/Account؛ لا يثبت تشغيل كل الـ50 Backend Blueprints أو 17 Feature على مشروع مولّد. أكمل الدمج بعد الاختبارات الآلية، ثم اختبر عمل مشروع حقيقي بالـBackend المرتبط، وفعل Firebase على جهازين، وتحقق من إعادة استخدام OTP، إبطال الجلسة، تبديل الحسابات والكيانات والصلاحيات.

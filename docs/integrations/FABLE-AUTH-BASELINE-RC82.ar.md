# RC82 — تدقيق أساس Auth: Logout وSession Timezone

**الخطّة الملزمة:** [السجل الرئيسي](./FABLE-FLUTTER-PARITY-MASTER.ar.md) · [قائمة Auth الأربعين](./FABLE-AUTH-OPERATIONS-RC80.json) · [القرارات العامة](./FABLE-BACKEND-WIDE-DECISIONS-RC81.ar.md) · [دليل BLoC](./FLUTTER-BLOC-LEARNING.ar.md).

## ماذا وجدنا في Backend الحقيقي؟

اعتمد الفحص على `Fable-Backend-RC66/src/platform/auth/auth.controller.ts` و`auth.service.ts` و`dto/update-session-timezone.dto.ts` و`blueprints/capabilities/auth/manifest.json`. هذه مصادر قالب Fable، **وليست نسخة مشروع مولد حي**.

| العملية | عقد Fable ومصدر السلوك | ما طبقه Flutter RC82 |
|---|---|---|
| `auth.logout` | `POST /auth/logout`، Bearer، يستدعي `revokeSession`، ويعيد `{revoked,sessionId,clientActions:['DELETE_LOCAL_PUSH_TOKEN']}` | لا يعلن نجاح الإلغاء على الخادم إلا عند `revoked === true`؛ يمسح بيانات الدخول المحلية حتى عندما يكون رد الخادم ناقصاً أو الشبكة مقطوعة؛ لا يمسح اعتماد مستخدم دخل أثناء الطلب |
| `auth.session.timezone` | `POST /auth/session/timezone`، Bearer، `{timeZone}` بطول لا يتجاوز 64، ثم تحقق IANA في Backend، واستجابة `{updated:true,timeZone}` | Gateway يتحقق من العملية والطريقة والمسار وAuth، ويرسل اسم المنطقة، ويرفض Response لا يطابق الطلب؛ شاشة الجلسات تعرض الإدخال فقط عند وجود العقد |
| `auth.session-policy` | `GET /auth/session-policy` عام، سلطة التشغيل في `AUTH_SESSION_POLICY` و`AUTH_SESSION_MAX_ACTIVE` و`AUTH_SESSION_OVERFLOW` و`AUTH_SESSION_ONE_PER_INSTALLATION` | موجود مسبقاً عبر `FableSessionPolicy` وقراءة وقت التشغيل؛ يحتاج اختبارات مشروع حي عند تغيير السياسة |
| `auth.sessions` | `GET /auth/sessions` محمي؛ يسرد الأجهزة مع `isCurrent` ومدة الصلاحية، ولا يعرض Refresh Tokens | موجود مسبقاً مع DTO آمن؛ يستلزم تجربة Revocation وStep-up على مستخدمين/أجهزة حقيقية |
| `auth.login` و`auth.refresh` | `POST` عامان مع Bearer tokens، `clientType=flutter` و`installationId`؛ Refresh مع Rotation وReplay Detection | Gateway وSecureStorage واختبارات Race موجودة؛ لكن عقد المشروع الفعلي والتزامن مع Backend حي لم يعتمدا بعد |

## سلوك مشترك وليس ميزة مستقلة

- **الـLogout لا يعني بالضرورة نجاح Remote Revocation.** على حالة Timeout أو رد `revoked:false`، يعرض التطبيق أن الاعتماد المحلي حُذف بينما الإلغاء على الخادم لم يؤكد؛ يجب أن يعالج مستخدم التطبيق اختلاف هاتين النتيجتين.
- **Push Token Cleanup** في Fable مطلب مهم: الخادم يطلب `DELETE_LOCAL_PUSH_TOKEN` ويزيل الارتباط مع AuthSession. إذا اختار الـWizard حزمة `fable_push_notifications` واستُعملت، فهي تستمع إلى `FableIdentityEvent` وتنفذ حذف FCM Token؛ **لا** نضع Firebase في `fable_core`. يظل الاختبار الحي ومسار إلغاء الربط ضرورياً.
- **Timezone ليست جدولة.** منطقة الجلسة للعرض فقط، ولا تغير المواعيد التجارية أو timestamps المخزنة UTC. لا نعتمد `DateTime.now().timeZoneName` كقيمة IANA؛ قد تكون اختصاراً غير صالح. يقدم المستخدم قيمة موثقة، ويتحقق الخادم من وجودها.
- **لا نعيد تشغيل mutation تلقائياً** لمجرد انقطاع الاتصال. إن تم تغيير هوية المستخدم أثناء الطلب، تتجاهل الواجهة الرد حتى لا تعرض بيانات الحساب السابق.

## ماذا يجب أن يقدمه Backend آخر؟

- **Logout:** عملية موثقة باسم ومسار خاصين به، نوع الاعتماد (Bearer/Cookie/custom)، دليل إبطال الجلسة الحقيقية، متطلبات حذف Push Token، أخطاء الاستدعاء، وحدود الإلغاء عند فشل الشبكة. نجاح HTTP لا يثبت وحده إبطال الجلسة إلا إذا كان ذلك جزءاً مثبتاً من عقد Backend الآخر.
- **Session Timezone:** اختياري؛ إن لم توجد العملية يبقى حقل المنطقة الزمنية غير ظاهر. إذا وجدت، يلزم Method/Path/Body Field، تحقق الخادم من IANA، معنى رد النجاح ونطاق التغيير (الجلسة لا إعدادات المشروع)، وأخطاء 400/401/403 والـRevision.
- **السياسات العامة:** العقد الأوسع لـ`Login/Refresh/Sessions` ومدة الجلسات/عددها والأجهزة وسياسة تجديد التوكن، وحقول الـDTO، وليس نسخة من أسماء عمليات Fable. يظل الـWizard على مسار `other` منفصلاً، ويبدأ `pending` إذا لم تُثبت القدرات والـMappings.

## حالات الاختبار والبوابات المفتوحة

**وحدة Core:** رد `revoked:false`، النجاح المؤكد، تبديل الحساب قبل وصول الرد، طلب تحديث المنطقة مع Bearer ومن دون رأس الكيان، غياب العملية، إدخال غير آمن، اختلاف الرد، وتبديل الجلسة. **Widget:** ظهور الحقل فقط في عقد Fable الموثق.

**غير معتمد بعد:** تشغيل Backend على MySQL، جلستان من جهازين، تغيير IANA والتحقق من القيمة بعد إعادة الدخول وRefresh، تنظيف Push Token على Android وiOS، اختبار إصلاحات Backend الأمنية المفتوحة، وعقود Other Backend. لذلك تظل `auth.logout` و`auth.session.timezone` بعلامة `SOURCE_IMPLEMENTED_E2E_PENDING`، و37 عملية Auth ما زالت `NOT_DECIDED`، ولا يُغلق Issue #15.

**التسلسل التالي:** تدقيق Login/Refresh/Sessions/Session Policy بصورة مكتملة بالـDTO والـError Envelope والـWizard، ثم بقية Auth مع إغلاق شروط E2E في بيئة حقيقية.

# RC142 — المرحلة الرابعة: تفعيل الواجهات بقرارات Backend الحقيقية

**المرجع:** خارطة المراحل السبع الأصلية Fable (29 أكتوبر 2026)، وليست خطة جديدة.
**النطاق:** Flutter `main` بعد RC140؛ اختيار `fable` أو `other` من Wizard. Source acceptance ≠ provider/runtime acceptance.

## سبب التعديل
القدرات الـ17 لها شيفرة واختبارات، لكن أغلبها لا يملك حتى الآن شاشة استخدام نهائية. كانت `FableFeature.screen()` تعود إلى `FableCapabilityScreen` التي تسرد أسماء العمليات، ما قد يجعل وجود وحدة برمجية يبدو وكأن المنتج جاهز. كذلك كانت `FableContract.isFeatureAvailable` تعيد `true` عند غياب قرار Backend في عقد قديم.

## ما أصبح مطبقًا
1. `isFeatureAvailable` صار **fail-closed** عند غياب `frontendSetup.decisions.frontendFeatures.enabled`. لا يُستنتج تمكين من اسم Blueprint أو package أو keyword.
2. `FableFeature.canLaunchFable(contract)` يرجع `false` افتراضيًا؛ هذا يمنع شاشة عمليات عامة من الظهور في التطبيق.
3. خمس شاشات مستخدمين موجودة بالفعل أضيف لها تحقق حقيقي من قرار القدرة وعمليتها:
   - **Auth** — `auth.login` عبر POST عام، وفق إعداد الخادم
   - **Profile** — `account.me` عبر GET محمي
   - **Notifications** — `notifications.inbox` GET محمي و`notifications.read` mutation محمية
   - **Localization** — `languages.list` GET، ولا يدّعي هذا ترجمة المحتوى
   - **Content** — `content.page.read` + `content.publicChanges` + `content.page.accept`، مع فصل المنشور عن المسودات
4. تطبيق Fable لا يعرض هذه الواجهات دون `FABLE_API_BASE_URL` وقرار `frontendFeatures` مؤكد. Push navigation يخضع لنفس `canLaunchFable`.
5. عند اختيار **Other Backend**، لا تُعرض شاشة شبكة دون `externalScreen` صريحة ومتحققة من عملياته المربوطة. تمت إزالة عرض واجهة باسم العملية فقط في Debug.
6. الكود والمكتبات الـ17 **لم تُحذف**. عدم ظهور شاشة Home لا يعطّل خدمة Native/Background التي تُركّب مستقلاً (Offline/Deeplinks/Analytics وغيرها).

## الوضع الحقيقي للقدرات الأصلية الـ17
| القدرة | نوع التنفيذ الحالي في Flutter | شرط الإكمال |
|---|---|---|
| Auth | شاشة وعقد مصدر | 2FA/OTP/Recovery/Device/DB E2E وسائر القرارات |
| Profile | شاشة الحساب وعقود كيانات مُدارة | دور/عضوية/دعوة/سياق مقيّد مع DB وأجهزة |
| Notifications | Inbox وشاشة وعمليات | FCM/APNs وOutbox وجلسات حقيقية |
| Media | Source/player/upload adapters مستقلة عن Home | LOCAL ملفات كبيرة وDRM KSM وAndroid/iOS/Backend E2E |
| Localization | صفحة لغات/اختيار لغة | ترجمة كاملة وRTL ونصوص خادم |
| Support | Repository/Widgets فقط | **لا API Support عام مضمون في Fable RC66**؛ عقد مشروع أو Other حقيقي |
| Social | Adapters/Widgets | OAuth SDK/nonce/MFA ومزوّد حي |
| Biometrics | Passkey ports/Widgets | RP ID/WebAuthn أصلي وتسجيل/حذف/تحقق |
| Realtime | SSE/sync ports | RTC/LiveKit منفصل، auth/reconnect |
| Deep Links | Native policy/dispatcher | Verified App/Universal Links وأذونات |
| Messaging | Repository/Composer | Inbound webhook **ليس** Send API؛ يلزم عقد إرسال موثق |
| Location | Geo/provider adapters/Widgets | صلاحية OS وخرائط ومزوّد وقيود |
| Payments | Read-only payment status/repository | Checkout/Capture/Refund وIdempotency/UNCERTAIN حقيقي |
| Offline | Queue/Drift/sync engine | Delta/ETag/Conflict + Background OS والأمان |
| Analytics | Opt-in queue + injected Sink | اختيار Sink فعلي وموافقة وخصوصية/retention |
| Content | واجهة محتوى منشور + قبول | Worker/DB وPrivacy consent ومحرر الأدوار |
| Access Control | Snapshot/session/guards | Grants/Revocation وسياق الحسابات الحقيقية |

## القاعدة المعمارية
- **Fable:** القرارات والعمليات من مشروع Fable المصدّر ومُعرّف بهوية/Hash، وBackend يفرض الصلاحيات.
- **Other Backend:** عقد OpenAPI/Custom خاص، مع Auth/DTO/permission mappings مستقلة؛ لا تسمح التسمية المشتركة لعملية بإعارة جلسة Fable أو صلاحياته.
- Flutter لا يمنح صلاحيات، لا يزوّر DTO، لا يتحول إلى clear DRM، ولا يعرض UI تشغيلية عند غياب قرار Backend.
- قدرات Client/Hybrid لا تُمسح من المولّد بسبب غياب Backend؛ تظل قرارات Flutter/OS مستقلة.

## اختبارات وقبول
- `test/rc142_verified_feature_activation_test.dart`: قائمة الـ17، شاشات المستهلك الموثقة، غياب سياسة Backend، تعطيل القدرة، اختلاف method.
- `test/rc142-verified-feature-activation-audit.test.mjs`: منع إظهار preview بدل عمل فعلي.
- CI ينفذ الـNode gate ثم `flutter analyze`, `flutter test`, Android Debug وiOS Simulator.

**لم ينتهِ Stage 4 وظيفيًا:** يحتاج عقد ومزوّد E2E لكل قدرة مختارة، وعمليات لا توفرها نسخ Backend الحالية لا يمكن إنشاؤها بالتخمين. راجع [RC141 #74](https://github.com/adnan118/Fable_flutter/issues/74) وخريطة [RC138 #23](https://github.com/adnan118/Fable/issues/23).

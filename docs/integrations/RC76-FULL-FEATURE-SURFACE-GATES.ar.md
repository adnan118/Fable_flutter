# RC76 — فحص التغطية التشغيلية لجميع ميزات Fable Flutter

**التاريخ:** 2026-10-31  
**النطاق:** 17 فئة Flutter ظاهرة في `lib/src/generated/feature_registry.dart`، تتبع Backend المصدر الذي اختاره الـWizard فقط.

## القاعدة: لا نجاح بمجرد وجود Package

قدرة المشروع ليست `READY` إلا إذا ثبت كل جزء مطلوب **بالعملية المناسبة لهذا النوع من المشروع**:

1. **Source contract:** الواجهة والمطوّر استوردا عقد Backend مختوم الهوية `projectId + contractHash`، أو عقد External موثّق مستقل. `ci_fable` ليس مشروعاً حقيقياً.
2. **Operations:** أحصِ كل `operationId` مطلوب للـMobile وفق طريقة HTTP، URL، المعلمات، DTO، رمز الاستجابة، Pagination، Auth، Step-up، الصلاحيات، والأخطاء. خصائص Admin/Web فقط تميّز صراحة كغير موجهة للمستخدم النهائي ولا تنقل تلقائياً.
3. **Data:** نماذج مقيّدة وقابلة للتحقق، توثيق قيم `nullable` و`enum`، سياسات تغيّر البيانات والإصدارات.
4. **State/Repository:** حماية التزامن، Refresh/Caching/Offline والتعافي بعد تبدّل الهوية عند الحاجة؛ عدم اختراع مسارات لباك آخر.
5. **Real UI:** لكل رحلة مستخدم مطلوبة شاشة وعناصر إدخال ورسائل نجاح/خطأ وPermissions Gate، لا قائمة من `GET/POST` فقط. الواجهات الخاصة بنوع Managed Entity/دور لا تظهر تلقائياً لكل مشروع.
6. **Wizard:** يسأل عن نوع Backend **أولاً**، ويستورد قدراته وصلاحياته، ثم يسأل عن خيارات Flutter المستقلة (مثل Deep Links وOffline) فقط. عدم وجود عملية في العقد يعني عدم إتاحة تشغيلها، ولا يؤدي إلى حذف الحزم المحلية دون قرار صريح.
7. **Tests:** unit + Widget + source contract + تجربة Backend مولّد وقاعدة بيانات وFCM + Android/iOS والمصادقة والاشتراكات وخلل الشبكة والتبديل بين الحسابات.

## وضع الفئات الـ17 في الكود — ليس اعتماد إنتاج

| الميزة | موصل البيانات/الشاشة التي رُصدت | ما يمنع ختم «مكتملة» |
|---|---|---|
| Auth | Login, Sessions, SessionPolicy, OTP/2FA/Step-up من العمليات المستوردة | كل طرق الهوية المعتمدة فعلياً، تبديل الجهاز والجلسات، صلاحيات وتحديات ودورة E2E |
| Profile | Account + Managed Entities وMembers/Invitations | إعادة فحص كل صلاحيات المالك/المدير وحالات دعوة/إيقاف/حذف واستعادة ومشاريع متعددة |
| Notifications | Inbox وMarkRead وPush-navigation | توكن FCM والتسجيل والإبطال والتحقق من تغيير الجهاز والخصوصية على جهازين حقيقيين |
| Media | Contract/Metadata + upload prepare/status/chunk/part/complete/abort + Resumable Upload Card | Picker وربط جميع الـmedia consumption/ACL/Protected playback مع Backend فعلي وR2 |
| Localization | `languages.list`, `languages.clientCopy` ونسخ محفوظة | تطبيق لغة الواجهة على كل الشاشات، مصادر النصوص الديناميكية، RTL، تعافي Offline وتغيّر الأسعار |
| Support | Repository/Widgets عامة | يحتاج عمليات Support Client موثّقة من Backend المختار؛ لا يجوز اختراع endpoints |
| Social | Google/Apple Repository adapters | تنفيذ Native SDK/Provider tokens، متطلبات MFA وlink/unlink ورفض الحسابات المتصادمة |
| Biometrics | Passkey Repository/Widgets | المنصة والبصمة الأصلية والتحدّي وE2E وتفويض Backend |
| Realtime | Source SSE/change sync | كل subscriptions المطلوبة لمشروع محدد وإعادة اتصال/تفويض/شاشات |
| Deep Links | Local dispatcher والسياسات الأصلية | إثبات HTTPS association والأهداف المسموح بها على Android/iOS |
| Messaging | Typed Repository/Widgets | تدفق الدردشة/الرسائل الحقيقي فقط عند توفر عقود موثّقة وصلاحياتها |
| Location | Repository/Widgets | أذونات الهاتف والخصوصية والفشل والمصدر الحقيقي |
| Payments | Read-only status/repository | Checkout/Refund/Settlement/حالات UNCERTAIN حسب مزود الباك؛ لا اختراع endpoints |
| Offline | Local queue/capability | سياسات تعارض Sync، هوية الحساب، عدم تكرار mutations وأثر السعر والحجوزات |
| Analytics | محلي/هجين | Consent وTelemetry contract وBatch/Offline، دون تسريب PII |
| Content | Public index + read/accept، RC75 Rich Text | تنزيل Media موثّق، كل أنواع الـBlocks ومراجعة النشر المجدول في Backend Issue #12 |
| Access Control | Permissions snapshot وRole View/Gates | تحقق من إبطال الصلاحيات وتحديثها عند تغيير الدور/العضوية، واختبارات متعددة الحسابات |

## مخرجات Audit الإلزامية

`node tools/audit-backend-feature-parity.mjs <project-root> [projectId contractHash]`

- `featureMatrix`: لكل ميزة `operationCount` و`sourceWiredOperationCount` و`screenWiredCount` و`missingOperationIds` و`nativeScreen` و`completeFeature=false`.
- `auditScope.unclassifiedBackendOperationIds`: عمليات مستوردة لا تنتمي بوضوح إلى الفئات الـ17؛ تُراجع ولا تُهمل.
- `auditScope.unimplementedOperationIds`: العمليات غير مربوطة أو ذات ربط قديم.
- `auditScope.featuresWithoutNativeScreen`: ميزات `server` بلا شاشة مستخدم أصلية؛ قد تحتاج شاشة حسب مشروع Backend.
- لا توجد أي حالة `liveVerified=true` تلقائية؛ العقد الاستعراضي `ci_fable` له 9 عمليات فقط، وهو غير كافٍ لتحليل جميع صلاحيات Backend.

**المقصود من RC76:** منع تضخيم نسبة الإنجاز وإظهار النواقص بدقة، ثم تنفيذ وتوثيق كل عملية ومراحل الاستخدام فعلياً. لا يُعتبر Report بديلاً عن تنفيذ الميزات.

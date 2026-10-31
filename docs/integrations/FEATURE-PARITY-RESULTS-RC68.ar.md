# نتائج تدقيق القدرات — Backend/Fable Flutter RC68

**تاريخ التدقيق:** 2026-10-31. **القاعدة:** `main` بعد RC67. هذه مراجعة كود وعقود واختبارات آلية؛ ليست اختبار E2E على خادم مولّد حقيقي.

## معنى النتائج

- **Core UI wired:** يوجد UI/Repository يقرأ Operation ID موثقاً؛ لا يعني نجاح التشغيل الحي.
- **Adapter/Repository only:** يوجد تنفيذ مقيد بالعقد لكن عرض الواجهة النهائية أو شمول جميع عمليات الباك غير مثبت.
- **Frontend-owned:** قدرة محلية لا يجوز حذفها لمجرد عدم وجود مسار في Backend.
- **Not audited:** لا توجد عمليات الباك ذات الصلة ضمن العقد المستورد في عينة CI؛ لا يجوز تحويل هذه الحالة إلى Done.
- **E2E verified:** يتطلب خادماً مولداً، بيانات وصلاحيات، أخطاء، طلبات فعلية، واختبار Android/iOS. **لم تُمنح هذه الحالة لأي ميزة في هذا التدقيق.**

## سبب عدم جواز إعلان اكتمال 17 قدرة

القائمة في `lib/src/generated/feature_registry.dart` تحتوي **17 ميزة**. عقد CI داخل `assets/contracts/contract.json` و`mobile-core-operations.json` يحتوي **9 عمليات فقط** (`Auth` و`Account`)، وهو تابع للتطبيق التجريبي `ci_fable`، ولا يتضمن `frontendFeatures` للمشروع الحقيقي.

تم تحديث `tools/audit-backend-feature-parity.mjs` ليصدر `auditScope` و`featureMatrix` لكل ميزة: ملكيتها، وجود الحزمة، تسجيلها في الواجهة، قرار الباك إن كان متوفراً، العمليات الموجودة في **العقد المستورد فقط**، عدد موصلات المصدر والشاشات، ومؤشر `liveVerified=false`.

## مراجعة الميزات الأساسية

| الميزة | حالة المصدر | الفجوة التي تمنع إعلان اكتمالها |
|---|---|---|
| Auth | Core UI wired | إلغاء الجلسات المحمي بـStep-up، تغيير عوامل الأمان، اختبار الجلسات الحي وأجهزة متعددة |
| Profile | Core UI wired | بيانات حساب المستخدم الأساسية موجودة؛ لا واجهة متكاملة لـManaged Accounts أو الملفات الخاصة بكل مشروع |
| Notifications | Core UI wired | Inbox وربط العمليات موجود؛ FCM يحتاج اختبار توكن/إبطال/خروج؛ إشعارات السياسة وحدث الجهاز تحتاج اختبار DB/Outbox حي |
| Media | Adapter/Repository only | رفع متقطع وR2 ومسارات موثقة؛ تحتاج رحلة Upload/Resume/Download/Protected playback على خادم فعلي |
| Localization | Adapter/Repository only | قائمة اللغات؛ لا إثبات لربط جميع الترجمة الديناميكية وثبات RTL والمحتوى دون اتصال |
| Support | Adapter/Repository only | واجهات ومخزن إرسال؛ تحقق من عمليات الطلب/الرد الحية وصلاحيات العميل مطلوب |
| Social | Adapter/Repository only | Google/Apple/link/unlink في Repository؛ يلزم تنفيذ SDK/MFA والحالات المتزامنة |
| Biometrics | Adapter/Repository only | Passkeys تحتاج Capability صريحة، UX تأكيد المستخدم واختبار iOS/Android |
| Realtime | Adapter/Repository only | تتبّع تغيّر المحتوى وبعض البنية؛ لا اكتمال مضمون لجميع Websocket/Realtime subscriptions |
| Deep Links | Frontend-owned | القرار محلي، يلزم ربط deep-link ومسارات التطبيق ومصادقة الأهداف في كل مشروع |
| Messaging | Adapter/Repository only | موصل إرسال مقيد بالعقد؛ لا يجوز استخدام Webhooks الواردة كواجهة إرسال |
| Location | Adapter/Repository only | Repository/Widgets؛ التحقق من الصلاحيات والخصوصية وFallback والموقع الحقيقي لكل منصة |
| Payments | Adapter/Repository only | قراءة حالة دفع موثقة فقط؛ لا Checkout/Refund/Settlement/Store Billing كاملة |
| Offline | Frontend-owned | توجد طوابير محلية؛ لا يجوز تفسيرها كمزامنة شاملة لجميع كيانات باك المشروع |
| Analytics | Frontend-owned/hybrid | Sink محلي باشتراك المستخدم؛ لا endpoint أو لوحة تحليل مفترضة |
| Content | Adapter/Repository only | عرض صفحات منشورة/قبول نسخة؛ يلزم صفحة تحديث الخصوصية وربط نسخها الحية |
| Access Control | Adapter/Repository only | Snapshot للأذونات؛ يلزم إثبات تغيّر الأدوار والتحديث الحي وRole-based layouts |

## Managed Accounts — فجوة مستقلة عالية الأولوية

يوجد **`managed-accounts`** في مخطط Backend الاختياري ضمن
`blueprints/capabilities/managed-accounts/manifest.json`، ويتضمن عمليات مثل:
`managed-accounts.list`, `managed-accounts.create`,
`managed-accounts.activate`, عمليات الدعوات والموافقات والأرشفة.
هذا لا يعني أن الميزة مثبتة في **كل** مشروع مولَّد.

في `Fable Flutter` توجد صفحة `FableAccountPage` لبيانات المستخدم الأساسية فقط، **ولا يوجد حالياً** تدفق كامل لإدارة كياناته الفرعية أو اختيار سياق الكيان. لا يجب إضافة شاشات Managed Accounts إلى مشروع لا يحتوي عقده على العمليات المطلوبة، ولا يجب اعتبار صلاحية User الشخصي إذناً على كيان فرعي؛ مطلوب سياق عضوية وصلاحية تؤكدهما Backend.

**الخطوة التالية بعد الفحص:** إضافة تدفق `list / activate` مقيد بـOperation ID إذا كان `managed-accounts` مثبتاً، ثم `create / invite / accept / disable` مع صلاحيات وStep-up موثقين، واختبارات فصل مستخدم/كيان وتجربة حقيقة.

## متطلبات ما قبل الاعتماد

1. استيراد `dist/client-contract` من المشروع الحقيقي والتحقق من `projectId` و`contractHash` باستقلال عن ملف الاستيراد.
2. مقارنة **كل** `operationId` نشط مع Repository/Model/Screen/Permissions/Errors؛ عدم وجود مسار يتركه `NOT_MAPPED`.
3. تشغيل اختبار E2E للباك مع قاعدة بيانات ومستخدمين وأجهزة مختلفة: تسجيل وOTP وإشعارات ونشر سياسة وصلاحيات كيان.
4. تشغيل Android/iOS مع FCM وOffline وNetwork failures وBackground/recovery.
5. تكرار المراجعة للباك **غير Fable** من كتالوجه الخاص، لا من هذه القائمة.

لا تُحذف حزم `client` أو `hybrid` عند غياب API من الباك؛ تبقى إدارة الحزم من ملكية Flutter.

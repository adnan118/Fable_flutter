# RC161 — المرحلة الرابعة: توثيق مسارات Notifications Inbox

**المصدر الفعلي:** `adnan118/Fable` — `Fable-Backend-RC66/src/platform/notifications/notifications.controller.ts` في Backend main `ee82b2ffc977187c4e79cfdad51da681a60aabde`.

## المشكلة

كانت `FableInboxPage._supported` و`FableNotificationsFeature.canLaunchFable` تتحققان غالبًا من مجرد وجود معرفي `notifications.inbox` و`notifications.read` وطريقة GET/POST بصورة جزئية. وجود معرف العملية وحده لا يثبت مسار الخدمة ولا يمنع توجيه طلب إشعار شخصي إلى مسار آخر قد يملك اسم عملية مطابقًا. ولا يكفي وجود الحزمة للتأكد من تفعيل الميزة في إعدادات Backend.

## إصلاح RC161

أضفنا `FableInboxRoutePolicy.verified(contract)` ونستدعيه **قبل إظهار أيقونة الميزة** وقبل تشغيل شاشة الصندوق أو إرسال طلباتها. يتحقق من:

- سياسة `contract.isFeatureAvailable('notifications')` — الميزة مختارة ومسموحة من قرارات Backend. السياسة الغائبة ليست إذنًا ضمنيًا.
- `notifications.inbox` = `GET /notifications/inbox` محمي ومصرح بالمصادقة في العقد.
- `notifications.read` = `POST /notifications/{id}/read` أو الصيغة المكافئة في المصدر `/notifications/:id/read`، محمي ومصرح بالمصادقة.
- كلا العمليتين `requiresAuth=true` و`enforceAuth=true` وبصمة العملية SHA-256 بشكل صحيح، دون اعتماد Header أسرار إضافي كأنه Bearer تلقائي.
- رفض أي مسار مختلف، ومنها مسارات الإدارة والبث، وطريقة DELETE/PATCH أو غياب التفعيل.
- عدم لمس سياسة `Other Backend`؛ يحتفظ بكتالوج عملياته وDTOs وتحقق الربط المستقل، دون توريث مسارات Fable.

**لا تغيّر Backend ولا تستدعي موفّر FCM/APNs**. حماية الإشعار حسب جمهور المستخدم تتحقق من الخادم في `NotificationsService.inbox` و`markRead`، وليس من UI وحدها.

## فحوص RC161

اختبارات الحزمة `rc161_fable_inbox_route_policy_test.dart` تتضمن: المسارات الفعلية (OpenAPI وNestJS)، تزوير الوجهة مع معرف صالح، تغيير طريقة HTTP، إسقاط Auth، تغيير سياسة التفعيل، وتأمين استقلال IDs الخارجية. تُنفذ ضمن RC49 مع Flutter analyze، وAndroid debug، وiOS 27 dual-simulator.

## الحدود

هذا إغلاق **ثغرة ربط مصدرية للـNotifications UI**، لا يُعتمد منه تسليم رسالة FCM/APNs إلى جهاز حقيقي أو حساب مستخدم فعلي. لا يوجد عقد مشروع غير تجريبي مثبت الهوية في تطبيق `ci_fable` بعد؛ #82 لم يُغلق. تستمر فجوات Support #35، سرقة Bearer+installation #33، الـ17 قدرة بشكل منفصل، وجاهزية الإنتاج Stage7 **NO-GO**.

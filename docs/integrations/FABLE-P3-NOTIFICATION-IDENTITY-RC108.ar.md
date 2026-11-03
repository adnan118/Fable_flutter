# RC108 — P3 Notifications: Session-bound Tap Navigation

**قاعدة المصدر:** Flutter/main عند RC107: `692d862e2ddde0ce172517fc477ced351ea5047f`.

## سبب الإصلاح
في الملاحة عبر إشعار Push أو Inbox، كان `isAuthenticated()` يتحقق من وجود
جلسة ثم تنفذ الملاحة بعد `await`. لو استُبدلت هوية A بـ B أثناء الانتظار،
لا يكفي وجود توكن حديث لحماية الوجهة؛ فقد يفتح تنقل بدأه إشعار A داخل حساب B.

## قرارات RC108
- `FableNotificationNavigation.identityRevision` وظيفة اختيارية من الجلسة
  الموثّقة، وليست Permission ولا JWT مخزّنًا في الإشعار.
- كل عملية `open()` تثبّت إصدار الهوية وقت البدء وتتحقق منه بعد فحص
  المصادقة، وقبل استدعاء روابط/ميزات المشروع، وبعد الاستدعاءات غير المتزامنة،
  وقبل الرجوع إلى Inbox. إذا تبدّلت الهوية يُرفض التنقل بدلاً من إكماله.
- تطبيق Fable يربط مصدر الإصدار بـ `FableSecureSession.identityRevision`
  من العقد المحدد سواء كان Fable أو Other Backend مع عقد Auth مثبت.
- كل `identityEvents` تبطل عمليات التنقل التي بدأت قبل الحدث.
  Logout يمسح Pending؛ Login يستطيع استئناف ضغطة إشعار مؤجلة من حالة
  غير مصادق بها، لكنها تخضع للتأكد من الهوية الحالية.
- `_fableNavigateFromNotification` يلتقط جلسة وإصدار هوية ويعيد التحقق
  بعد تهيئة `_bootstrap` وقبل `Navigator.push`. لا يكتفي بنتيجة
  `isAuthenticated` السابقة.
- لا يتغير Backend، ولا يتم افتراض API، ولا تمنح الإشعارات أذونات.
  وجود `target` في Push لا يثبت حق الوصول؛ وجهات التطبيق المسموح بها
  وBackend يبقيان المصدر النهائي.

## المحاكاة واختبارات المصدر
- `packages/features/fable_notifications/test/notification_identity_navigation_rc108_test.dart`:
  تغيّر المستخدم أثناء فحص Auth المعلّق، وجلسة مستقرة، وتسجيل الدخول بعد
  التنقل المؤجل، وتغيّر المستخدم أثناء URL callback، وLogout، وتنظيف reset.
- `test/rc108-notification-identity-audit.test.mjs`: يؤكد ربط الجلسة
  في التطبيق وحراسة العمليات بعد `await`، ولا يعتبر فحص نص المصدر
  بديلًا عن تشغيل Flutter tests.
- CI: Node source audit + Flutter analyze + تطبيق/حزم اختبارات +
  Android Debug + unsigned iOS Simulator.

## الحدود المعلنة
- اختبارات Flutter تستخدم `Completer` لمحاكاة تأخر التحقق والاستجابة؛
  **لا تعني P6 Backend/DB/FCM/APNs/device E2E**.
- لا يستطيع Flutter إلغاء تنقل نفذه callback بالفعل قبل تحديث الجلسة؛
  يجب أن يفحص كل callback صلاحية الوجهة والهوية عند استخدامها، لا قبله فقط.
- لا يُنظّم RC108 إنشاء/إبطال Token FCM أو ضمان حذف تسجيل الجهاز من
  Backend بعد Logout. هذه فجوة مستقلة في P3/P6.
- سياسة الملاحة المسندة إلى `Other Backend` لا تستورد مسارات أو معاني
  صلاحيات Fable. كل تطبيق يتحقق من Catalog الخاص به.
- لا يُعد أي من 17 Feature عائلة مقبولة إنتاجيًا دون عقد مشروع حي و
  اختبارات صلاحيات/أجهزة متكاملة.

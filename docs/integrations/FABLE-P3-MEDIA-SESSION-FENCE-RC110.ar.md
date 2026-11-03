# RC110 — P3 Media: تثبيت هوية الجلسة خلال الرفع والاستئناف

**الأساس:** `adnan118/Fable_flutter@6b9f3e5d2f5b973ebc4a37a8f11caa100c8604f2` (RC109، main CI ناجح 3/3).

## الفجوة المعالجة
رفع الوسائط في Flutter كان يثبّت سبع عمليات مصادق عليها من Backend،
ويحسب SHA-256 محلياً ويعتمد تقدم الخادم فقط. لكن `start/resume` لا يثبتان
إصدار هوية الجلسة عبر انتظار `prepare`، أو Hashing، أو Checkpoint،
أو `status/chunk`، أو `R2 part PUT` و`partAck`، أو `complete`.
قد ينتقل التنفيذ المتأخر من حساب A إلى حساب B بعد `await` دون أن يكون
الرد صالحاً لواجهة B.

## التغيير التنفيذي
- `MediaUploadRepository` يلتقط `identityRevision` مرة واحدة لكل
  عملية رفع/استئناف/إلغاء، ويعيد فحصه قبل وبعد كل إرسال عبر
  `_execute`، وقبل وبعد العمليات المحلية الطويلة، وقبل تسليم
  أي تقدم من الخادم أو نتيجة إكمال.
- `FableAuthGateway` يوفّر هوية Fable المؤكدة من
  `FableSecureSession.identityRevision`. لا يُقبل مصدر مختلف يمرره
  المستهلك لهذا المسار.
- عند اختيار `Other Backend` يجب تزويد Repository بمصدر
  `identityRevision` وفاحص `isSessionCurrent` من **جلسته المستقلة**.
  إذا غاب أيهما تُرفض تهيئة Repository بدل التخمين.
- يتم التحقق من `CancelToken` طوال المسار، وليس أثناء حلقة الأجزاء
  فقط؛ فلا يمكن متابعة نشر أجزاء بعد Pause/Cancel عند عودة
  استجابة متأخرة.
- في `S3_MULTIPART` يرفض العميل إرسال `partAck` إذا تغيّر
  حساب المستخدم أثناء `putPart` إلى Cloudflare R2. لا يعيد إرسال
  كتابة تلقائياً؛ يجب الاستئناف من `GET status` مؤكّد.
- في `LOCAL_RESUMABLE` لا يرسل الجزء التالي أو `complete`
  بعد تغيّر الجلسة، حتى لو رجع طلب `chunk` السابق بنتيجة ناجحة.
- `cancel` يحفظ Intent المحلي قبل طلب DELETE. إذا تغيّرت الهوية
  أثناء ذلك، لا يُرسل `abort` باستخدام اعتماد الحساب الجديد.
- لا يتغير شكل DTO، أو عمليات العقد السبع، أو مصدر Progress؛
  صلاحية وصول Backend تظل السلطة النهائية.

## المحاكاة والاختبارات
- `packages/features/fable_media/test/media_identity_transfer_rc110_test.dart`:
  Fake Gateway، ملف محلي تجريبي، وFake R2 Transport، مع `Completer`
  لضمان تبديل A→B أثناء `prepare` و`status` و`chunk`
  و`putPart` وCheckpoint وIntent الإلغاء؛ واختبار مسار
  نجاح ثابت مع إقرار أجزاء محلية على الخادم الوهمي.
- `test/rc110-media-identity-audit.test.mjs` يراجع أن كل عمليات
  HTTP السبعة تمر عبر الحارس ذاته، ويمنع عودة اتصال مباشر
  `gateway.execute` خارج `_execute`.
- فحص CI: Node، تحليل Flutter والحزم، Android Debug APK،
  iOS Simulator غير موقّع.

## ما لا تثبته RC110
- هذا ليس E2E حياً على Backend/DB/R2/Android/iOS.
- قد تكون كتابة قديمة عولجت على الخادم قبل أن يلاحظ العميل
  تغيّر الجلسة؛ رفض الرد محلياً لا يُلغي أثرها على Backend.
- لا يستطيع العميل استرجاع `saveCheckpoint` اكتمل في تخزين خارجي
  قبل رصد تغير الجلسة. يجب أن يكون `MediaUploadCheckpointStore`
  مقيداً بـSHA-256 مصدره هوية Backend والحساب، وأن تخضع
  إعادة الاستئناف لإعادة تحقق الملف والخادم.
- لا يغيّر RC110 سياسات تنظيف أجزاء R2 المتروكة أو نشر ملفات
  مكتملة؛ تتطلب اختبارات خادم حقيقية ومراجعة worker/quotas.
- لا تُرفع `liveE2EVerified` لأي ميزة ولا يُعلن إغلاق P3/P6.

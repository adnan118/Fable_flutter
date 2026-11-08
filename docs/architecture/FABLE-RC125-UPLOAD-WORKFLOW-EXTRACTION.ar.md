# RC125 — فصل دورة رفع الملفات عن Widget (Track B · 2026-11-08)

**المرجع:** RC124 merged Flutter/main `faa9e6d89b8e4dff46bdaf07c207c2407d268e4e` وقد اجتاز فحص main المستقل [#42358117635](https://github.com/adnan118/Fable_flutter/actions/runs/42358117635) بثلاث وظائف ناجحة. Backend الخاص لا يتغير؛ أي ملف محلي أحدث من GitHub لا يُستبدل.

## لماذا هذا التغيير؟
كان `resumable_upload_card.dart` ينسق `repository.start/resume/cancel`، يقرأ ويكتب checkpoints ويحتفظ برمز إلغاء Dio ويراقب هوية الجلسة مباشرة. هذا خلط بين Presentation وApplication وData وأحد ديون RC114 الصريحة.

## ما الذي نُفذ؟
- `domain/upload_workflow_port.dart`: عقد Domain لا يعرف Flutter أو Dio أو File أو Fable أو URL، وحالات/نتائج تقدم typed.
- `application/resumable_upload_workflow.dart`: منسّق مستقل لمسارات restore / start / resume / pause / cancel / dispose. أحداث تبديل الحساب ترفض كل الردود اللاحقة وتلغي العملية قبل تغيير حالة الواجهة؛ `generation` و `identityRevision` يفصلان A→B.
- `data/media_upload_workflow_adapter.dart`: يحصر `CancelToken` وملف `dart:io` والتحقق من SHA-256 وعمليات المستودع وإصرار حفظ Checkpoint في الطبقة الصحيحة؛ يتعامل مع `MediaUploadRepository` نفسه، دون طرق Backend جديدة.
- `media_upload_widget_composition.dart`: نقطة تكوين Legacy منفصلة لتوصيل Port للـUseCase؛ يحافظ على الاختيار الموثوق لـFable/Other Backend.
- `resumable_upload_card.dart`: عرض الحالة فقط، الأزرار وأخطاء AR/EN المأخوذة من `UploadFlowProblem`. لم يعد ينفذ عمليات HTTP/التخزين/تسلسل الرفع.

## أمن وسلوك يجب ألا يتغير
- Auth events مفقودة → لا تظهر أزرار الرفع (fail closed).
- إلغاء المستخدم → إزالة checkpoint المحلية أولاً، ثم `DELETE` فقط إن بقي الحساب نفسه، وإلا تُعرض `cancellationUnconfirmed` إن فشل DELETE.
- الاستئناف → تحقق SHA-256 وحجم الملف من Data/Repository، ولا تُعاد كتابة الجزء المرفوض تلقائياً.
- التبديل A→B أو Dispose أو Pause → إلغاء العملية ورفض الأحداث والردود القديمة؛ لا استخدام لـCheckpoint حساب A في UI حساب B.
- `onCompleted(Map<String,dynamic>)` محفوظ **للتوافق فقط**؛ يعبر عبر Receipt تحتوي `Map<String,Object?>` ولا يتم تخزينها في Application. ترحيل DTO النهائي هدف RC126، ولا ندعي أن MediaUploadRepository القديمة صارت typed بالكامل.

## بوابات القبول
- الفحوص المصدرية RC111 وRC114 وRC115 وRC125.
- اختبارات `media_upload_workflow_rc125_test.dart` الجديدة + اختبارات Widget RC111 القائمة + كل Feature Packages/Flutter analyzer.
- بناء Android APK وXcode27 iPhone+iPad UIScene tests دون تخفيف أي شرط؛ فحوص مشغّل الفيديو RC122–RC124 قائمة بلا تغيير.

## الحدود المفتوحة
`media_read_repository.dart` لا يزال يمرر Map خاماً، وHTTP media-specific موجود في Core؛ المستودع القديم الخاص بالرفع يحمل Backend JSON. P6: لا توجد اختبارات على أجهزة حقيقية أو Backend/MySQL/R2 deployed، ومؤشرات liveE2EVerified=0/17 لم تتغير. RC125 ليس جاهزية إنتاج أو إصدار APK/IPA موقّعاً.

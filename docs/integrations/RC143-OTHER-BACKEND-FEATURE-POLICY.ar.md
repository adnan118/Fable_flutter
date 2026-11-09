# RC143 — فحص قرارات الكتابة عند اختيار Backend آخر

هذا التعديل جزء من **المرحلة الرابعة الأصلية لـFable**: تكامل Flutter مع قرارات الخادم، وليس مجرد إظهار قدرات في الـHome.

## Backend الآخر (OpenAPI / Custom)
عند استيراد `feature-operations.json`، يجب أن تطابق العمليات ملف `external-operations.json` من حيث `sourceHash` و`operationsHash`. لا تسمح هذه المطابقة وحدها باعتبار كل عملية مناسبة للموبايل. الآن:
- كل `read/list` تلتزم بالـmethod في كتالوج الخادم وتظل ملزمة بإدارة هوية المستخدم حسب العملية.
- `create/update/remove/markRead` لا يُسمح بها إلا مع `requiresAuth=true` و`enforceAuth=true` وBearer User Auth. لا تُرسل عمليات كتابية عامة أو أسرار Backend إلى Flutter.
- أي عملية `auth:'provider'` أو `credentialHeader` أو مسار `/webhooks/` أو معرف يحوي `webhook` **ممنوعة** من أن تصبح دورًا لواجهة مستخدم. Webhook الوارد ليس API إرسال.
- **Payments:** يتعمد الرابط العام رفض `create/update/remove/markRead` حتى لو كان POST محميًا، إلى أن يُبرمج Adapter مالي typed ومعتمد بـIdempotency/If-Match وStep-up وProvider UNCERTAIN. `read` يبقى متاحًا حسب العقد.
- `notifications.markRead` ما يزال يتطلب مصادقة ومعرف إشعار `{id}` موثقًا.
- أسماء الميزات المربوطة تُفحص ولا يمكن إدخال معرف شاذ أو حقول مصطنعة.

هذه القرارات نفسها تطبق داخل أداة `wizard:check` و `wizard:check:strict`، لذا لا يعطي الـWizard إشارة نجاح لمشروع سيرفضه Flutter وقت التشغيل.

## Backend Fable
لا تُعدل خوارزمية ترخيص Fable أو عقوده بواسطة `Other`. جميع أدوار Fable تؤخذ من `FableContract` وعملية الخادم المُصدَّرة؛ لا تُجرى إعارة لرموز Fable/الأدوار إلى Backend آخر.

## الاختبارات
- اختبارات Dart للتحقق من طلب Support سليم، ورفض public POST/provider keys/webhook/checkout العام، مع السماح بقراءة Payment.
- اختبارات Node لأداة Wizard تفحص الأخطاء الدلالية نفسها، وفحص CI يضمن وجود الحراسة.
- الاختبارات الحية على Backend محدد غير متوفرة بعد، وبالتالي Stage 4 لا يمكن إعلان اكتمالها E2E.

سجل المتابعة: [RC141 Stage 4 #74](https://github.com/adnan118/Fable_flutter/issues/74).

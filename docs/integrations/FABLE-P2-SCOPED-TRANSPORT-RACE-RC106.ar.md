# RC106 — P2: إغلاق سباق النقل ورفض 403 بعد تغيير الحساب الفرعي

**Source baseline:** Flutter/main RC105 merge `8e292f96ede307a51a2d1d808de295ba42c2586d`.

## السبب
- كانت `executeBoundInStore` في RC105 تتحقق من تطابق العملية `operationId/method/path/contractHash` مع المشروع وتمنع استخدام مسارات عامة. نحافظ على هذا القرار بالكامل.
- بقي سباقان: رفض `403` لحساب A يمكنه أن يصل بعد التحويل إلى B فيحذف اختيار B؛ وقد يتغير الكيان أثناء انتظار Credentials قبل دخول الطلب إلى الشبكة.

## تغييرات Flutter فقط
1. `executeUsingStore` يلتقط جلسة Fable، وهوية Backend، `selectionRevision` واختيار `FableManagedAccountSelection`. يمرر `sameContext` إلى `executeInContext` ومنها إلى `executeInManagedEntity`.
2. `UnifiedApiClient.request` و`_send` يرفضان طلبًا مرتبطًا بكيان إذا تغيّر السياق قبل الإرسال، في كل محاولة HTTP retry، وبعد استلام الرد. لا يطبق الحارس على طلبات غير مقيّدة، ولا تتغير عقود Auth.
3. رفض 403 أو `MANAGED_ACCOUNT_NOT_FOUND` يمسح الحساب **فقط إذا ظل هو نفسه الحساب الجاري**. رد A الذي يتأخر عن اختيار B يُرمى بخطأ 409 ولا يلمس B.
4. `FableManagedScopedOperation.validate` يبقى حاجز العقد في RC105. لا غلاف بديل يلتف حوله؛ `executeBoundInStore` يستدعي واجهة التنفيذ نفسها بعد إثبات العقد.

## اختبارات محاكاة دون Backend حي
- اختبار `RC106 delayed 403 for A never clears newly selected B` عبر Dio interceptor.
- اختبار `RC106 authoritative 403 on active entity clears its own selection`.
- اختبار `RC106 entity switch while token is pending prevents scoped PATCH dispatch` بمحاكاة انتظار جلب التوكن؛ عدد طلبات HTTP الفعلي للمُحاكي يجب أن يكون صفراً.
- تبقى اختبارات RC105 للعقود وA→B→A وWizard في CI. نتائج Flutter Analyze وAndroid وiOS Simulator تُراجع على Commit المدمج أو PR بشكل مستقل.

## حدود الضمان
- المحاكاة ليست اختبار Backend فعلي أو قاعدة بيانات أو جهاز حقيقي. لا نعلن اكتمال P6.
- لا يستطيع التطبيق إلغاء أثر Mutation وصلت فعلياً إلى Backend قبل تغيير الحساب؛ يجب إعادة التحقق والخادم هو مرجع الصلاحيات.
- 401/403، Refresh وIdempotency وتزامن عضويات متعددة تحتاج E2E مستقل عند توفر البيئة.
- لا تعديل على Backend الخاص ولا على عمليات Auth الأربعين، ولا إنشاء مسارات API.

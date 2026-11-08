# RC127 — حماية الوصول لكل وسائط Flutter حتى مع API عامة

**الحالة:** تغيير عميل ضمن PR #68 (غير مدمج). المرجع المقابل: PR #16 في مستودع Backend **الخاص** (لا تُنسخ شيفرته إلى هنا).

## السياسة
- يجب أن تكون كل صورة وفيديو ومقطع صوتي ومستند وVariant تحت Media Playback Authorization مستقل، حتى لو كانت metadata معروضة عبر واجهة API عامة أو كان السجل `visibility=PUBLIC`.
- عقد التشغيل المستورد لا يُقبل إذا كان `protection.enabled` أو `forcePrivate` أو `requireAuthorizationGrant` غير صحيح، أو كان `directPublicUrls` أو `directDownload` أو `drm.queryTokensAllowed` مسموحًا.
- `MediaAssetAccessMode` في Fable Domain لا يقبل إلا `protected`. أي `signed/public/authenticated` من Backend قديم يُرفض، وحتى الوسائط المحمية تُرفض إذا أعادت `access.url` أو غاب `playbackEndpoint` المتوقع لذلك الوسيط.
- لا تقم بإظهار وسائط محمية عبر `Image.network` أو URL عام. استخدم byte source يحضر بايتات الوسيط من Backend باستخدام Auth + X-Fable-Media-Token من جلسة مخصصة للملف، ويُبطل الحالة عند تبديل الحساب/إلغاء Playback.
- لا تستخدم Token في Query Param ولا تُخزنه أو تُظهره في Toast/Logs/Analytics. المخزن المؤقت للصور يجب أن يكون مقيدًا بالحساب والوسيط والعمر المسموح؛ الأفضل التعامل مع الصور الخاصة في الذاكرة دون مشاركة عبر Cache عام.

## قيود تشغيل الويب والتطبيق
- المسار المباشر للملف خارج التطبيق، سواء في المتصفح أو أداة curl، يجب أن يرفض بدون Authorization الفعلي والـMedia Token وتحقق Playback Session في Backend؛ لا يكفي CORS أو Origin.
- للموقع العام الذي يعرض صورة دون تسجيل دخول مستخدم: يلزم تصميم BFF/guest session ذات إصدار مرخص، HttpOnly cookie، ومنع مشاركة الموارد بين الزوار. مصدر Backend الحالي يفرض AuthSession فعلية، لذا ستُحجب بايتات الوسائط عن الزوار المجهولين حتى إنشاء هذا المسار المصرح بشكل منفصل.
- رمز صالح مأخوذ من تطبيق مصرح يمكن إعادة استخدامه إلى أن ينتهي أو يُلغى؛ منع ذلك بشكل أقوى يتطلب attestation وربطًا بالأجهزة، ولا يمنع أخذ لقطة خارجية لكاميرا.

## القبول
1. اختبارات parser ترفض جميع access modes غير protected للأربعة IMAGE/VIDEO/AUDIO/DOCUMENT وبالحالتين PUBLIC/PRIVATE.
2. ترفض عقد Runtime يعلن تعطيل الحماية أو URL public أو GET مباشر أو Query DRM token.
3. CI الكامل (Flutter test/analyze/packages، بناء Android، Xcode27 UIScene على iPhone+iPad، decoder Android Media3/iOS AVPlayer) على SHA واحد قبل الدمج.
4. خارج CI: اختبار Staging Backend عبر المتصفح دون Authorization والـCDN/bucket المباشر، مع ضمان عدم وجود static route للمجلد المحلي. نجاح هذه الخطوات لا يمكن استنتاجه من Flutter/CI وحده.

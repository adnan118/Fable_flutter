# Fable Flutter — Media مع Backend فايبل أو Backend آخر (RC137)

## اختيار صريح عند تركيب المشروع

ينشئ **Wizard** اختيارًا إلزاميًا:

- `FABLE`: أدابتر Fable فقط، يعتمد على `OperationCatalog` المستورد والمتحقق منه، وعقد `GET /media/client-contract` من المشروع المنشور.
- `OTHER`: أدابتر منفصل حسب مستندات الخادم الآخر. **لا تستورد ولا تخمّن** `FableAuthGateway`، `media.upload`، `/media/:id`، أو Cookie/Token الخاصة بفايبل.

`ProjectMediaBackendBinding` هو عقد تركيب صريح. للمشغل الواحد `ProtectedPlayerSession` تُحقن `DescribedMediaByteSource`:
- فايبل: `FableMediaByteSource` أو `FablePublicGuestByteSource` (وفق نوع الترخيص).
- آخر: `OtherBackendProtectedMediaSource` بعد تنفيذ `OtherBackendVerifiedMediaTransport` والتحقق المستقل من Auth والـRange والجلسة والتصاريح في Backend الآخر.

`OtherBackendMediaDeclaration` يشترط التخزين الخاص، التفويض عند قراءة كل Range، عدم وجود روابط تنزيل عامة، عدم وصول مفتاح التشفير إلى العميل، ومنع ادعاء DRM دون مراجعة التراخيص. صحة ادّعاء العقد مسؤولية دمج وإجراء اختبارات E2E، لا يثبتها مجرد Boolean.

## واجهة مستويات التشفير

| المستوى | UI developer label | سلوك API/client |
|---|---|---|
| `NONE` | بدون تشفير محتوى | وصول بجلسة محمية وHTTPS، لا تصريح عام للبايت |
| `LOCAL` | تشفير محلي دون اشتراكات | Backend يفك AES بعد التفويض، لا مفتاح في Flutter |
| `DRM` | DRM Widevine/FairPlay | استخدم مشغل CDM/licensed KSM، لا clear fallback |

**Fable LOCAL RC136:** `FableLocalEncryptedBufferedUploader` يدعم `POST /media` (Multipart) مع عملية `media.upload` المتحقَّق منها من Fable؛ يفحص `MediaRuntimeCapabilities` ويمنع استئناف/Multipart إذا كان السيرفر لا يدعمه. حجم افتراضي 20MiB. لا تستخدم واجهة `ResumableUploadWorkflow` لهذا المستوى حاليًا؛ اعرض خيار رفع محدود بآلية واضحة أو استخدم `FableLocalEncryptedBufferedUploader` مباشرة عند اختيار LOCAL. خيار الملفات الكبيرة من الخريطة التالية، غير مكتمل.

**OTHER LOCAL:** ليس شرطًا أن يدعم الخادم الآخر AES-256-GCM نفسه؛ استخدم Contract الخاص به وفحوصه الحقيقية. لا تُنقل أسرار من خادم إلى واجهة Flutter.

## واجبات المبرمج:
1. اختَر Backend صراحة في Wizard؛ استورد عقده وأثبت الحماية/العمليات.
2. اربط هوية الجلسة وإبطالها بمصدر الوسائط *من Backend المختار فقط*.
3. اربط قراءة bytes بالـRange الموثق لدى Backend، وسلوك 206 وContent-Range دون cache عام أو token في URL.
4. اشترط `encryptionTierVerified=true` قبل عرض المستوى المحلي على أنه مفعل.
5. اختبر المستخدم A→B أثناء تحميل Chunk، وتغير المحتوى، وانتهاء التوكن، والتحويل من/إلى DRM. لا تقبل silent fallback.
6. لا تعِد مستخدمك بأن LOCAL يمنع حفظ الصور أو تصوير الشاشة؛ هو تشفير تخزين يفك على السيرفر.

**الحالة:** كود تكامل ومشغّل ورفع LOCAL محدود؛ لا توجد اختبارات Dart/Android/iOS/Web متصلة مؤكدة في بيئة تشغيل حقيقية. راجع قضايا القبول والمراحل التالية.

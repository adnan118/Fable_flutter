# RC136 — اختيارات حماية Media للمبرمج Flutter
يراجع Backend الخاص بالمشروع أولًا. هذا الملف عام ولا يتضمن مفاتيح أو شيفرة Backend الخاصة.

## الخيارات التي تظهر لمطور المشروع
| الخيار | الاسم في العقد | أين يُشفّر المحتوى؟ | ما واجب Flutter؟ |
|---|---|---|---|
| بلا تشفير | `NONE` | لا AES للمحتوى في مخزن Backend الخاص | يطلب جلسة Protected Stream وتوكن صلاحية |
| محلي دون أي اشتراكات | `LOCAL` | AES-256-GCM داخل Backend فقط؛ لا حساب أو منصة مطلوبة | نفس مسار المشغل المحمي؛ **لا يحمل مفتاح ولا يفك AES** |
| Widevine/FairPlay | `DRM` | CMAF CBCS، يملك Backend مفاتيحه المغلّفة ويطلب تراخيص KSM مرخصًا | يطلق مشغل DRM Android/iOS/Web المدعوم، مع طلب license آمن ورفض أي Clear fallback |

**حتى في NONE لا تُظهر direct object URL.** مستوى التشفير مختلف عن ترخيص المستخدم وعرض `PUBLIC` في الكتالوج. يجب تمرير `X-Fable-Media-Token` وجلسة وسائط صالحة للقراءة. نسخة الزائر تحتاج Guest Lease والكوكي/التوكن حسب Backend الحالي.

يقرأ `FableMediaReadSource.runtimeContract()` الحقل `protection.encryptionTier` ويحوّله إلى `MediaRuntimeCapabilities.encryptionTier`، مع `encryptionTierVerified`. استخدم `MediaEncryptionTierDeveloperLabels.labelAr` و`explanationAr` في واجهة الإعداد، مع توضيح أن التبديل الحقيقي في Backend أثناء توليد المشروع أو نشره؛ لا ترسل قيمة tier ضمن طلب رفع من المستخدم العادي.

عند `encryptionTierVerified == false` الخادم يستخدم عقدًا قديمًا؛ لا تعرض علامة «تشفير محلي نشط». العقد الجديد يرفض تضارب `encryptionTier` مع `drm.enabled` أو ادّعاء AES محلي دون `atRestEncrypted=true`.

## مهام Flutter
- `NONE`: مشغل Protected Byte Source العادي؛ لا local key؛ لا direct GET عام.
- `LOCAL`: نفس المشغل؛ السيرفر يفك الملف بعد مصادقة الطلب، ولذلك يستطيع المشاهد المصرح به نسخ البيانات. طبق سقف الرفع الذي يحدده Backend (v1: buffered upload `POST /media`, حتى 20MiB افتراضيًا)، وعطّل زر الاستئناف والمقاطع الكبيرة.
- `DRM`: اعتمد استجابة Playback Session `MULTI_DRM`، و`X-Fable-DRM-Token` لطلب الترخيص، و`Widevine` على Android والمتصفحات المدعومة و`FairPlay` على Apple. إن لم يتوفر خادم تراخيص حقيقي، أظهر حالة عدم الجاهزية بدل إرسال MP4 واضح.
- لا تضع `MEDIA_LOCAL_ENCRYPTION_KEY_B64`، DRM content keys أو أسرار KSM في Dart، build flags، SharedPreferences أو logs.
- إذا تغيّر tier بين إصدارات Backend، اطلب إعادة تحميل العقد ولا تفترض أن الوسائط القديمة تم ترحيلها.

**حالة التسليم**: عقد Flutter + اختبارات Decoder فقط، لا اختبار أجهزة فعلي أو SDK مرخص. إجراءات التحقق معلّقة في Backend issue #21 وFlutter issue #70 حتى تسمح بيئة الاختبارات بالتشغيل.

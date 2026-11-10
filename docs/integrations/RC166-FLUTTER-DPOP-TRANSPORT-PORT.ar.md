# RC166 — Flutter DPoP transport integration port (Stage 4)

**10 تشرين الثاني 2026** — حالة المسودة، لا تستخدم GitHub Actions معيار قبول.

## ما تم

- `FableDpopProofSigner`: واجهة حقن لتنفيذ منصة أصلي يحتفظ بمفتاح P-256 الخاص في Android Keystore أو iOS Keychain/Secure Enclave حين يتوفر. هذه الواجهة لا تنشئ مفتاحًا ولا تخزن مفتاحًا ضمن Dart، ولا تعطي تنفيذًا احتياطيًا برمجيًا.
- `UnifiedApiClient`: يحقن الموقّع فقط إذا كان العقد `FableContract` والناقل `FableTransportAdapter`، ويحوّل `Authorization` إلى `DPoP` للطلبات المحمية. `DPoP` في الترويسات العامة و`Dio BaseOptions` ممنوع.
- يولّد إثباتًا للعمليات العامة التي تنشئ جلسة فقط، وبمسار وطريقة مطابقين للعمليات المعلنة: Password Login وRefresh و2FA complete وOTP complete وGoogle/Apple.
- كل محاولة HTTP `_send` توقّع إثباتًا جديدًا؛ إثبات `jti` المستهلك لا يعاد استخدامه عند GET retry أو بعد تدوير Refresh Token.
- `FableAuthGateway` يرفض تخزين جلسة تعلن `tokenType=DPoP` من دون موقّع، أو جلسة Bearer عندما اختار التطبيق موقّعًا. المشاريع الأقدم دون DPoP لا تتغيّر افتراضيًا.
- اختبارات `rc166_fable_dpop_transport_port_test.dart` تغطي التفويض والإثبات للطلب المحمي ولـlogin العام، إعادة توقيع retry، عدم تسرب الإثبات للعمليات العامة غير المتعلقة بالدخول، رفض Other Backend وDio ambient header.

## ما لم يُنجز

هذه **ليست** حماية أجهزة مكتملة. `FableDpopProofSigner` هو منفذ حقن فقط، وليس تنفيذ Android/iOS للمفتاح أو توقيع ES256 حقيقيًا. بيانات التوقيع في اختبار Dart صورية لفحص الترويسات وليست إثباتًا صالحًا على Backend.

كذلك لم يتوفر Flutter SDK أو محاكيا iOS وAndroid داخل بيئة الفحص الحالية؛ لم يتم تشغيل `flutter test` ولا `flutter analyze`، ولم نُجر اتصال HTTPS بحساب مصادق عليه أو ننشر RC166. يحتفظ Backend RC165 [PR #37](https://github.com/adnan118/Fable/pull/37) بحالة DRAFT، وخادم Render لا يزال RC155.

## قبول الإصدار لاحقًا

يتطلب الإغلاق: تطبيق موقّع حقيقي أصلي للمفاتيح في Android/iOS، حفظ/ربط هوية المفتاح الصحيح عبر تبديل الحسابات وإعادة تثبيت التطبيق، تشغيل Flutter offline tests على SDK مناسب **بدون GitHub Actions**، تشغيل بناء Backend وPrisma، قاعدة MariaDB حقيقية وعقد مشروع غير تجريبي، ثم اختبار حسابين عبر HTTPS لسرقة Bearer+Installation ID، إعادة تشغيل `jti`، Refresh، Logout، صلاحيات Support وMedia.

**قرار:** لا دمج ولا نشر على Render قبل نجاح تلك الشروط؛ ثغرة [Backend #33](https://github.com/adnan118/Fable/issues/33) لا تزال مفتوحة.

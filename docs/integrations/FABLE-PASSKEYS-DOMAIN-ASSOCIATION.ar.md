# Fable — ربط نطاق Passkeys الفعلي مع Android وiOS

**الحالة:** أداة إصدار ملفات مراجعة محلية `RC262`، وليست نشرًا أو تحققًا حيًا أو تصريح إنتاج.

يتطلب إكمال ميزة Passkeys ثلاثة أطراف متطابقة: نطاق RP الذي ضبطه Backend رسميًا، هوية تطبيق Android مع شهادة التوقيع الحقيقية، وهوية تطبيق iOS مع Team ID وتوقيع/Entitlements فعلي. لا يكفي أن يعمل MethodChannel أو أن يمر تحليل Dart.

## مدخلات مشروع حقيقي

بعد استيراد عقد Backend والتأكد من `assets/contracts/contract.json` و`flutter-handoff.json`، ضع ملف JSON داخل مشروع Flutter يُدخل بياناتك الفعلية بالشكل التالي (استبدل كل قيمة إيضاحية بالهوية **الحقيقية** قبل التشغيل):

```json
{
  "kind": "fable.passkey-domain-association",
  "schemaVersion": 1,
  "projectId": "REAL_BACKEND_PROJECT_ID",
  "backendContractHash": "REAL_64_CHARACTER_SHA256",
  "rpId": "REAL_HTTPS_RP_HOST",
  "android": {
    "packageName": "REAL_ANDROID_APPLICATION_ID",
    "sha256CertFingerprints": ["REAL_COLON_SEPARATED_32_BYTE_SHA256_CERTIFICATE"]
  },
  "ios": {
    "teamId": "REAL_APPLE_10_CHARACTER_TEAM_ID",
    "bundleId": "REAL_IOS_BUNDLE_ID"
  }
}
```

الأداة ترفض هذا المثال كما هو، وتتحقق من فهرس العقد الموثّق **بوضع المشروع الحقيقي** قبل إنتاج أي ملفات.

الأمر الواحد بعد توفير البيانات الحقيقية:

```bash
pnpm wizard:passkeys:domains -- --root . --config .fable/passkeys-association.json --out .fable/passkey-domain-review
```

لا تضع ملف القيم الحقيقية في GitHub قبل مراجعة سياسة مشروعك. شهادات التوقيع المذكورة **بصمات عامة** وليست المفاتيح الخاصة، لكن معلومات هوية المشروع ما زالت تحتاج إدارة واعية.

## ما يُنتَج وما لا يُنفّذ تلقائيًا

- `site/.well-known/assetlinks.json` لربط Credential Manager مع نطاق RP بواسطة `delegate_permission/common.get_login_creds`.
- `site/.well-known/apple-app-site-association` بلا امتداد لإثبات `webcredentials` لهوية `TEAMID.bundleID`.
- `ios/FablePasskeys.entitlements` كمقطع مراجعة لقائمة `com.apple.developer.associated-domains`.
- `backend/Passkeys-origin-review.env` بقيمتي `AUTH_PASSKEY_RP_ID` و`AUTH_PASSKEY_ORIGINS` للمراجعة، بما فيها أصل Android `android:apk-key-hash:<SHA256_BASE64URL>` المحسوب من شهادة التوقيع الفعلية. يُسمح بـ HTTPS RP أصلًا للـ iOS؛ قد تحتاج أصول الويب الأخرى إلى إضافتها يدويًا بعد التوثيق.
- `README.md` يحدد خطوات النشر والتحقق المطلوبة، مع بصمة عقد Backend.

الأداة لا تغيّر Application ID، ولا توقع Android/iOS، ولا تكتب تلقائيًا فوق Entitlements الفعلية، ولا تنشر الملفات على النطاق. يجب دمج إعدادات التوقيع الصحيحة، ونشر ملفات `.well-known` عبر HTTPS، وفحص Android Digital Asset Links مع شهادة الإصدار الحقيقية، والتحقق من Associated Domains وApple CDN على جهاز iPhone فعلي.

يجب أن يتطابق `rpId` حرفيًا مع `AUTH_PASSKEY_RP_ID` الموثوق لدى Backend، وأن تتضمن `AUTH_PASSKEY_ORIGINS` أصول التطبيق/الويب الصحيحة وفق متطلبات WebAuthn. عدم التطابق يفشل إغلاق W6.

للمرجع الرسمي:

- Android: https://developer.android.com/identity/credential-manager/prerequisites
- Apple: https://developer.apple.com/documentation/authenticationservices/supporting-passkeys/
- Apple Associated Domains: https://developer.apple.com/documentation/Xcode/supporting-associated-domains

**القرار حتى التشغيل والاختبارات الحقيقية: `NO_GO`.**

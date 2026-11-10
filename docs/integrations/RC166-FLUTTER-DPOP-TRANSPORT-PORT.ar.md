# RC166 — توقيع DPoP الأصلي في Flutter وAndroid وiOS

**10 تشرين الثاني 2026** | المرحلة الرابعة | **مسودة غير مدمجة وغير منشورة** | لا نعتمد على GitHub Actions.

## الإنجازات الفعلية في PR #88

1. **Android:** `FableDpopNativeBridge.kt` يستخدم `AndroidKeyStore` لإنشاء زوج مفاتيح P-256، ويرفض أي مفتاح لا يبلّغ النظام أنه داخل عتاد آمن (`KeyInfo.isInsideSecureHardware`). يوقّع `ES256` ويحّول توقيع ECDSA من DER إلى P1363 كما يتطلب JWS. `jti` عشوائي مختلف لكل طلب، و`ath` هو SHA-256 لرمز الوصول الحالي. المفتاح الخاص لا يعبر `MethodChannel`.
2. **iOS:** `FableDpopNativeBridge.swift` ينشئ مفتاح P-256 دائمًا داخل **Secure Enclave** باستخدام Security.framework، ويستخرج المفتاح العام فقط لإنشاء JWK، ويوقّع `ecdsaSignatureMessageX962SHA256` ثم يحول DER إلى P1363. أُضيف الملف إلى `Runner.xcodeproj`، وتُسجّل القناة ضمن `FlutterImplicitEngineDelegate` الداعم لـUIScene.
3. **عزل المفاتيح:** بصمة عنوان Backend HTTPS تحدد اسم مفتاح مختلف لكل Origin، حتى لا يكون للمشاريع المختلفة مفتاح مشترك يسمح بتتبع المستخدم. لا يوجد مسار لتصدير المفتاح الخاص.
4. **Dart:** `FableNativeDpopProofSigner` يثبت أصل HTTPS ويرفض URL مختلفًا أو Query/Fragment داخل `htu` ويرسل الطريقة والمسار والرمز إلى قناة المنصة فقط. يمنع الخطأ إعادة المحاولة بمفتاح برمجي غير محمي.
5. **التفعيل المركزي:** `UnifiedApiClient` و`FableAuthGateway` يستعملان `resolveFableDpopProofSigner` نفسه. التفعيل **متوقف افتراضيًا** ولا يتاح إلا بعقد Fable حقيقي مع تطابق بصمة العقد وعنوان Backend:
   - `--dart-define=FABLE_DPOP_NATIVE_ENABLED=true`
   - `--dart-define=FABLE_DPOP_BACKEND_CONTRACT_HASH=<64-hex>`
   - `--dart-define=FABLE_DPOP_BACKEND_ORIGIN=https://<verified-host>`
   لا تفعّل هذه القيم على Render RC155 أو باستخدام Fixture `test-project`.
6. **سلامة الشبكة:** كل HTTP attempt يوقّع إثباتًا جديدًا. بعد انتظار التوقيع الأصلي تعاد مقارنة `identityRevision` وسياق الكيان والإلغاء قبل الإرسال. يحظر إدخال `DPoP` بشكل محيط عبر `Dio` أو `Other Backend`. تتحقق جلسات `DPoP` من `tokenType` قبل تخزين رموزها.

## فحوص دون GitHub Actions

أُضيفت **7 اختبارات Flutter للناقل** بموّقع صوري للتحقق من Routing/Retry، و**6 اختبارات Flutter لقناة المنصة** لفحص تثبيت HTTPS والرمز وفشل غياب الجهاز. هذه اختبارات مكتوبة **ولم تُشغّل على Flutter SDK** في هذه البيئة.

أُضيف تدقيقان مصدران مستقلان دون Actions:

```sh
node --test tools/rc166-dpop-source-audit.mjs
node --test tools/rc166-native-dpop-source-audit.mjs
```

التحقق المباشر عبر مستودع GitHub للملفات المحدثة أعطى **29/29 نقطة مصدرية ناجحة**، منها تضمين Swift ضمن Xcode، وإعداد KeyStore، وربط قناة المنصة، واشتراط Origin والعقد، وفحص تبديل الحساب. هذا ليس تشغيلًا لأكواد Swift/Kotlin أو إثباتًا لنوعية المفتاح على جهاز فعلي.

## قيود القبول الأساسية

- **Android Emulator وiOS Simulator:** قد لا يمتلكان عتادًا آمنًا؛ الإصدار الصارم **يرفض التوقيع** ولا يرجع إلى مفتاح برمجي. يجب فحص أجهزة فعلية تدعم KeyStore hardware وSecure Enclave. فشل محاكٍ بلا عتاد متوقع، وليس اختبارًا ناجحًا للمفتاح.
- **لم يتم تجميع native bridge** باستخدام Android SDK أو Xcode، ولم يُجر `flutter analyze` أو `flutter test` أو اختبار DPoP حيّ بحسابين.
- Backend [RC165 PR #37](https://github.com/adnan118/Fable/pull/37) ما زال مسودة دون تشغيل MariaDB/Prisma كامل أو نشر. خادم Render ما زال RC155؛ خطر سرقة Bearer + Installation ID موثق في [Backend #33](https://github.com/adnan118/Fable/issues/33).
- يلزم اختبار تبديل الحسابات والجلسات، وإبطال المفتاح عند فقدان العتاد، وسلوك إعادة تثبيت التطبيق، وخطة ترحيل جلسات Bearer، وضبط `AUTH_DPOP_FLUTTER_MODE=required` على خادم مختبَر **بعد** قبول العميل والعقد الحقيقي.
- يلزم إتمام [Flutter #82](https://github.com/adnan118/Fable_flutter/issues/82): حسابان تجريبيان مؤقتان عبر HTTPS، ثبات المفتاح وتجدّد `jti`، عزل Auth وAccess وMedia، الاختبارات الحيّة على الأجهزة، وتوثيق التنظيف.

**القرار: PR #88 وPR #37 ما زالا DRAFT وغير قابلين للإعلان عن إغلاق الثغرة أو الاعتماد الإنتاجي؛ Stage 4 مستمرة، Stage 7 NO-GO.**

## مراجعة مستقلة دون Android أو Xcode — 2026-11-10

بناءً على عدم توفر Android SDK وXcode حاليًا، أُجريت مراجعة حية على مصدر PR بدل تعليق العمل. كشف التدقيق **ثلاثة أخطاء وتم إصلاحها قبل الدمج**:

1. `fable_api.dart` احتوى نسخة مكررة تالفة بعد نهاية `FableApiException`؛ أزيلت **3476 محرفًا** وأصبح الملف يحوي تعريفًا واحدًا لكل من `UnifiedApiClient` و`FableApiClient` و`FableApiException`. وجود النسخة المكررة كان سيمنع ترجمة Dart.
2. `AppDelegate` كان ينشئ `FableDpopNativeBridge` مؤقتًا بينما معالج قناة المنصة يحتفظ بـ`self` على نحو ضعيف. عولج عمر الكائن باستخدام خاصية قوية `nativeDpopBridge` في `AppDelegate`، حتى لا يتوقف استقبال طلبات التوقيع فور التسجيل.
3. طلب استرجاع مفتاح iOS الموجود في Keychain لم يكن يقيّد البحث بنوع رمز التخزين؛ صار `keyQuery` يطلب `kSecAttrTokenIDSecureEnclave` صراحةً، ولا يقبل مفتاح EC برمجيًا يحمل الوسم نفسه.

أُضيفت ثلاثة اختبارات مصدرية إلى `tools/rc166-native-dpop-source-audit.mjs` حتى لا تتكرر هذه الانحدارات. أُجريت مراجعة مباشرة بعد الإصلاح لـ**31/31 نقطة تحقق مصدرية ناجحة** عبر المستودع؛ وشُغلت حزمة Backend المستقلة عبر Node 22.16 محليًا **41/41 PASS** (بدون GitHub Actions). هذا لا يثبت تجميع Swift/Kotlin أو صلاحية إثبات صادر من الجهاز فعليًا.

لا يتغير وضع النشر: PR #88 مسودة، وBackend #37 مسودة، Render RC155 دون DPoP فعلي، وثغرة #33 ما زالت مفتوحة.

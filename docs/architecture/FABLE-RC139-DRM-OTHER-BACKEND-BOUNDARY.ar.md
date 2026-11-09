# RC139 — حدود Media بين Backend فايبل وBackend آخر

يظل اختيار Backend قرارًا مستقلًا في Wizard:
- `fable`: عقد Fable الموثق `FableContract` و`BackendSelection.canUseFableContract`. لا يسمح `FableLocalEncryptedBufferedUploader` باستخدام `media.upload` على Backend آخر حتى لو تشابه الاسم أو المسار.
- `other`: عقد OpenAPI/Custom مستقل، مع `OtherBackendVerifiedMediaTransport` الذي يدير Auth وRange ومدة الجلسة والإبطال؛ لا يفترض مسارات أو توكنات فايبل.

## خيارات تشفير الوسائط
| مستوى الخادم | استخدام Flutter |
|---|---|
| `NONE` | قراءة HTTPS خاصة بعد التفويض عبر مصدر بايتات مثبت |
| `LOCAL` | القراءة نفسها؛ Backend يفك AES-256-GCM؛ المفتاح لا يصل للتطبيق |
| `DRM` | **لا** تستخدم `MediaByteSource` الواضح. يتطلب Native/Web CDM + KSM مرخصًا، منفذًا مستقلًا، واختبارات فعلية |

حتى لو قدّم Backend الآخر `licensedDrmVerified=true`، فلن يسمح `OtherBackendProtectedMediaSource` بإرجاع bytes في الوضع `DRM`؛ الموافقة على التراخيص ليست دليلًا على أن مُشغل البايتات يدعم CDM. اعرض حالة «يتطلب مشغّل DRM متحققًا منه».

`OtherBackendProtectedMediaSource.read()` يحتفظ بقدرة قراءة ملفات الصور/المستندات بعد صلاحياتها، بينما `readChunk()` المخصص للمشغل التدريجي لا يقبل إلا MIME من نوع `audio/*` أو `video/*` ويتوقف عند اختلاف نوع المورد أو الهوية.

## رفض الالتباس
- لا تُمكّن `FableLocalEncryptedBufferedUploader` إلا مع `selectedBackend.kind='fable'`, `status='ready'`, `contractImported=true` و`FableContract` موثق.
- لا تخلط `Other` مع Session/Endpoints فايبل.
- لا تستخدم مستوى تشفير مُرسل من واجهة المستخدم لتحديد سياسة التخزين؛ الخادم هو السلطة.
- عدم اكتمال Contract أو صلاحية session أو رخصة DRM يوقف التشغيل، ولا يحوّله إلى clear fallback.

**تدقيق التنفيذ:** اختبارات Dart مُضافة، وفحص عقد Node مسجل في CI. لم تُنفذ اختبارات Flutter/Dart والأجهزة على RC139 بعد؛ لا تعتبر المحاكاة النصية اعتماد Production.

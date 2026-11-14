# RC217 — أمر pnpm واحد لجميع فحوص Fable

**تاريخ التنفيذ: 2026-11-14.** المشروع مثبت على `pnpm@12.10.1` وفق `package.json`. تمت إضافة واجهة واحدة فقط؛ الأوامر القديمة تبقى موجودة لأغراض التشخيص، لكن لا يحتاج المطوّر لتشغيلها واحدًا تلو الآخر.

## الأمر الوحيد

من مجلد `Fable_flutter`:

```sh
pnpm fable:all
```

**ماذا يفعل الأمر؟**

1. يجمع كافة ملفات اختبارات `node --test` التي كانت موزعة على سكربتات `test:*` في `package.json`، ويشغّل الملف مرة واحدة دون تكرار. يشمل اختبارات W0 وWizard وW3/W4/W5/W6/RC216 السابقة.
2. يبحث عن نسخة Backend الخاصة في `../Fable/Fable-Backend-RC66` أو مسار Backend الشقيق المعروف، ويشغّل كلا فحصَي `fable-w1-w2-one-shot.mjs --fast --json` و`--full --json`. ينفذ تدقيق مخرجات Backend إن وُجد مشروع مولّد بالفعل.
3. يشغّل بوابات W3 وW4 وW5 المتاحة من المصدر والعقود. غياب الصادرات الحقيقية يحجب اعتماد تلك الحالات؛ لا ينشئ عينة تدّعي أنها مشروع حقيقي.
4. يدقق سجل W0 الأصلي باستخدام بوابة `--strict` التي ستعيد حالة محجوبة طالما بقيت بنود الاعتماد الـ82 مفتوحة.
5. يحاول تشغيل اختبارات Auth وNotifications المستهدفة مع `flutter analyze` و`flutter test`. إذا لم يكن Flutter SDK متاحًا تظهر `BLOCKED: TOOL_NOT_INSTALLED` بدل شهادة نجاح وهمية.
6. يحفظ تقرير JSON تلقائيًا في `.fable/reports/rc217-<timestamp>.json` دون الكتابة فوق تقرير قديم، ويعرض أعداد `PASS/FAILED/BLOCKED/NOT_RUN`. يفصل فحص المصدر عن الاختبارات الحقيقية على الأجهزة.
7. لا يعتمد على GitHub Actions، ولا يطبع stdout/stderr قد يتضمن معلومات حساسة، ولا يمسح مجلدات المشروع، ولا ينفذ أي أوامر عبر `shell`. **لا يعلن production GO**.

## الربط مع مشروع حقيقي (عند توفره)

من دون إعداد إضافي ينفذ الأمر فحوص المصدر المتاحة ويُظهر بوابات العقد والإنتاج المحجوبة. ويمكن لاحقًا وضع الملف الاختياري `.fable/closeout-inputs.json` داخل Flutter **مرة واحدة**؛ سيقرأه نفس الأمر تلقائيًا في التشغيل التالي، دون إضافة وسائط أو أوامر أخرى.

مثال مفاتيح الملف (استبدل القيم بمسارات وSHA مستقلة حقيقية؛ لا تضع أسرارًا):

```json
{
  "expectedBackendSha": "<actual independently verified 40-char Backend main SHA>",
  "expectedFlutterSha": "<actual independently verified 40-char Flutter main SHA>",
  "generatedBackendRoot": "<local generated Backend project path>",
  "backendExportRoot": "<local Backend dist/client-contract path>",
  "generatedFlutterRoot": "<local generated Flutter project path>",
  "projectId": "<actual project ID>",
  "contractHash": "<64-character SHA-256>",
  "fableProfiles": {
    "minimal": {"source":"<path>","expectedProjectId":"<id>","expectedContractHash":"<sha256>"},
    "standard": {"source":"<path>","expectedProjectId":"<id>","expectedContractHash":"<sha256>"},
    "complex": {"source":"<path>","expectedProjectId":"<id>","expectedContractHash":"<sha256>"}
  }
}
```

يتم التأكد من أن مستودعي Git على `main` وبعنوان GitHub الصحيح ودون تغييرات tracked، قبل استخدام بصماتهما لإثبات مصدر W3. ويظل نجاح W3 مصدريًا لا إثباتًا مشفرًا لتاريخ إنشاء ملفات التصدير.

## دليل الحالة

- `test/rc217-pnpm-one-command.test.mjs`: 15 اختبارات Node مكتوبة، بما في ذلك اكتشاف كافة اختبارات المصدر، تشغيل Backend سريع وكامل، ومنع قبول W4/W5 أو GO بلا صادرات ودليل حقيقي.
- جرى فحص منطق تشغيل المراحل وتصنيف النتائج بفحوص V8 معزولة على كود المستودع؛ **لم يتم تشغيل `pnpm fable:all` داخل نسخة Flutter/Backend كاملة** في بيئة النموذج. اختبارات Flutter/Dart الحقيقية والـprovider E2E ما زالت تحتاج البيئة الفعلية.
- تبقى حدود W0 الأصلية `17 families / 60 gaps / 10 cross-cutting / 12 Wizard = 82 outstanding`، وحالة الإنتاج `NO_GO` حتى إغلاق أدلة المالك واعتمادها.

**ملاحظة:** كلمة `npmp` المذكورة في الطلب فُسرت بوصفها `pnpm` لأن مدير الحزم المثبت بالمشروع هو `pnpm@12.10.1`. إذا كان المقصود أداة مستقلة باسم `npmp` فلا يجوز افتراض توافقها مع مشروع يستخدم pnpm.

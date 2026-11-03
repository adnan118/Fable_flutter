# RC107 — دمج مولّد ربط العمليات المقيدة بكيان مع RC106

**قاعدة المصدر:** Flutter/main `b193407b9c6de7614bf6adbc52ead1a29709ffe0`، بعد نجاح CI ثلاثي على main.

## خلفية قرار الدمج
كان مولّد الثوابت في PR #47 مبنياً فوق RC105، بينما دُمجت بعده حماية نقل RC106 في PR #46.
أُعيد نقل ملفات التوليد إلى فرع جديد مبني من RC106 المدمج، دون استبدال ملفات
`fable_api.dart` أو `fable_auth_gateway.dart` أو تعطيل حارس السياق
قبل إرسال HTTP وعند ردود 403 المتأخرة.

## تنفيذ محدد وآمن
- `wizard:scope:generate` هو خيار منفصل، يبدأ بـPreview، ولا يكتب قبل `--apply`.
- يتطلب قرار `frontend-setup` من استيراد Backend Fable الموثق:
  `source=backend-contract-export`، `mode=import`، `projectBound=true`.
- يتطلب `projectId` و`contractHash` مقدمَين بشكل مستقل،
  والتحقق من ملفات التصدير غير التجريبية بـ`verifyFableContract(mode:project)`.
- يقرأ العمليات `managedEntityScope:true` من متطلبات الميزات المختارة فقط،
  ويتحقق من `operationId/method/path/public:false` وحظر `auth/admin/permissions/public`.
- يولّد فقط `FableManagedScopedOperation` المصدَّر من Profile. 
  لا ينشئ DTO/Repository عام، ولا يضيف Scope إلى بقية الميزات.
- يُطبّق إلغاء التفعيل المحلي على جميع تكرارات الميزة في
  `mobile-features.json` و`project-features.json`.
- لا يستبدل `managed_scoped_operations.dart` الموجود إذا اختلف محتواه:
  يلزم مراجعة الفرق ونقل الملف السابق جانباً قبل إعادة التوليد.
  إعادة التنفيذ بنفس المخرجات لا تغيّر الملف؛ ويُرفض الرابط الرمزي.

## محاكاة قابلة للتكرار
`node --test test/rc106-pinned-managed-generator.test.mjs`:
مطابقة العقد، منع العمليات العامة والمجهولة، حماية الاستيراد غير المثبت،
الاختيار المكرر/المُعطل، ملف مُعدَّل يدويًا، وSymlink.
ويختبر Flutter CI المصدر والحزم وAndroid APK وiOS Simulator على رأس PR.

## وضع الاعتماد
هذا تدقيق مصدر ومحاكاة في CI؛ ليس E2E حياً على Backend أو قاعدة البيانات
أو الأجهزة الفعلية. P6 يتطلب جلسات مستخدمين حقيقية، تنازع تبديل الكيان،
إلغاء عضوية أثناء عملية حساسة، وحماية Backend بعد استقبال الطلب.
يبقى واجب توليد DTO وربط Repository خاص بكل مشروع مرتبطاً بالعقد الفعلي،
ولا يجوز اعتبار مولّد الثوابت إغلاقاً تلقائياً لجميع P2.

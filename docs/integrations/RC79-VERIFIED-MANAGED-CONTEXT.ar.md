# RC79 — سياق الكيان المحدد عبر التطبيق

## سبب التطوير
قبل RC79 كان `FableManagedAccountsPage` يُفعّل الكيان ويؤكد الدور في Backend، لكن `FableAccountPage` يفتح الشاشة دون توصيل `onActivated`؛ الاختيار لا يصل إلى الشاشات الأخرى. إن عرض اسم الكيان فقط لا يمنح تفويضاً.

## ما أصبح متاحاً
- `FableManagedAccountSelection` يرث النوع العام `FableManagedEntitySelection` الذي يشمل المعرف والدور والاسم العربي/الإنجليزي ورقم مراجعة هوية AuthSession.
- `FableManagedEntityStore` محلي متطاير (غير محفوظ على القرص) يرتبط بمصدر Fable الموثق بواسطة `contractHash` وعنوان Backend؛ يلغي الاختيار عند تغيير مصدر العقد أو عند تسجيل الدخول/الخروج/تبديل الهوية عبر إشارة session.
- التطبيق يغلّف الشاشات في `FableManagedEntityScope` فقط عندما يكون Backend المختار Fable وله عقد متحقق. المشروع الذي اختار `other` لا يرث سياق Fable، ووجود Core لا يثبت أن ميزة Managed Accounts متاحة.
- `FableAccountPage` يعرض الاختيار الذي أكده Backend ويقدم إزالة صريحة للسياق المحلي، ويمرر `onActivated/onCleared` لواجهة إدارة الكيانات. تغيير كيان، تعديل خصوصية/تعاون، أو عملية Lifecycle مؤكدة تلغي الاختيار الحالي.

## حد الأمان (مهم)
هذا **سياق قراءة UI**. لا يضيف أي HTTP interceptor عاماً ولا يضع `X-Fable-Managed-Entity-Id` في طلبات Profile/Auth/Payments/Public/External. كل ميزة مشروع تتطلب سياق الكيان عليها استعمال `FableManagedAccountsRepository.executeInContext` أو مكافئ موثق **بالعملية نفسها** وبعد إعادة التحقق من الصلاحيات، ومع إبطال الكاش والصلاحيات عند تبدّل الكيان. اختيار الواجهة لا يمنح صلاحية ولا يثبت الوصول إلى بيانات الكيان.

لا تُعتبر إدارة الكيانات متعددة الحسابات مكتملة قبل اعتماد E2E مع مستخدمين وكيانات متعددة، اختبار رفض العضوية الملغاة، وتحقق خادم Fable لكل طلب مسموح. الاستمرار لاحقاً: تأمين Context Gate على كل عملية مشروع تحتاجه ونقل الـWizard بحسب العمليات الفعلية بدلاً من تعميم رأس Fable.

## الفحوص
- وحدة Core: عقد Fable المطلوب، تحقق UUID/OWNER/MANAGER/VIEWER، إبطال الهوية والسياق عند تغير المصدر، تفاعل InheritedNotifier مع Flutter Widgets.
- وحدة source: تغيير الكيان يخرج من Profile إلى App وغياب global header/استيراد Profile في Core يضمن ألا يكسر إزالة Profile ضمن Wizard.
- Flutter Analyze وFeature tests وبناء Android/iOS ضمن PR.

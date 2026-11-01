# دليل تعليمي عملي: Flutter + BLoC مع Fable أو Backend آخر

> **هذا الدليل لفهم كود المشروع وتطويره بأمان، وليس إعلاناً أن جميع حزم المشروع تستخدم BLoC حالياً.**
> مرجع التكامل الأساسي: [السجل الرئيسي للمطابقة](./FABLE-FLUTTER-PARITY-MASTER.ar.md).

## 1) افهم البنية أولاً

```text
Page / Widget
  ├── BlocBuilder / BlocListener   ← العرض والتفاعل (إن استعملنا flutter_bloc)
  ├── Cubit / Bloc                 ← حالة التحميل، الصلاحيات، الخطأ، الإلغاء
  └── Repository                   ← الدالة التي تفهم Domain
        └── Gateway               ← HTTP + عقد العمليات + جلسة + حماية النقل
              └── Fable Backend أو External Backend (كل واحد بعقده)
```

- `Widget` مسؤول عن العرض وإرسال حدث UI؛ لا يقرر صلاحية جديدة من تلقاء نفسه.
- `Model` يمثّل البيانات والعقد بدقة: أنواع، nullability، حقول غير معروفة، تحقق.
- `Repository` يعرف معنى العملية (مثلاً `inviteMember`) ويستخدم **العملية الموثقة**؛ لا ينفذ POST إلى Path اخترعناه.
- `Cubit`: مناسب لتسلسل بسيط مثل تحميل قائمة. `Bloc`: مناسب إذا كثرت الأحداث المتنافسة (بحث، تحديث، تغيير حساب، جلسات، رد متأخر).
- `BlocBuilder` يبني UI عند تغير State؛ `BlocListener` للتنقل وSnackbar والآثار الجانبية؛ `BlocSelector` لمنع إعادة رسم غير ضرورية.
- **اختيار Backend يسبق إنشاء Repository**: Fable يأخذ `FableContract`؛ الآخر يأخذ `ExternalOperationCatalog` وBindings الخاصة به. لا تخضع الشاشتان لمسار HTTP واحد بالتخمين.

## 2) مثال تعليمي (غير مضاف إلى الإنتاج)

المثال التالي يوضح تسلسل حالة فقط؛ `flutter_bloc` يجب أن يكون Dependency في المشروع إذا قررنا استخدامه في تلك الميزة. لا يفترض وجود API باسم `/my-entities`.

```dart
import 'package:flutter_bloc/flutter_bloc.dart';

// الحالة ثابتة ومعروفة، ولا نستخدم bool واحداً لتمثيل كل شيء.
sealed class EntitiesState {
  const EntitiesState();
}
class EntitiesInitial extends EntitiesState { const EntitiesInitial(); }
class EntitiesLoading extends EntitiesState { const EntitiesLoading(); }
class EntitiesReady extends EntitiesState {
  const EntitiesReady(this.names);
  final List<String> names;
}
class EntitiesDenied extends EntitiesState { const EntitiesDenied(); }
class EntitiesFailure extends EntitiesState {
  const EntitiesFailure(this.message);
  final String message;
}

abstract interface class EntitiesRepository {
  // العملية الحقيقية تأتي من العقد المستورد وليس من عنوان ثابت.
  Future<List<String>> listNames();
}

class EntitiesCubit extends Cubit<EntitiesState> {
  EntitiesCubit(this.repository) : super(const EntitiesInitial());
  final EntitiesRepository repository;
  int _requestRevision = 0;

  Future<void> load() async {
    final revision = ++_requestRevision;
    emit(const EntitiesLoading());
    try {
      final names = await repository.listNames();
      // بعد تبديل الحساب لا يجوز إعادة بيانات المستخدم القديم للواجهة.
      if (isClosed || revision != _requestRevision) return;
      emit(EntitiesReady(List<String>.unmodifiable(names)));
    } catch (_) {
      if (isClosed || revision != _requestRevision) return;
      emit(const EntitiesFailure('تعذّر التحميل؛ راجع الجلسة والصلاحيات'));
    }
  }

  void clearForIdentitySwitch() {
    ++_requestRevision; // إبطال نتائج الطلبات القديمة.
    emit(const EntitiesInitial());
  }
}
```

**لماذا هذا المثال غير كافٍ للإنتاج؟** لأن تبديل الحساب يحتاج إشارة من SecureSession موثقة وربط النتيجة بـ`identityRevision`، ولأن الصلاحيات `403` وسياق Managed Entity والعقد الحقيقي يجب فحصها قبل أي Network Call. لا تستخدم `Cubit` لعزل أمان الشبكة بدلاً من Backend.

## 3) أين أجد أمثلة من الكود الحالي؟

| ما تريد تعلمه | ابدأ من | الفكرة |
|---|---|---|
| Flutter StatefulWidget + async | `packages/features/fable_profile/lib/src/managed_accounts_page.dart` | دورة تحميل/إنشاء ودعوات و`mounted` وتبديل الجلسة |
| Repository + DTO | `packages/features/fable_profile/lib/src/managed_accounts_repository.dart` | Contract-gating، تحقق UUID، رفض الدور المزور والرد غير المطابق |
| اختيار Backend | `lib/src/app.dart` و`tools/flutter-setup-wizard.mjs` | شرط الفصل Fable/Other، تفعيل الشاشات فقط عند وجود عقد |
| صلاحيات المستخدم | `packages/features/fable_access_control/lib/src/access_session.dart` | إبطال Grants بعد Logout وتغير الإذن و403 |
| تنظيم حالة لغة واجهة | `packages/fable_core/lib/src/fable_locale_preference.dart` | حفظ تغييرات UI دون تنازع writes |
| الجلسة وهويتها | `packages/fable_core/lib/src/fable_session.dart` | `identityRevision`، Lock للكتابة، تجاهل الطلب القديم |

## 4) خريطة تعلم تدريجية

1. **Flutter:** Lifecycle و`StatefulWidget` و`initState/dispose` و`mounted` و`FutureBuilder`.
2. **Dart:** `Future` و`Stream` و`sealed class` وNull safety و`async/await`.
3. **Cubit:** `emit` وImmutable State وLoading/Success/Error/Denied/Empty.
4. **BLoC:** Events/Handlers و`BlocProvider/BlocBuilder/BlocListener` واختبار ترتيب الأحداث.
5. **Repository:** حقن Gateway mock بالاختبارات وعدم وضع HTTP داخل Widget.
6. **أمان المشروع:** انقطاع الإنترنت، Session refresh، تبديل المستخدم، 401/403/409/429، صلاحيات وEntityScope، وعدم تكرار POST حساس.
7. **Other Backend:** Mapping من OpenAPI/Custom، نجاح الاختبارات نفسها مع مسارات مختلفة من دون نقل عناوين Fable.

روابط مفيدة:
- [الموقع الرسمي لمكتبة BLoC](https://bloclibrary.dev/)
- [حزمة flutter_bloc على pub.dev](https://pub.dev/packages/flutter_bloc)
- [توثيق Flutter لإدارة الحالة](https://docs.flutter.dev/data-and-backend/state-mgmt/intro)
- [Dart asynchronous programming](https://dart.dev/libraries/async/async-await)
- [توثيق الاختبار في Flutter](https://docs.flutter.dev/testing/overview)

## 5) سياسة التعليقات بالعربية

- في **كل شيفرة جديدة** فيها قرار أمني أو تعاقدي، ضع تعليقاً عربياً قصيراً يشرح **لماذا**؛ لا تكرر حرفياً ما يفعله السطر.
- إذا كان التفصيل كبيراً، يكفي رابط نسبي لهذا الدليل أو للسجل الرئيسي داخل تعليق `///`.
- أسماء الدوال والمتغيرات و`operationId` تبقى English ومرتبطة بالعقد؛ التعليق والشرح عربيان.
- مثال:
```dart
// لا نسمح باستمرار الطلب إذا تغير المستخدم أثناء انتظار Backend.
// المرجع: docs/integrations/FABLE-FLUTTER-PARITY-MASTER.ar.md
if (revision != session.identityRevision) return;
```
- اجعل `bloc_test` أو `flutter_test` يتحقق من الحالة الأمنية، وليس فقط نص زر «تسجيل الدخول».
- لا نضيف BLoC أو Drift أو Firebase إلى الحزمة بلا حاجة مثبّتة في إعداد Wizard والعقد المنسوب إليها.

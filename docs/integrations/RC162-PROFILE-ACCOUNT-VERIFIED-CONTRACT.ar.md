# RC162 — المرحلة الرابعة: مطابقة Profile مع حساب Auth الأساسي في Fable

**التاريخ:** 10 نوفمبر 2026. **النطاق:** عرض حساب Flutter الأساسي وتحديث الاسم الظاهر، لا إنشاء ملف شخصي Domain جديد.

## المشكلة المكتشفة

كانت واجهة `FableProfileFeature.canLaunchFable` تسمح بظهور Profile إذا وجدت عملية `account.me` من نوع GET وموسومة بالمصادقة، لكنها لم تتحقق من مسارها ولا بصمة عقد العملية أو تفعيل الحماية. كذلك كانت شاشة `FableAccountPage` تتحقق من وجود معرف العملية فقط، وتُظهر زر حفظ الاسم إذا وُجد `account.displayName.update` دون التأكد من طريقة PATCH ومسارها الصحيح.

تتيح هذه الحالة ربط واجهة تعرض بيانات حساب حساسة بعملية غير مقصودة على الخادم إذا تغيّر أو استُورد عقد غير مطابق. التصريح الحقيقي النهائي يبقى بيد Backend، لكن Flutter يجب أن يرفض العقد غير المتطابق.

## مصدر الحقيقة

في Backend `Fable-Backend-RC66/src/platform/auth/auth.controller.ts`:
- `GET /auth/me/account` — بيانات الحساب الأساسية فقط.
- `PATCH /auth/me/account` — تحديث حقل `displayName` فقط، وليس البريد أو الهاتف أو الدور أو إعدادات الأمن.

ويظهر العمليتان نفسهُما في ملف `assets/contracts/mobile-core-operations.json` ضمن مشروع Flutter.

## RC162

أضفنا `FableProfileAccountRoutePolicy` في حزمة Profile وربطناه مع:
- `FableProfileFeature.canLaunchFable`: لا يُظهر الميزة قبل التحقق من تفعيل `profile` ومن GET `account.me` المطابق.
- `FableAccountPage._supported`: لا يحمّل البيانات إذا كان العقد غير موثوق أو مُعطّلًا أو عنوان API غير محدد.
- زر وتطبيق تعديل الاسم الظاهر: `_canUpdateDisplayName` يشترط PATCH الصحيح والمصادقة الصارمة؛ إذا كانت عملية PATCH مفقودة أو خاطئة، يبقى **الحساب للقراءة فقط** إذا صح GET.

العقد يجب أن يقدّم `requiresAuth=true`، و`enforceAuth=true`، وعدم استخدام Header اعتماد بديل غير مصرح، وبصمة SHA-256 صالحة. لا يُستنتج تفعيل Profile من وجود حزمة Flutter وحدها. **Other Backend** يستخدم الاستيراد والربط المستقل ولا يرث مسارات Fable.

## الاختبارات والحدود

`rc162_profile_account_verified_routes_test.dart` يغطي خمس مجموعات: GET/PATCH الحقيقيين، مسارات خاطئة أو أساليب غير صحيحة، بيانات مصادقة ضعيفة أو بصمة غير صالحة، تعطيل الميزة من Backend أو حذف السياسة، وحالة قراءة الحساب دون السماح بتعديل غير موثق.

**هذه اختبارات مصدر وحزمة Flutter** ولا تُثبت بعد تشغيل مستخدم مصادق عليه من Android/iOS عبر HTTPS أو سياسة الحذف المادي أو إغلاق #82. لا نغيّر قواعد الصلاحيات في الخادم أو نمنح دورًا أو ننشئ بيانات اعتماد. تبقى المخاطر المفتوحة: [Backend #33](https://github.com/adnan118/Fable/issues/33)، [Backend Support #35](https://github.com/adnan118/Fable/issues/35)، تكامل [Flutter #82](https://github.com/adnan118/Fable_flutter/issues/82)، وStage 7 **NO-GO**.

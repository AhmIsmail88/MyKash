# ترقية قاعدة البيانات (Schema Migrations)

قاعدة البيانات بتتطور مع كل مرحلة (وردية، دفع مقسّم، طاولات…). القاعدة الذهبية:
**مفيش فقدان بيانات لأي عميل قديم.**

## الملفات المرجعية

| المسار | إيه هو |
|---|---|
| `drift_schemas/drift_schema_vN.json` | نسخة مجمّدة من السكيما عند الإصدار N |
| `test/generated/schema.dart` | أدوات drift لاختبار الترقيات |
| `test/migration_test.dart` | الاختبارات اللي بتحمي الترقية |

## خطوات أي تعديل على السكيما

1. عدّل الجداول في `lib/data/database.dart`.
2. **ارفع** `AppDatabase.currentSchema` (مثلاً 4 → 5).
3. أضف خطوة **إضافية فقط** داخل `onUpgrade`:
   ```dart
   if (from < 5) {
     await m.createTable(shifts);          // جدول جديد
     // أو: await m.addColumn(items, items.variants);
   }
   ```
   ❌ ممنوع حذف خطوة قديمة، أو `dropTable`، أو تعديل عمود موجود.
4. أعد توليد الكود:
   ```bash
   dart run build_runner build --delete-conflicting-outputs
   ```
5. جمّد السكيما الجديدة:
   ```bash
   dart run drift_dev schema dump lib/data/database.dart drift_schemas/
   dart run drift_dev schema generate drift_schemas/ test/generated/
   ```
6. حدّث `currentSchemaForTests` في `test/migration_test.dart` وأضف اختبار ترقية:
   ```dart
   test('upgrade from 4 to 5', () async {
     final connection = await verifier.startAt(4);
     final db = AppDatabase.forTesting(connection);
     await verifier.migrateAndValidate(db, 5);
   });
   ```
7. `flutter test` — لازم يعدّي كله.

## ملاحظة صادقة عن التاريخ

النسخ 1→3 اتعملت **قبل** تفعيل تتبّع السكيما، فمفيش نسخ مجمّدة لها.
يعني اختبار الترقية الحقيقي (4→5، 5→6…) يبدأ من أول تعديل جاي.
للي فات: الاختبارات الحالية بتتحقق إن الترقية تنتج السكيما المعلنة بالظبط،
وإن البيانات بتفضل موجودة بعد الفتح والإغلاق.

## الإعدادات مش محتاجة migration

`shop_settings` جدول key/value. أي إعداد جديد (`business_type`، `vat_rate`،
`enable_tables` …) يتحفظ فيه **بدون أي تغيير في السكيما**. استخدمه دايماً
قبل ما تفكر تضيف عمود.
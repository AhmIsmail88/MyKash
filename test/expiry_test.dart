import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykash/data/database.dart';

void main() {
  group('daysUntil', () {
    const day = 86400000;

    test('counts whole days rounding up', () {
      expect(daysUntil(1000 + day, 1000), 1);
      expect(daysUntil(1000 + day ~/ 2, 1000), 1);
      expect(daysUntil(1000, 1000), 0);
    });

    test('is negative for dates in the past', () {
      expect(daysUntil(1000 - day, 1000), -1);
      expect(daysUntil(1000 - 3 * day, 1000), -3);
    });
  });

  group('expiringItems', () {
    late AppDatabase db;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      await db.initDevice(isMobile: false);
    });

    tearDown(() async => db.close());

    test('lists a batch that expires inside the window', () async {
      final soon = nowMs() + 5 * 86400000;
      await db.addItem(
          name: 'Milk',
          salePrice: 1500,
          openingQtyMilli: 3000,
          expiryDate: soon);

      final rows = await db.expiringItems(withinDays: 30);
      expect(rows.length, 1);
      expect(rows.single.name, 'Milk');
      expect(rows.single.expiryDate, soon);
      expect(rows.single.stockMilli, 3000);
      expect(rows.single.daysLeft(), 5);
    });

    test('ignores batches outside the window', () async {
      await db.addItem(
          name: 'Canned',
          salePrice: 1000,
          openingQtyMilli: 1000,
          expiryDate: nowMs() + 200 * 86400000);
      expect(await db.expiringItems(withinDays: 30), isEmpty);
    });

    test('ignores items without an expiry date', () async {
      await db.addItem(name: 'Soap', salePrice: 1000, openingQtyMilli: 1000);
      expect(await db.expiringItems(), isEmpty);
    });

    test('ignores items whose stock ran out', () async {
      await db.addItem(
          name: 'Yogurt',
          salePrice: 1000,
          openingQtyMilli: 1000,
          expiryDate: nowMs() + 3 * 86400000);
      final item = (await db.watchItems('').first)
          .firstWhere((i) => i.name == 'Yogurt');
      await db.adjustStockTo(item.id, 0);
      expect(await db.expiringItems(), isEmpty);
    });

    test('an expiry automatically flags the item as tracked', () async {
      await db.addItem(
          name: 'Cheese',
          salePrice: 2000,
          openingQtyMilli: 500,
          expiryDate: nowMs() + 10 * 86400000);
      final row = await (db.select(db.items)
            ..where((t) => t.name.equals('Cheese')))
          .getSingle();
      expect(row.trackExpiry, isTrue);
    });
  });
}
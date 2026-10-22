import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykash/data/database.dart';

void main() {
  group('resolveTierPriceMs', () {
    test('returns null when there are no tiers', () {
      expect(resolveTierPriceMs(const <PriceTierInput>[], 5000), isNull);
    });

    test('returns null below the smallest threshold', () {
      const tiers = <PriceTierInput>[
        PriceTierInput(minQtyMilli: 5000, unitPrice: 2200),
      ];
      expect(resolveTierPriceMs(tiers, 1000), isNull);
    });

    test('picks the highest threshold not above the quantity', () {
      const tiers = <PriceTierInput>[
        PriceTierInput(minQtyMilli: 1000, unitPrice: 2500),
        PriceTierInput(minQtyMilli: 5000, unitPrice: 2300),
        PriceTierInput(minQtyMilli: 20000, unitPrice: 2100),
      ];
      expect(resolveTierPriceMs(tiers, 1000), 2500);
      expect(resolveTierPriceMs(tiers, 4999), 2500);
      expect(resolveTierPriceMs(tiers, 5000), 2300);
      expect(resolveTierPriceMs(tiers, 8000), 2300);
      expect(resolveTierPriceMs(tiers, 20000), 2100);
      expect(resolveTierPriceMs(tiers, 99999), 2100);
    });
  });

  group('tier storage', () {
    late AppDatabase db;
    late String unitId;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      await db.initDevice(isMobile: false);
      await db.addItem(name: 'Feed', salePrice: 3000, openingQtyMilli: 100000);
      final item = (await db.watchItems('').first).first;
      final units = await db.unitsOf(item.id);
      unitId = units.first.id;
    });

    tearDown(() async => db.close());

    test('saves and reads tiers ordered by quantity', () async {
      await db.saveTiersForUnit(unitId, const <PriceTierInput>[
        PriceTierInput(minQtyMilli: 20000, unitPrice: 2100, label: 'كميات'),
        PriceTierInput(minQtyMilli: 1000, unitPrice: 2500, label: 'تجزئة'),
      ]);
      final rows = await db.tiersForUnit(unitId);
      expect(rows.map((r) => r.minQtyMilli).toList(), <int>[1000, 20000]);
      expect(rows.first.unitPrice, 2500);
    });

    test('saving again replaces the previous tiers', () async {
      await db.saveTiersForUnit(unitId, const <PriceTierInput>[
        PriceTierInput(minQtyMilli: 1000, unitPrice: 2500),
      ]);
      await db.saveTiersForUnit(unitId, const <PriceTierInput>[
        PriceTierInput(minQtyMilli: 5000, unitPrice: 2300),
      ]);
      final rows = await db.tiersForUnit(unitId);
      expect(rows.length, 1);
      expect(rows.single.minQtyMilli, 5000);
    });

    test('ignores zero or negative rows', () async {
      await db.saveTiersForUnit(unitId, const <PriceTierInput>[
        PriceTierInput(minQtyMilli: 0, unitPrice: 2500),
        PriceTierInput(minQtyMilli: 1000, unitPrice: 0),
        PriceTierInput(minQtyMilli: 2000, unitPrice: 2400),
      ]);
      final rows = await db.tiersForUnit(unitId);
      expect(rows.length, 1);
      expect(rows.single.minQtyMilli, 2000);
    });

    test('priceForUnit resolves through the stored tiers', () async {
      await db.saveTiersForUnit(unitId, const <PriceTierInput>[
        PriceTierInput(minQtyMilli: 5000, unitPrice: 2300),
      ]);
      expect(await db.priceForUnit(unitId, 1000), isNull);
      expect(await db.priceForUnit(unitId, 5000), 2300);
      expect(await db.priceForUnit(unitId, 12000), 2300);
    });
  });
}
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykash/data/database.dart';

void main() {
  late AppDatabase db;
  late String itemId;
  late String adminId;
  late String cashierId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.initDevice(isMobile: false);
    adminId = (await db.createUser(name: 'A', role: 'admin', pin: '1111')).id;
    cashierId = (await db.createUser(name: 'C', role: 'cashier', pin: '2222')).id;
    await db.addItem(name: 'Item', salePrice: 10000, openingQtyMilli: 100000);
    itemId =
        (await db.watchItems('').first).firstWhere((i) => i.name == 'Item').id;
  });

  tearDown(() async => db.close());

  Future<({String id, String number})> sell({
    required String? userId,
    int discount = 0,
  }) =>
      db.completeSale(
        lines: [
          SaleLineInput(itemId: itemId, qtyMilli: 1000, unitPrice: 10000),
        ],
        credit: false,
        discount: discount,
        userId: userId,
      );

  group('discount cap', () {
    test('a cashier cannot exceed the configured cap', () async {
      await db.setSetting('max_discount_percent', '5');
      await expectLater(
        sell(userId: cashierId, discount: 1000), // 10%
        throwsA(isA<StateError>()),
      );
    });

    test('a cashier may discount exactly up to the cap', () async {
      await db.setSetting('max_discount_percent', '5');
      final sale = await sell(userId: cashierId, discount: 500); // 5%
      final row =
          await (db.select(db.sales)..where((s) => s.id.equals(sale.id)))
              .getSingle();
      expect(row.discount, 500);
    });

    test('an admin has no cap', () async {
      await db.setSetting('max_discount_percent', '5');
      final sale = await sell(userId: adminId, discount: 5000); // 50%
      final row =
          await (db.select(db.sales)..where((s) => s.id.equals(sale.id)))
              .getSingle();
      expect(row.discount, 5000);
    });

    test('an unknown user id skips the check (legacy path)', () async {
      await db.setSetting('max_discount_percent', '5');
      final sale = await sell(userId: null, discount: 5000);
      expect(sale.number, isNotEmpty);
    });

    test('a cashier with no cap configured cannot discount at all', () async {
      await expectLater(
        sell(userId: cashierId, discount: 100),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('voiding', () {
    test('a cashier cannot cancel when voiding is locked', () async {
      await db.setSetting('allow_void', '0');
      final sale = await sell(userId: cashierId);
      await expectLater(
        db.cancelSale(sale.id, userId: cashierId),
        throwsA(isA<StateError>()),
      );
      final row =
          await (db.select(db.sales)..where((s) => s.id.equals(sale.id)))
              .getSingle();
      expect(row.status, 'completed');
    });

    test('a cashier can cancel when voiding is allowed', () async {
      await db.setSetting('allow_void', '1');
      final sale = await sell(userId: cashierId);
      await db.cancelSale(sale.id, userId: cashierId);
      final row =
          await (db.select(db.sales)..where((s) => s.id.equals(sale.id)))
              .getSingle();
      expect(row.status, 'cancelled');
    });

    test('an admin can cancel even when voiding is locked', () async {
      await db.setSetting('allow_void', '0');
      final sale = await sell(userId: cashierId);
      await db.cancelSale(sale.id, userId: adminId);
      final row =
          await (db.select(db.sales)..where((s) => s.id.equals(sale.id)))
              .getSingle();
      expect(row.status, 'cancelled');
    });
  });
}
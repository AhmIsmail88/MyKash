import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykash/data/database.dart';

void main() {
  late AppDatabase db;
  late String userId;
  late String milk;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.initDevice(isMobile: false);
    final admin = await db.createUser(name: 'Admin', role: 'admin', pin: '1234');
    userId = admin.id;
    await db.addItem(
        name: 'Milk', salePrice: 1500, costPrice: 1000, openingQtyMilli: 5000);
    milk = (await db.watchItems('').first)
        .firstWhere((i) => i.name == 'Milk')
        .id;
  });

  tearDown(() async => db.close());

  Future<({String id, String number})> cashSale(int qty) => db.completeSale(
        lines: [
          SaleLineInput(itemId: milk, qtyMilli: qty, unitPrice: 1500, unitCost: 1000),
        ],
        credit: false,
        userId: userId,
      );

  test('openShift numbers the first shift S-0001 and makes it current', () async {
    final shift = await db.openShift(userId: userId, openingCash: 10000);
    expect(shift.number, 'S-0001');
    expect(shift.status, 'open');
    expect(shift.openingCash, 10000);
    expect((await db.currentShift())?.id, shift.id);
  });

  test('a second shift cannot be opened while one is open', () async {
    final first = await db.openShift(userId: userId, openingCash: 10000);
    await expectLater(
      db.openShift(userId: userId, openingCash: 5000),
      throwsA(isA<StateError>()),
    );
    final current = await db.currentShift();
    expect(current?.id, first.id);
    expect(current?.openingCash, 10000);
  });

  test('sales are attached to the open shift and summarised', () async {
    final shift = await db.openShift(userId: userId, openingCash: 10000);

    await cashSale(2000); // 3000 cash

    final customer = await db.addCustomer(name: 'C1', creditLimit: 100000);
    await db.completeSale(
      lines: [
        SaleLineInput(itemId: milk, qtyMilli: 1000, unitPrice: 1500, unitCost: 1000),
      ],
      credit: true,
      customerId: customer,
      paidNow: 500,
      userId: userId,
    );

    final summary = await db.shiftSummary(shift.id);
    expect(summary.salesCount, 2);
    expect(summary.cashSales, 3000);
    expect(summary.creditSales, 1500);
    expect(summary.cashReturns, 0);
    expect(summary.cashFromSales, 3500); // 3000 كاش + 500 مقدم الآجل
    expect(summary.cashPaymentsIn, 0); // المدفوعات المرتبطة بفاتورة بتتحسب في cashFromSales
    expect(summary.cashPaymentsOut, 0);
    expect(summary.expectedCash, 13500); // 10000 + 3000 + 500

    final rows = await db.watchShiftSales(shift.id).first;
    expect(rows.length, 2);
  });

  test('closeShift computes expected and difference, and refuses a second close',
      () async {
    final shift = await db.openShift(userId: userId, openingCash: 10000);
    final sale = await cashSale(2000); // 3000

    final lines = await db.saleLinesFor(sale.id);
    final refund = await db.returnItems(sale.id, {lines.first.lineId: 500});
    expect(refund, 750);

    final closed = await db.closeShift(shiftId: shift.id, countedCash: 12000);
    expect(closed.expectedCash, 12250); // 10000 + 3000 - 750
    expect(closed.shift.countedCash, 12000);
    expect(closed.shift.expectedCash, 12250);
    expect(closed.shift.difference, -250);
    expect(closed.difference, -250);
    expect(closed.shift.status, 'closed');
    expect(closed.shift.closedAt, isNotNull);

    await expectLater(
      db.closeShift(shiftId: shift.id, countedCash: 1),
      throwsA(isA<StateError>()),
    );
    expect(await db.currentShift(), isNull);
  });

  test('a sale after closing the shift is not attached to it', () async {
    final shift = await db.openShift(userId: userId, openingCash: 0);
    await db.closeShift(shiftId: shift.id, countedCash: 0);

    final after = await cashSale(1000);
    final rows = await db.watchShiftSales(shift.id).first;
    expect(rows.map((r) => r.id), isNot(contains(after.id)));
  });

  test('sales before any shift have no shift attached', () async {
    final before = await cashSale(1000);
    final shift = await db.openShift(userId: userId, openingCash: 0);
    final rows = await db.watchShiftSales(shift.id).first;
    expect(rows.map((r) => r.id), isNot(contains(before.id)));
  });
}
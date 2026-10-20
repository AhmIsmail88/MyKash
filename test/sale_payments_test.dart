import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykash/data/database.dart';

void main() {
  late AppDatabase db;
  late String milk;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.initDevice(isMobile: false);
    await db.addItem(
        name: 'Milk', salePrice: 1500, costPrice: 1000, openingQtyMilli: 10000);
    milk = (await db.watchItems('').first)
        .firstWhere((i) => i.name == 'Milk')
        .id;
  });

  tearDown(() async => db.close());

  Future<List<SalePayment>> rowsFor(String saleId) => (db.select(db.salePayments)
        ..where((t) => t.saleId.equals(saleId)))
      .get();

  test('a plain cash sale records one cash payment row for the full total',
      () async {
    final sale = await db.completeSale(
      lines: [
        SaleLineInput(itemId: milk, qtyMilli: 2000, unitPrice: 1500, unitCost: 1000),
      ],
      credit: false,
    );

    final rows = await rowsFor(sale.id);
    expect(rows.length, 1);
    expect(rows.single.method, 'cash');
    expect(rows.single.amount, 3000);
  });

  test('a split payment records each method separately', () async {
    final sale = await db.completeSale(
      lines: [
        SaleLineInput(itemId: milk, qtyMilli: 800, unitPrice: 1500, unitCost: 1000),
      ],
      credit: false,
      paymentSplits: const [
        SalePaymentInput(method: 'cash', amount: 500),
        SalePaymentInput(method: 'card', amount: 700),
      ],
    );

    final rows = await rowsFor(sale.id);
    expect(rows.length, 2);
    expect(rows.map((r) => r.method).toSet(), {'cash', 'card'});
    expect(rows.fold<int>(0, (s, r) => s + r.amount), 1200);

    final stored = await (db.select(db.sales)..where((s) => s.id.equals(sale.id)))
        .getSingle();
    expect(stored.total, 1200);
    expect(stored.paid, 1200);
  });

  test('the drawer only counts the cash part of a split sale', () async {
    final shift = await db.openShift(userId: 'u1', openingCash: 0);
    await db.completeSale(
      lines: [
        SaleLineInput(itemId: milk, qtyMilli: 800, unitPrice: 1500, unitCost: 1000),
      ],
      credit: false,
      paymentSplits: const [
        SalePaymentInput(method: 'cash', amount: 500),
        SalePaymentInput(method: 'card', amount: 700),
      ],
    );

    final summary = await db.shiftSummary(shift.id);
    expect(summary.cashSales, 1200); // إجمالي الفاتورة كاش
    expect(summary.cashFromSales, 500); // اللي دخل الدرج فعلًا
    expect(summary.expectedCash, 500);
  });

  test('a credit sale counts only the up-front cash', () async {
    final shift = await db.openShift(userId: 'u1', openingCash: 1000);
    final customer = await db.addCustomer(name: 'C', creditLimit: 100000);
    await db.completeSale(
      lines: [
        SaleLineInput(itemId: milk, qtyMilli: 2000, unitPrice: 1500, unitCost: 1000),
      ],
      credit: true,
      customerId: customer,
      paidNow: 1000,
    );

    final summary = await db.shiftSummary(shift.id);
    expect(summary.cashFromSales, 1000);
    expect(summary.cashPaymentsIn, 0); // ممنوع العدّ المزدوج
    expect(summary.expectedCash, 2000);
  });

  test('legacy sales without payment rows fall back to the sale amount',
      () async {
    final shift = await db.openShift(userId: 'u1', openingCash: 0);
    final sale = await db.completeSale(
      lines: [
        SaleLineInput(itemId: milk, qtyMilli: 1000, unitPrice: 1500, unitCost: 1000),
      ],
      credit: false,
    );

    // Simulation of a sale created before sale_payments existed.
    await (db.delete(db.salePayments)..where((t) => t.saleId.equals(sale.id))).go();

    final summary = await db.shiftSummary(shift.id);
    expect(summary.cashFromSales, 1500);
    expect(summary.expectedCash, 1500);
  });
}
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykash/data/database.dart';

/// Full business cycle on an isolated in-memory database.
///
/// Uses the real AppDatabase, real transactions and the real SQL, so it
/// exercises the same code the shop runs - only the storage is throwaway.
void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.initDevice(isMobile: false);
    await db.setSetting('shop_name', 'Demo Shop');
  });

  tearDown(() async {
    await db.close();
  });

  Future<String> itemIdByName(String name) async {
    final rows = await db.watchItems('').first;
    return rows.firstWhere((r) => r.name == name).id;
  }

  Future<int> stockOfName(String name) async =>
      db.stockOf(await itemIdByName(name));

  test('complete shop cycle', () async {
    // ---------- users ----------
    final admin = await db.createUser(name: 'Admin', role: 'admin', pin: '1234');
    expect(await db.verifyPin(admin.id, '1234'), isNotNull);
    expect(await db.verifyPin(admin.id, '9999'), isNull);
    expect(await db.hasUsers(), isTrue);

    // ---------- items ----------
    await db.addItem(
        name: 'Tea', salePrice: 2500, costPrice: 1800, openingQtyMilli: 10000, barcode: '1001');
    await db.addItem(
        name: 'Sugar', salePrice: 3000, costPrice: 2000, openingQtyMilli: 5000, barcode: '1002');
    await db.addItem(
        name: 'Milk', salePrice: 1500, costPrice: 1000, openingQtyMilli: 2000);

    expect((await db.watchItems('').first).length, 3);
    expect(await stockOfName('Tea'), 10000);
    expect((await db.itemByBarcode('1001'))?.name, 'Tea');

    final tea = await itemIdByName('Tea');
    final sugar = await itemIdByName('Sugar');
    final milk = await itemIdByName('Milk');

    // ---------- cash sale ----------
    final sale1 = await db.completeSale(
      lines: [
        SaleLineInput(itemId: tea, qtyMilli: 2000, unitPrice: 2500, unitCost: 1800),
        SaleLineInput(itemId: sugar, qtyMilli: 1000, unitPrice: 3000, unitCost: 2000),
      ],
      credit: false,
      discount: 500,
      userId: admin.id,
    );
    expect(sale1.number, 'D-0001');
    expect(await stockOfName('Tea'), 8000);
    expect(await stockOfName('Sugar'), 4000);

    // ---------- credit sale ----------
    final customer = await db.addCustomer(name: 'Customer A', creditLimit: 100000);
    final sale2 = await db.completeSale(
      lines: [
        SaleLineInput(itemId: milk, qtyMilli: 1000, unitPrice: 1500, unitCost: 1000),
      ],
      credit: true,
      customerId: customer,
      paidNow: 500,
      userId: admin.id,
    );
    expect(sale2.number, 'D-0002');
    expect(await stockOfName('Milk'), 1000);

    final custRow = (await db.watchCustomers().first)
        .firstWhere((c) => c.id == customer);
    expect(custRow.balance, 1000); // 1500 - 500
    expect(await db.receivablesTotal(), 1000);

    // ---------- return half a unit ----------
    final lines2 = await db.saleLinesFor(sale2.id);
    final refund = await db.returnItems(sale2.id, {lines2.first.lineId: 500});
    expect(refund, 750); // 1500 * 0.5
    expect(await stockOfName('Milk'), 1500);

    // A credited return reduces what the customer owes:
    // 1500 (sale) - 750 (return) - 500 (paid up front) = 250.
    expect((await db.watchCustomers().first)
        .firstWhere((c) => c.id == customer)
        .balance, 250);

    // ---------- payment ----------
    await db.recordPayment(
      partyType: 'customer',
      partyId: customer,
      direction: 'in',
      amount: 200,
      userId: admin.id,
    );
    expect(await db.receivablesTotal(), 50);

    final statement = await db.customerStatement(customer);
    expect(statement.where((e) => e.minus > 0).isNotEmpty, isTrue);

    // ---------- purchase from supplier ----------
    final supplier = await db.addSupplier(name: 'Supplier B');
    await db.createPurchase(
      supplierId: supplier,
      lines: [
        PurchaseLineInput(itemId: tea, qtyMilli: 2000, unitCost: 1700),
      ],
      paidNow: 0,
      userId: admin.id,
    );
    expect(await stockOfName('Tea'), 10000);
    expect(await db.payablesTotal(), 3400);

    // ---------- cancelled sale must not count ----------
    final sale3 = await db.completeSale(
      lines: [
        SaleLineInput(itemId: sugar, qtyMilli: 1000, unitPrice: 3000, unitCost: 2000),
      ],
      credit: false,
    );
    expect(await stockOfName('Sugar'), 3000);
    await db.cancelSale(sale3.id, userId: admin.id);
    expect(await stockOfName('Sugar'), 4000);

    // ---------- reports ----------
    final from = nowMs() - 86400000;
    final to = nowMs() + 86400000;
    final r = await db.report(from, to);
    expect(r.salesCount, 2); // the cancelled one is excluded
    expect(r.cashTotal, 7500);
    expect(r.creditTotal, 1500);
    expect(r.salesTotal, 9000);
    expect(r.returnsTotal, 750);
    expect(r.net, 8250);
    expect(r.cogs, 6600); // 3600 + 2000 + 1000
    expect(r.profit, 8250 - (6600 - 500));

    // ---------- invoice ----------
    final invoice = await db.invoiceForPrint(sale1.id);
    expect(invoice.number, 'D-0001');
    expect(invoice.total, 7500);
    expect(invoice.lines.length, 2);
    expect(invoice.cashierName, 'Admin');

    // ---------- inventory ----------
    expect(await db.inventoryValue(), greaterThan(0));
    final low = await db.lowStockItems();
    expect(low, isA<List<ItemRow>>());
  });
}
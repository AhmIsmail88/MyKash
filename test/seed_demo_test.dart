// ignore_for_file: avoid_print
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykash/data/database.dart';

/// Seeds a complete demo shop into whatever database MYKASH_SEED_DB points at.
///
/// Deliberately opt-in (environment variable) so a normal `flutter test` run
/// never touches a real database.
void main() {
  final target = Platform.environment['MYKASH_SEED_DB'];

  test('seed a complete demo shop', () async {
    final file = File(target!);
    final db = AppDatabase.forTesting(NativeDatabase(file));
    await db.initDevice(isMobile: false);
    await db.setSetting('shop_name', 'متجر الاختبار');
    await db.setSetting('currency', 'ج.م');

    final admin = await db.createUser(name: 'أحمد', role: 'admin', pin: '1234');
    await db.createUser(name: 'محمود', role: 'cashier', pin: '1111');

    await db.addItem(
        name: 'شاي',
        salePrice: 2500,
        costPrice: 1800,
        openingQtyMilli: 10000,
        barcode: '1001');
    await db.addItem(
        name: 'سكر',
        salePrice: 3000,
        costPrice: 2000,
        openingQtyMilli: 5000,
        barcode: '1002');
    await db.addItem(
        name: 'لبن',
        salePrice: 1500,
        costPrice: 1000,
        openingQtyMilli: 2000,
        barcode: '1003');

    final rows = await db.watchItems('').first;
    final tea = rows.firstWhere((r) => r.name == 'شاي').id;
    final sugar = rows.firstWhere((r) => r.name == 'سكر').id;
    final milk = rows.firstWhere((r) => r.name == 'لبن').id;

    final customer =
        await db.addCustomer(name: 'عميل نقدي', phone: '01000000000', creditLimit: 200000);

    await db.completeSale(
      lines: [
        SaleLineInput(itemId: tea, qtyMilli: 2000, unitPrice: 2500, unitCost: 1800),
        SaleLineInput(itemId: sugar, qtyMilli: 1000, unitPrice: 3000, unitCost: 2000),
      ],
      credit: false,
      discount: 500,
      userId: admin.id,
    );

    await db.completeSale(
      lines: [
        SaleLineInput(itemId: milk, qtyMilli: 3000, unitPrice: 1500, unitCost: 1000),
      ],
      credit: true,
      customerId: customer,
      paidNow: 1000,
      userId: admin.id,
    );

    final supplier = await db.addSupplier(name: 'مورد الجملة', phone: '01111111111');
    await db.createPurchase(
      supplierId: supplier,
      lines: [
        PurchaseLineInput(itemId: tea, qtyMilli: 4000, unitCost: 1700),
      ],
      paidNow: 2000,
      userId: admin.id,
    );

    final items = await db.watchItems('').first;
    final sales = await db.watchSales('', 'all').first;
    final customers = await db.watchCustomers().first;
    print('SEED_ITEMS=${items.length}');
    print('SEED_SALES=${sales.length}');
    print('SEED_CUSTOMERS=${customers.length}');
    print('SEED_INVENTORY=${await db.inventoryValue()}');
    print('SEED_RECEIVABLES=${await db.receivablesTotal()}');
    print('SEED_PAYABLES=${await db.payablesTotal()}');
    await db.close();
  }, skip: target == null ? 'set MYKASH_SEED_DB to a database file to seed' : null);
}
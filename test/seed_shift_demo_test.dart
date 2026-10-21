// ignore_for_file: avoid_print
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykash/data/database.dart';

/// Seeds a demo shop WITH an open shift and sales attached to it.
/// Opt-in via MYKASH_SEED_DB; never touches a real database otherwise.
void main() {
  final target = Platform.environment['MYKASH_SEED_DB'];

  test('seed a shift with sales', () async {
    final db = AppDatabase.forTesting(NativeDatabase(File(target!)));
    await db.initDevice(isMobile: false);
    await db.setSetting('shop_name', 'متجر الاختبار');

    final admin = await db.createUser(name: 'Admin', role: 'admin', pin: '1234');

    await db.addItem(
        name: 'شاي', salePrice: 2500, costPrice: 1800, openingQtyMilli: 20000);
    await db.addItem(
        name: 'سكر', salePrice: 3000, costPrice: 2000, openingQtyMilli: 10000);
    await db.addItem(
        name: 'لبن', salePrice: 1500, costPrice: 1000, openingQtyMilli: 8000);

    final rows = await db.watchItems('').first;
    String idOf(String n) => rows.firstWhere((r) => r.name == n).id;
    final tea = idOf('شاي');
    final sugar = idOf('سكر');
    final milk = idOf('لبن');

    final shift = await db.openShift(userId: admin.id, openingCash: 100000);

    await db.completeSale(
      lines: [
        SaleLineInput(itemId: tea, qtyMilli: 2000, unitPrice: 2500, unitCost: 1800),
        SaleLineInput(itemId: sugar, qtyMilli: 1000, unitPrice: 3000, unitCost: 2000),
      ],
      credit: false,
      discount: 500,
      userId: admin.id,
    );

    final customer = await db.addCustomer(name: 'عميل آجل', creditLimit: 200000);
    await db.completeSale(
      lines: [
        SaleLineInput(itemId: milk, qtyMilli: 3000, unitPrice: 1500, unitCost: 1000),
      ],
      credit: true,
      customerId: customer,
      paidNow: 1000,
      userId: admin.id,
    );

    final summary = await db.shiftSummary(shift.id);
    print('SHIFT=${shift.number} opening=${shift.openingCash}');
    print('cashSales=${summary.cashSales} creditSales=${summary.creditSales} count=${summary.salesCount}');
    print('cashFromSales=${summary.cashFromSales} expected=${summary.expectedCash}');
    await db.close();
  }, skip: target == null ? 'set MYKASH_SEED_DB' : null);
}
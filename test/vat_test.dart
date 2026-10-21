import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykash/data/database.dart';

void main() {
  group('computeVat', () {
    test('exclusive adds tax on top of the net amount', () {
      final r = computeVat(10000, 14);
      expect(r.tax, 1400);
      expect(r.total, 11400);
    });

    test('inclusive keeps the total and extracts the tax part', () {
      final r = computeVat(11400, 14, inclusive: true);
      expect(r.total, 11400);
      expect(r.tax, 1400);
    });

    test('rounds to the nearest minor unit', () {
      final r = computeVat(3000, 14);
      expect(r.tax, 420);
      expect(r.total, 3420);
    });

    test('zero rate changes nothing', () {
      final r = computeVat(7500, 0);
      expect(r.tax, 0);
      expect(r.total, 7500);
    });

    test('negative net is clamped to zero', () {
      final r = computeVat(-500, 14);
      expect(r.tax, 0);
      expect(r.total, 0);
    });
  });

  group('sales with VAT', () {
    late AppDatabase db;
    late String itemId;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      await db.initDevice(isMobile: false);
      await db.addItem(name: 'A', salePrice: 3000, openingQtyMilli: 10000);
      itemId = (await db.watchItems('').first).firstWhere((i) => i.name == 'A').id;
    });

    tearDown(() async => db.close());

    Future<({String id, String number})> sell() => db.completeSale(
          lines: [
            SaleLineInput(itemId: itemId, qtyMilli: 1000, unitPrice: 3000),
          ],
          credit: false,
        );

    test('exclusive VAT is added to the stored total', () async {
      await db.setSetting('vat_rate', '14');
      final sale = await sell();
      final row =
          await (db.select(db.sales)..where((s) => s.id.equals(sale.id)))
              .getSingle();
      expect(row.subtotal, 3000);
      expect(row.tax, 420);
      expect(row.total, 3420);
      expect(row.paid, 3420);
    });

    test('inclusive VAT keeps the total unchanged', () async {
      await db.setSetting('vat_rate', '14');
      await db.setSetting('vat_inclusive', '1');
      final sale = await sell();
      final row =
          await (db.select(db.sales)..where((s) => s.id.equals(sale.id)))
              .getSingle();
      expect(row.total, 3000);
      expect(row.tax, 368); // 3000 * 14 / 114
    });

    test('no rate means no tax at all', () async {
      final sale = await sell();
      final row =
          await (db.select(db.sales)..where((s) => s.id.equals(sale.id)))
              .getSingle();
      expect(row.tax, 0);
      expect(row.total, 3000);
    });

    test('report and invoice carry the tax', () async {
      await db.setSetting('vat_rate', '14');
      final sale = await sell();
      final r = await db.report(nowMs() - 86400000, nowMs() + 86400000);
      expect(r.taxTotal, 420);
      expect(r.salesTotal, 3420);

      final invoice = await db.invoiceForPrint(sale.id);
      expect(invoice.tax, 420);
      expect(invoice.total, 3420);
    });

    test('discount is applied before VAT', () async {
      await db.setSetting('vat_rate', '14');
      final sale = await db.completeSale(
        lines: [
          SaleLineInput(itemId: itemId, qtyMilli: 1000, unitPrice: 3000),
        ],
        credit: false,
        discount: 500,
      );
      final row =
          await (db.select(db.sales)..where((s) => s.id.equals(sale.id)))
              .getSingle();
      expect(row.subtotal, 3000);
      expect(row.discount, 500);
      expect(row.tax, 350); // 14% of 2500
      expect(row.total, 2850);
    });
  });
}
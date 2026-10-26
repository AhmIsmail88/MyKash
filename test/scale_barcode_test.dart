import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykash/data/database.dart';

void main() {
  group('parseScaleCode', () {
    // prefix(2) + plu(12345) + value(012500) + check(0)
    const code = '2123450125000';

    test('splits a 13 digit code into plu and value', () {
      final p = parseScaleCode(code);
      expect(p, isNotNull);
      expect(p!.plu, '12345');
      expect(p.value, 12500);
    });

    test('respects a custom prefix', () {
      expect(parseScaleCode('9123450125000', prefix: '9')!.plu, '12345');
      expect(parseScaleCode(code, prefix: '9'), isNull);
    });

    test('rejects wrong length, letters and bad digits', () {
      expect(parseScaleCode('212345012500'), isNull);
      expect(parseScaleCode('21234501250001'), isNull);
      expect(parseScaleCode('21234501250A0'), isNull);
    });
  });

  group('matchScaleBarcode', () {
    late AppDatabase db;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      await db.initDevice(isMobile: false);
      await db.addItem(
          name: 'Tomatoes',
          salePrice: 2000,
          costPrice: 1200,
          openingQtyMilli: 50000,
          barcode: '12345');
    });

    tearDown(() async => db.close());

    test('weight mode turns the value into quantity', () async {
      final scan = await db.matchScaleBarcode('2123450125000');
      expect(scan, isNotNull);
      expect(scan!.match.item.name, 'Tomatoes');
      expect(scan.qtyMilli, 12500);
      expect(scan.priceOverride, isNull);
    });

    test('price mode fixes the line price instead', () async {
      await db.setSetting('scale_mode', 'price');
      final scan = await db.matchScaleBarcode('2123450125000');
      expect(scan, isNotNull);
      expect(scan!.qtyMilli, 1000);
      expect(scan.priceOverride, 12500);
    });

    test('returns null for a normal barcode', () async {
      expect(await db.matchScaleBarcode('999999'), isNull);
    });

    test('returns null when the plu is unknown', () async {
      expect(await db.matchScaleBarcode('2999990125000'), isNull);
    });
  });
}
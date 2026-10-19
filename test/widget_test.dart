import 'package:flutter_test/flutter_test.dart';
import 'package:mykash/core/format.dart';

void main() {
  group('money', () {
    test('formatMoney omits decimals for whole amounts', () {
      kCurrency = 'X';
      expect(formatMoney(9500), '95 X');
    });

    test('formatMoney keeps two decimals for fractional amounts', () {
      kCurrency = 'X';
      expect(formatMoney(9550), '95.50 X');
    });

    test('parseMoney converts to minor units', () {
      expect(parseMoney('95'), 9500);
      expect(parseMoney('95.5'), 9550);
      expect(parseMoney('19.99'), 1999);
      expect(parseMoney(''), 0);
      expect(parseMoney('abc'), 0);
    });

    test('moneyInput round-trips through parseMoney', () {
      expect(moneyInput(9500), '95');
      expect(moneyInput(9550), '95.50');
      expect(parseMoney(moneyInput(1999)), 1999);
    });

    test('formatAmount strips the currency symbol', () {
      expect(formatAmount(9500), '95');
      expect(formatAmount(9550), '95.50');
    });
  });

  group('quantity', () {
    test('parseQty converts to milli units', () {
      expect(parseQty('3'), 3000);
      expect(parseQty('2.5'), 2500);
      expect(parseQty('0.125'), 125);
      expect(parseQty(''), 0);
    });

    test('formatQty trims trailing zeros', () {
      expect(formatQty(3000), '3');
      expect(formatQty(2500), '2.5');
      expect(formatQty(125), '0.125');
    });

    test('parseQty round-trips through formatQty', () {
      for (final milli in [1000, 2500, 125, 750]) {
        expect(parseQty(formatQty(milli)), milli);
      }
    });
  });

  test('latinDigits leaves latin input untouched', () {
    expect(latinDigits('123.45'), '123.45');
  });
}
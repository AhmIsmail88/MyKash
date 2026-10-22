import 'package:flutter_test/flutter_test.dart';
import 'package:mykash/data/database.dart';

void main() {
  tearDown(() => kBusinessType = 'general');

  test('every business type has an Arabic label', () {
    expect(kBusinessTypes.length, 4);
    expect(kBusinessTypes.keys,
        containsAll(<String>['general', 'grocery', 'feed', 'restaurant']));
    for (final label in kBusinessTypes.values) {
      expect(label.trim(), isNotEmpty);
    }
  });

  test('the default unit follows the business type', () {
    kBusinessType = 'feed';
    expect(businessDefaultUnit(), 'شيكارة');

    kBusinessType = 'restaurant';
    expect(businessDefaultUnit(), 'طبق');

    kBusinessType = 'grocery';
    expect(businessDefaultUnit(), 'قطعة');

    kBusinessType = 'general';
    expect(businessDefaultUnit(), 'حبة');
  });

  test('an unknown business type falls back to the generic unit', () {
    kBusinessType = 'something-else';
    expect(businessDefaultUnit(), 'حبة');
  });
}
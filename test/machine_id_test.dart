import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mykash/core/license/machine_id.dart';

void main() {
  group('SMBIOS UUID validation', () {
    test('accepts a real firmware UUID', () {
      expect(isUsableSmbiosUuid('4C4C4544-0038-3510-8048-B2C04F4E4432'), isTrue);
      expect(isUsableSmbiosUuid('4c4c4544-0038-3510-8048-b2c04f4e4432'), isTrue);
      expect(isUsableSmbiosUuid('  4C4C4544-0038-3510-8048-B2C04F4E4432  '), isTrue);
    });

    test('rejects blank-board and vendor placeholder UUIDs', () {
      expect(isUsableSmbiosUuid('FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF'), isFalse);
      expect(isUsableSmbiosUuid('00000000-0000-0000-0000-000000000000'), isFalse);
      expect(isUsableSmbiosUuid('03000200-0400-0500-0006-000700080009'), isFalse);
      expect(isUsableSmbiosUuid('12345678-1234-1234-1234-123456789ABC'), isFalse);
    });

    test('rejects malformed values', () {
      expect(isUsableSmbiosUuid(''), isFalse);
      expect(isUsableSmbiosUuid('not-a-uuid'), isFalse);
      expect(isUsableSmbiosUuid('4C4C4544-0038-3510-8048'), isFalse);
    });
  });

  test('resolves a stable MACH fingerprint on Windows', () async {
    debugResetMachineIdCache();
    final id = await machineFingerprint();
    // ignore: avoid_print
    print('MACHINE_FINGERPRINT=$id');
    expect(id, matches(RegExp(r'^MACH-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}$')));
    expect(await machineFingerprint(), id);
  }, skip: Platform.isWindows ? null : 'Windows-only probe');
}
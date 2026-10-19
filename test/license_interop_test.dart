import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mykash/core/license/license_service.dart';

/// End-to-end check that a token produced by `tools/license/make_license.py`
/// is accepted by the app's verifier.
///
/// Opt-in only: set the three environment variables to run it. This keeps
/// normal test runs independent of any real key material.
void main() {
  final token = Platform.environment['MYKASH_TEST_TOKEN'];
  final pub = Platform.environment['MYKASH_TEST_PUB'];
  final machine = Platform.environment['MYKASH_TEST_MACHINE'];
  final ready = token != null && pub != null && machine != null;

  test('accepts a token issued by make_license.py', () async {
    final r = await LicenseService.verify(token!,
        publicKeyB64: pub!, machineId: machine!);
    expect(r.valid, isTrue, reason: r.error);
  }, skip: ready
      ? null
      : 'set MYKASH_TEST_TOKEN / MYKASH_TEST_PUB / MYKASH_TEST_MACHINE');

  test('rejects the same token for a different machine', () async {
    final r = await LicenseService.verify(token!,
        publicKeyB64: pub!, machineId: 'MACH-0000-0000-0000');
    expect(r.valid, isFalse);
  }, skip: ready
      ? null
      : 'set MYKASH_TEST_TOKEN / MYKASH_TEST_PUB / MYKASH_TEST_MACHINE');
}
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mykash/core/license/machine_id.dart';

/// Proves the OS-level identity is actually readable on this host.
///
/// Skipped automatically on platforms where the probe would need a real app
/// shell (the Android implementation talks to a MethodChannel).
void main() {
  test('resolves a stable MACH fingerprint on Windows', () async {
    final id = await machineFingerprint();
    // ignore: avoid_print
    print('MACHINE_FINGERPRINT=$id');
    expect(id, matches(RegExp(r'^MACH-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}$')));
    // A second call must return the cached, identical value.
    expect(await machineFingerprint(), id);
  }, skip: Platform.isWindows ? null : 'Windows-only probe');
}
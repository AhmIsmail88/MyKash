import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Thrown when this machine's identity cannot be read.
class MachineIdException implements Exception {
  final String message;
  const MachineIdException(this.message);

  @override
  String toString() => 'MachineIdException: $message';
}

String? _cachedValue;
String? _cachedPlatform;

const MethodChannel _deviceChannel = MethodChannel('mykash/device');

/// Stable per-machine identifier used to bind a license to one installation.
///
/// The value comes from an operating-system identifier, never from the app
/// database. Copying `mykash.sqlite` to another machine therefore does not
/// carry this identity with it, which is what makes a license non-transferable.
Future<String> machineFingerprint() async {
  final platform = Platform.operatingSystem;
  final cached = _cachedValue;
  if (cached != null && _cachedPlatform == platform) return cached;

  final String raw;
  try {
    raw = await _rawMachineId();
  } catch (_) {
    throw const MachineIdException(
        'تعذر قراءة بصمة الجهاز. أعد تشغيل التطبيق، وإذا تكرر الخطأ راسل الدعم.');
  }
  if (raw.trim().isEmpty) {
    throw const MachineIdException(
        'تعذر قراءة بصمة الجهاز. أعد تشغيل التطبيق، وإذا تكرر الخطأ راسل الدعم.');
  }

  final digest =
      sha256.convert(utf8.encode('mykash|v1|$platform|$raw')).toString();
  final id = formatFingerprint(digest.substring(0, 12));
  _cachedValue = id;
  _cachedPlatform = platform;
  return id;
}

/// Formats 12 hex characters as `MACH-XXXX-XXXX-XXXX`.
///
/// Pure on purpose: the grouping rules can be unit tested without touching
/// the operating system.
String formatFingerprint(String hex12) {
  final hex = hex12.toUpperCase().padRight(12, '0');
  return 'MACH-${hex.substring(0, 4)}-${hex.substring(4, 8)}-${hex.substring(8, 12)}';
}

/// Drops the process-wide cache. Only used by tests.
void debugResetMachineIdCache() {
  _cachedValue = null;
  _cachedPlatform = null;
}

Future<String> _rawMachineId() async {
  if (Platform.isWindows) return _windowsMachineId();
  if (Platform.isAndroid) return _androidMachineId();
  return _fallbackFileId();
}

Future<String> _windowsMachineId() async {
  // `reg.exe` is used instead of hand-rolled advapi32 FFI: same value, no ABI
  // risk, and it works on every supported Windows build.
  final query = await Process.run(
    'reg',
    <String>[
      'query',
      r'HKLM\SOFTWARE\Microsoft\Cryptography',
      '/v',
      'MachineGuid',
      '/reg:64',
    ],
  );
  if (query.exitCode == 0) {
    final match =
        RegExp(r'MachineGuid\s+REG_SZ\s+(\S+)').firstMatch('${query.stdout}');
    final guid = match?.group(1)?.trim() ?? '';
    if (guid.isNotEmpty) return guid;
  }
  // Fallback: the volume serial number of the system drive.
  final vol = await Process.run(
    'cmd',
    <String>['/c', 'vol', Platform.environment['SystemDrive'] ?? 'C:'],
  );
  final serial =
      RegExp(r'[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}').firstMatch('${vol.stdout}');
  if (serial != null) return 'vol:${serial.group(0)}';
  throw const MachineIdException('windows');
}

Future<String> _androidMachineId() async {
  final info =
      await _deviceChannel.invokeMapMethod<String, String>('fingerprintRaw');
  final androidId = (info?['androidId'] ?? '').trim();
  if (androidId.isEmpty) throw const MachineIdException('android');
  return <String>[
    androidId,
    info?['manufacturer'] ?? '',
    info?['model'] ?? '',
    info?['fingerprint'] ?? '',
  ].join('|');
}

/// Weak fallback for platforms without a stable hardware identifier.
Future<String> _fallbackFileId() async {
  final dir = await getApplicationSupportDirectory();
  final file = File(p.join(dir.path, '.mykash_machine_id'));
  if (await file.exists()) {
    final existing = (await file.readAsString()).trim();
    if (existing.isNotEmpty) return existing;
  }
  final random = Random.secure();
  final value = base64Url
      .encode(List<int>.generate(18, (_) => random.nextInt(256)))
      .replaceAll('=', '');
  await file.writeAsString(value, flush: true);
  return value;
}
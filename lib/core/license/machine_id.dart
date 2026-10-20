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

/// Stable per-machine identifier used to bind a licence to one installation.
///
/// The value comes from operating-system identifiers, never from the app
/// database. Copying `mykash.sqlite` or a Windows disk image to another machine
/// therefore does not carry this identity with it.
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

  // v2 mixes in the SMBIOS UUID on Windows so a cloned disk image no longer
  // produces the same fingerprint.
  final digest =
      sha256.convert(utf8.encode('mykash|v2|$platform|$raw')).toString();
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

/// Firmware UUIDs that identify nothing: blank boards, Hyper-V defaults and
/// the AMI placeholder that ships on a lot of cheap hardware. Treating them as
/// identity would make every such machine share one fingerprint.
const Set<String> _placeholderUuids = <String>{
  'FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF',
  '00000000-0000-0000-0000-000000000000',
  '03000200-0400-0500-0006-000700080009',
  '12345678-1234-1234-1234-123456789ABC',
};

/// True when [value] looks like a real, unique SMBIOS UUID.
bool isUsableSmbiosUuid(String value) {
  final v = value.trim().toUpperCase();
  final shape = RegExp(
      r'^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$');
  if (!shape.hasMatch(v)) return false;
  return !_placeholderUuids.contains(v);
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
  // Precedence matters:
  //  * SMBIOS UUID first - it lives in the firmware, so it survives a Windows
  //    reinstall on the same board but differs on any cloned disk image.
  //  * MachineGuid second - survives nothing but is present on every install.
  //  * Volume serial last - weakest of the three.
  // Mixing SMBIOS and MachineGuid together would break licences whenever
  // Windows is reinstalled, so exactly one source is used.
  final uuid = await _smbiosUuid();
  if (uuid.isNotEmpty) return 'smbios:$uuid';

  final guid =
      await _registryValue(r'HKLM\SOFTWARE\Microsoft\Cryptography', 'MachineGuid');
  if (guid.isNotEmpty) return 'guid:$guid';

  final serial = await _volumeSerial();
  if (serial.isNotEmpty) return 'vol:$serial';

  throw const MachineIdException('windows');
}

/// Reads a REG_SZ value with reg.exe: no extra dependency, no ABI risk.
Future<String> _registryValue(String key, String name) async {
  try {
    final r = await Process.run(
      'reg',
      <String>['query', key, '/v', name, '/reg:64'],
    );
    if (r.exitCode != 0) return '';
    final match =
        RegExp('$name\\s+REG_SZ\\s+(\\S+)').firstMatch('${r.stdout}');
    return match?.group(1)?.trim() ?? '';
  } catch (_) {
    return '';
  }
}

/// Firmware identifier of the motherboard/VM. Survives a disk clone only when
/// the clone runs on the same physical board - which is exactly what we want.
Future<String> _smbiosUuid() async {
  try {
    final r = await Process.run('powershell', <String>[
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      '(Get-CimInstance -ClassName Win32_ComputerSystemProduct).UUID',
    ]);
    if (r.exitCode != 0) return '';
    final value = '${r.stdout}'.trim().toUpperCase();
    return isUsableSmbiosUuid(value) ? value : '';
  } catch (_) {
    return '';
  }
}

Future<String> _volumeSerial() async {
  try {
    final vol = await Process.run(
      'cmd',
      <String>['/c', 'vol', Platform.environment['SystemDrive'] ?? 'C:'],
    );
    final serial =
        RegExp(r'[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}').firstMatch('${vol.stdout}');
    return serial?.group(0) ?? '';
  } catch (_) {
    return '';
  }
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
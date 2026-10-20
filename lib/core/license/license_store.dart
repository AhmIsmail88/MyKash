import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'license_key.dart';
import 'machine_id.dart';

/// Locally persisted licensing state.
///
/// This lives OUTSIDE the SQLite database on purpose: wiping or replacing
/// `mykash.sqlite` must not reset the trial or drop the activation.
class LicenseState {
  final String machine;
  final int? trialStart;
  final int? lastSeen;
  final String? licenseCode;
  final bool tampered;

  const LicenseState({
    required this.machine,
    this.trialStart,
    this.lastSeen,
    this.licenseCode,
    this.tampered = false,
  });

  LicenseState copyWith({
    String? machine,
    int? trialStart,
    int? lastSeen,
    String? licenseCode,
    bool? tampered,
  }) {
    return LicenseState(
      machine: machine ?? this.machine,
      trialStart: trialStart ?? this.trialStart,
      lastSeen: lastSeen ?? this.lastSeen,
      licenseCode: licenseCode ?? this.licenseCode,
      tampered: tampered ?? this.tampered,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'v': 1,
        'machine': machine,
        'trial_start': trialStart,
        'last_seen': lastSeen,
        'license_code': licenseCode,
      };

  factory LicenseState.fromJson(Map<String, dynamic> json) {
    return LicenseState(
      machine: (json['machine'] as String?) ?? '',
      trialStart: json['trial_start'] as int?,
      lastSeen: json['last_seen'] as int?,
      licenseCode: json['license_code'] as String?,
    );
  }
}

/// Stores [LicenseState] in a sidecar file protected by an HMAC.
///
/// The HMAC is tamper-EVIDENT, not tamper-proof: the key is derived from this
/// machine plus an application secret, so a hand-edited file is detected, but a
/// determined attacker with the binary can still forge one. The real guarantee
/// comes from the Ed25519 signature on the license code itself.
class LicenseStore {
  LicenseState? _cached;
  bool _loaded = false;

  Future<File> _file() async {
    if (Platform.isWindows) {
      final dirs = <String>[
        if ((Platform.environment['ProgramData'] ?? '').isNotEmpty)
          p.join(Platform.environment['ProgramData']!, 'MyKash'),
        if ((Platform.environment['APPDATA'] ?? '').isNotEmpty)
          p.join(Platform.environment['APPDATA']!, 'MyKash'),
      ];
      for (final dir in dirs) {
        try {
          final d = Directory(dir);
          await d.create(recursive: true);
          final probe = File(p.join(d.path, '.write_probe'));
          await probe.writeAsString('1', flush: true);
          await probe.delete();
          return File(p.join(d.path, 'license_state.json'));
        } catch (_) {
          continue;
        }
      }
      throw const FileSystemException('لا يوجد مسار صالح لحفظ حالة الترخيص.');
    }
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    return File(p.join(dir.path, 'license_state.json'));
  }

  Future<Hmac> _hmac() async {
    final machine = await machineFingerprint();
    final key = sha256.convert(utf8.encode(machine + kLicenseStateSecret)).bytes;
    return Hmac(sha256, key);
  }

  /// Reads the stored state. Returns `null` when nothing has been written yet.
  /// An unreadable or hand-edited file comes back flagged [LicenseState.tampered].
  Future<LicenseState?> read() async {
    if (_loaded) return _cached;
    _loaded = true;

    final file = await _file();
    if (!await file.exists()) return _cached = null;

    try {
      final envelope =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final data = envelope['data'] as String;
      final storedMac = envelope['mac'] as String;
      final expected = base64Encode(
          (await _hmac()).convert(utf8.encode(data)).bytes);
      final decoded = jsonDecode(data) as Map<String, dynamic>;
      // Files written before the state schema was versioned cannot be trusted
      // once the fingerprint algorithm changes: drop them and let the database
      // re-seed rather than locking the user out with "tampered".
      if (decoded['v'] == null) return _cached = null;
      final parsed = LicenseState.fromJson(decoded);
      if (expected != storedMac) {
        return _cached = parsed.copyWith(tampered: true);
      }
      return _cached = parsed;
    } catch (_) {
      return _cached = LicenseState(machine: await _safeMachine(), tampered: true);
    }
  }

  Future<String> _safeMachine() async {
    try {
      return await machineFingerprint();
    } catch (_) {
      return '';
    }
  }

  Future<void> write(LicenseState state) async {
    final data = jsonEncode(state.toJson());
    final mac = base64Encode((await _hmac()).convert(utf8.encode(data)).bytes);
    final file = await _file();
    await file.writeAsString(jsonEncode(<String, String>{'data': data, 'mac': mac}),
        flush: true);
    _cached = state;
    _loaded = true;
  }

  Future<void> wipe() async {
    final file = await _file();
    if (await file.exists()) await file.delete();
    _cached = null;
    _loaded = true;
  }
}
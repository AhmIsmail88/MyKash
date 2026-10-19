import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import '../../data/database.dart';
import '../app_info.dart';
import 'license_key.dart';
import 'license_store.dart';
import 'machine_id.dart';

enum LicenseKind { disabled, trial, licensed, expired, tampered }

class LicenseStatus {
  final LicenseKind kind;
  final int daysLeft;
  final String? shop;
  final String? until; // YYYY-MM-DD أو null لو دائم
  const LicenseStatus(this.kind, {this.daysLeft = 0, this.shop, this.until});

  bool get canUse =>
      kind == LicenseKind.disabled ||
      kind == LicenseKind.trial ||
      kind == LicenseKind.licensed;

  bool get showBanner => kind == LicenseKind.trial;

  String get text {
    switch (kind) {
      case LicenseKind.disabled:
        return 'الترخيص غير مفعّل في هذه النسخة';
      case LicenseKind.trial:
        return 'نسخة تجريبية: باقي $daysLeft يوم';
      case LicenseKind.licensed:
        return until == null
            ? 'مرخّص (دائم)${shop == null ? "" : " — $shop"}'
            : 'مرخّص حتى $until${shop == null ? "" : " — $shop"}';
      case LicenseKind.expired:
        return 'انتهى الترخيص أو الفترة التجريبية';
      case LicenseKind.tampered:
        return 'تاريخ الجهاز غير صحيح (رجوع بالوقت). صحّح التاريخ أو فعّل الترخيص';
    }
  }
}

class LicenseCheck {
  final bool valid;
  final String? error;
  final Map<String, dynamic>? payload;
  const LicenseCheck.ok(this.payload)
      : valid = true,
        error = null;
  const LicenseCheck.fail(this.error)
      : valid = false,
        payload = null;
}

/// ترخيص أوفلاين: كود موقّع Ed25519 مربوط بمعرّفات الأجهزة وتاريخ انتهاء،
/// وفترة تجريبية. التحقق محلي بالكامل. (أي ترخيص أوفلاين يمكن الالتفاف عليه
/// من مستخدم متمكّن؛ الهدف منع الاستخدام العادي غير المرخّص.)
class LicenseService {
  LicenseService(this.db);
  final AppDatabase db;

  static const _day = 24 * 3600 * 1000;

  final LicenseStore _store = LicenseStore();

  /// This machine's licence fingerprint, or an empty string when unreadable.
  Future<String> _thisMachine() async {
    try {
      return await machineFingerprint();
    } catch (_) {
      return '';
    }
  }

  /// Reads the sidecar state, seeding it from the database on first run so an
  /// installation that predates the sidecar file keeps its activation.
  Future<LicenseState> _loadState() async {
    try {
      final existing = await _store.read();
      if (existing != null) return existing;
    } catch (_) {
      return LicenseState(machine: await _thisMachine(), tampered: true);
    }
    final migrated = LicenseState(
      machine: await _thisMachine(),
      trialStart: int.tryParse(await db.getSetting('trial_start') ?? ''),
      lastSeen: int.tryParse(await db.getSetting('lic_last_seen') ?? ''),
      licenseCode: await db.getSetting('license_code'),
    );
    try {
      await _store.write(migrated);
    } catch (_) {
      // A read-only ProgramData is not fatal: the database copy still works.
    }
    return migrated;
  }

  Future<LicenseStatus> status() async {
    if (!kLicensingEnabled) return const LicenseStatus(LicenseKind.disabled);
    final now = nowMs();

    // حماية بسيطة من إرجاع ساعة الجهاز للخلف
    final state = await _loadState();
    if (state.tampered) return const LicenseStatus(LicenseKind.tampered);
    final lastSeen = state.lastSeen ?? 0;
    if (now < lastSeen - _day) return const LicenseStatus(LicenseKind.tampered);
    if (now > lastSeen) await _store.write(state.copyWith(lastSeen: now));

    final code = state.licenseCode;
    if (code != null && code.isNotEmpty) {
      final c = await LicenseService.verify(code);
      if (c.valid) {
        final exp = c.payload!['exp'] as String?;
        return LicenseStatus(LicenseKind.licensed,
            shop: c.payload!['shop'] as String?,
            until: (exp == null || exp.isEmpty) ? null : exp);
      }
    }

    var start = state.trialStart;
    if (start == null) {
      start = now;
      await _store.write(state.copyWith(trialStart: start));
    }
    final left = ((start + kTrialDays * _day - now) / _day).ceil();
    return left > 0
        ? LicenseStatus(LicenseKind.trial, daysLeft: left)
        : const LicenseStatus(LicenseKind.expired);
  }

  static Future<LicenseCheck> verify(String raw,
      {String? publicKeyB64, String? machineId}) async {
    final pubKey = publicKeyB64 ?? kLicensePublicKeyB64;
    if (pubKey.startsWith('REPLACE')) {
      return const LicenseCheck.fail('لم يُضبط مفتاح الترخيص العام في التطبيق');
    }
    final parts = raw.trim().split('.');
    if (parts.length != 3 || parts[0] != 'MYK1') {
      return const LicenseCheck.fail('صيغة الكود غير صحيحة');
    }
    List<int> payloadBytes, sig;
    try {
      payloadBytes = base64Url.decode(base64Url.normalize(parts[1]));
      sig = base64Url.decode(base64Url.normalize(parts[2]));
    } catch (_) {
      return const LicenseCheck.fail('الكود تالف');
    }
    final bool ok;
    try {
      ok = await Ed25519().verify(
        payloadBytes,
        signature: Signature(
          sig,
          publicKey: SimplePublicKey(base64.decode(pubKey),
              type: KeyPairType.ed25519),
        ),
      );
    } catch (_) {
      return const LicenseCheck.fail('تعذّر التحقق من الكود');
    }
    if (!ok) return const LicenseCheck.fail('الكود غير صالح');
    final Map<String, dynamic> payload;
    try {
      payload = jsonDecode(utf8.decode(payloadBytes)) as Map<String, dynamic>;
    } catch (_) {
      return const LicenseCheck.fail('بيانات الكود تالفة');
    }
    final devs = ((payload['devices'] as List?) ?? const []).cast<String>();
    final thisMachine = machineId ?? await _machineOrEmpty();
    if (thisMachine.isEmpty) {
      return const LicenseCheck.fail(
          'تعذر قراءة بصمة الجهاز، لا يمكن التحقق من الترخيص.');
    }
    if (!devs.contains('*') && !devs.contains(thisMachine)) {
      return const LicenseCheck.fail('هذا الكود صادر لجهاز آخر');
    }
    final exp = payload['exp'] as String?;
    if (exp != null && exp.isNotEmpty) {
      final d = DateTime.tryParse(exp);
      if (d == null) return const LicenseCheck.fail('تاريخ الانتهاء في الكود غير صحيح');
      if (DateTime.now().isAfter(DateTime(d.year, d.month, d.day, 23, 59, 59))) {
        return LicenseCheck.fail('انتهت صلاحية هذا الكود في $exp');
      }
    }
    return LicenseCheck.ok(payload);
  }

  /// يتحقق من الكود ويحفظه.
  Future<LicenseCheck> activate(String raw) async {
    final c = await LicenseService.verify(raw);
    if (c.valid) {
      final code = raw.trim();
      await db.setSetting('license_code', code);
      final state = await _loadState();
      if (!state.tampered) {
        await _store.write(state.copyWith(licenseCode: code));
      }
    }
    return c;
  }
}

/// Fingerprint of this machine, or an empty string when it cannot be read.
///
/// Top-level so [LicenseService.verify] can stay static and be unit tested
/// without constructing a database-backed service.
Future<String> _machineOrEmpty() async {
  try {
    return await machineFingerprint();
  } catch (_) {
    return '';
  }
}
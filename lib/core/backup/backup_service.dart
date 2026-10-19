import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/database.dart';
import '../../sync/sync_providers.dart' show isHubPlatform;
import '../app_info.dart';
import '../paths.dart';

class BackupInfo {
  final File file;
  final String kind; // auto | manual | pre-upgrade | pre-restore
  final DateTime at;
  final int size;
  const BackupInfo(this.file, this.kind, this.at, this.size);

  String get kindLabel => switch (kind) {
        'auto' => 'تلقائية',
        'manual' => 'يدوية',
        'pre-upgrade' => 'قبل الترقية',
        'pre-restore' => 'قبل الاستعادة',
        _ => kind,
      };
}

/// قاعدة بيانات «فاحصة» تفتح أي ملف SQLite دون المساس بجداوله، وتلتقط إصدار
/// المخطط الأصلي (user_version) لنتأكد أنه نسخة MyKash صالحة قبل الاستعادة.
class _ProbeDb extends GeneratedDatabase {
  _ProbeDb(super.e);
  int? versionBefore;

  @override
  Iterable<TableInfo<Table, dynamic>> get allTables => const [];
  @override
  Iterable<DatabaseSchemaEntity> get allSchemaEntities => const [];
  @override
  int get schemaVersion => 1000;
  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {},
        onUpgrade: (m, from, to) async {},
        beforeOpen: (d) async => versionBefore = d.versionBefore,
      );
}

String _stamp(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}${two(d.month)}${two(d.day)}-${two(d.hour)}${two(d.minute)}${two(d.second)}';
}

String _sqlPath(String path) => path.replaceAll("'", "''");

/// نسخ احتياطي واستعادة. النسخة = ملف SQLite واحد (يشمل الإعدادات لأنها داخل القاعدة).
class BackupService {
  BackupService(this.db);
  final AppDatabase db;
  Timer? _timer;

  // ---------- عند بدء التطبيق (قبل فتح القاعدة) ----------

  /// نسخة أمان خام عند تغيّر إصدار التطبيق (قبل أي ترحيل للقاعدة).
  static Future<void> preOpenSafety() async {
    try {
      final dbFile = File(await AppPaths.dbPath());
      final verFile = File(await AppPaths.versionFilePath());
      final old = await verFile.exists() ? (await verFile.readAsString()).trim() : null;
      if (await dbFile.exists() && old != null && old != kAppVersion) {
        final dir = await AppPaths.backupsDir();
        final dest = p.join(
            dir.path, 'pre-upgrade-$old-to-$kAppVersion-${_stamp(DateTime.now())}.mykbak');
        await dbFile.copy(dest);
        final wal = File('${dbFile.path}-wal');
        if (await wal.exists()) await wal.copy('$dest-wal');
        await _prune(dir);
      }
      await verFile.writeAsString(kAppVersion);
    } catch (_) {}
  }

  /// لو هناك استعادة مجهّزة: نسخة أمان من القاعدة الحالية ثم استبدالها.
  static Future<bool> applyPendingRestore() async {
    final pending = File(await AppPaths.pendingRestorePath());
    if (!await pending.exists()) return false;
    final dbPath = await AppPaths.dbPath();
    final dbFile = File(dbPath);
    try {
      if (await dbFile.exists()) {
        final dir = await AppPaths.backupsDir();
        final safety = p.join(dir.path, 'pre-restore-${_stamp(DateTime.now())}.mykbak');
        try {
          final old = AppDatabase.forTesting(NativeDatabase(dbFile));
          await old.customStatement("VACUUM INTO '${_sqlPath(safety)}'");
          await old.close();
        } catch (_) {
          await dbFile.copy(safety); // احتياطي: نسخة خام
        }
        await _prune(dir);
      }
      for (final suffix in const ['', '-wal', '-shm', '-journal']) {
        final f = File('$dbPath$suffix');
        if (await f.exists()) await f.delete();
      }
      try {
        await pending.rename(dbPath);
      } catch (_) {
        await pending.copy(dbPath);
        await pending.delete();
      }
      await File(await AppPaths.epochFlagPath()).writeAsString('1');
      return true;
    } catch (_) {
      return false;
    }
  }

  /// بعد فتح القاعدة: لو تمت استعادة نغيّر «حقبة» المزامنة.
  static Future<void> afterOpen(AppDatabase db) async {
    final flag = File(await AppPaths.epochFlagPath());
    if (await flag.exists()) {
      await db.setSetting('sync_epoch', newId());
      await flag.delete();
    }
  }

  // ---------- النسخ التلقائي ----------

  void startAuto() {
    _maybeAuto();
    _timer = Timer.periodic(const Duration(hours: 6), (_) => _maybeAuto());
  }

  void dispose() => _timer?.cancel();

  Future<void> _maybeAuto() async {
    try {
      final last = int.tryParse(await db.getSetting('last_auto_backup') ?? '') ?? 0;
      if (nowMs() - last < 20 * 3600 * 1000) return;
      await createBackup(kind: 'auto');
      await db.setSetting('last_auto_backup', '${nowMs()}');
    } catch (_) {}
  }

  // ---------- إنشاء وإدارة النسخ ----------

  /// ينشئ نسخة متسقة بـ VACUUM INTO (بدون إغلاق القاعدة)، ويحذف الأقدم، ويكرّرها لمجلد إضافي إن حُدِّد.
  Future<File> createBackup({String kind = 'manual'}) async {
    final dir = await AppPaths.backupsDir();
    final name = '$kind-${_stamp(DateTime.now())}.mykbak';
    final path = p.join(dir.path, name);
    await db.customStatement("VACUUM INTO '${_sqlPath(path)}'");
    await _prune(dir);
    final extra = await db.getSetting('backup_extra_dir');
    if (extra != null && extra.isNotEmpty) {
      try {
        await File(path).copy(p.join(extra, name));
      } catch (_) {}
    }
    return File(path);
  }

  Future<List<BackupInfo>> list() async {
    final dir = await AppPaths.backupsDir();
    final out = <BackupInfo>[];
    await for (final e in dir.list()) {
      if (e is! File || !e.path.endsWith('.mykbak')) continue;
      final name = p.basename(e.path);
      final kind = name.startsWith('pre-upgrade')
          ? 'pre-upgrade'
          : name.startsWith('pre-restore')
              ? 'pre-restore'
              : name.startsWith('auto')
                  ? 'auto'
                  : 'manual';
      final st = await e.stat();
      out.add(BackupInfo(e, kind, st.modified, st.size));
    }
    out.sort((a, b) => b.at.compareTo(a.at));
    return out;
  }

  Future<void> delete(BackupInfo b) async {
    await b.file.delete();
    final wal = File('${b.file.path}-wal');
    if (await wal.exists()) await wal.delete();
  }

  static Future<void> _prune(Directory dir) async {
    final limits = {'auto': 14, 'manual': 30, 'pre-upgrade': 5, 'pre-restore': 5};
    final files = <File>[];
    await for (final e in dir.list()) {
      if (e is File && e.path.endsWith('.mykbak')) files.add(e);
    }
    for (final entry in limits.entries) {
      final mine = files.where((f) => p.basename(f.path).startsWith(entry.key)).toList()
        ..sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
      for (final f in mine.skip(entry.value)) {
        try {
          await f.delete();
          final wal = File('${f.path}-wal');
          if (await wal.exists()) await wal.delete();
        } catch (_) {}
      }
    }
  }

  // ---------- التصدير والاستعادة ----------

  /// يصدّر ملفًا: على الديسك توب «حفظ باسم»، وعلى الموبايل مشاركة (واتساب/فلاش/Drive).
  /// يعيد رسالة للعرض (أو null).
  static Future<String?> exportFile(File f) async {
    if (isHubPlatform) {
      var target = await FilePicker.platform.saveFile(
        dialogTitle: 'حفظ النسخة الاحتياطية',
        fileName: p.basename(f.path),
      );
      if (target == null) return null;
      if (!target.endsWith('.mykbak')) target = '$target.mykbak';
      await f.copy(target);
      return 'تم الحفظ في $target';
    }
    await Share.shareXFiles([XFile(f.path)], subject: 'نسخة احتياطية MyKash');
    return null;
  }

  /// يتحقق من ملف النسخة ثم يجهّزه للاستعادة عند إعادة تشغيل التطبيق.
  /// يعيد رسالة خطأ، أو null عند النجاح.
  Future<String?> stageRestore(String srcPath) async {
    final src = File(srcPath);
    if (!await src.exists()) return 'الملف غير موجود';
    final tmpDir = await getTemporaryDirectory();
    final tmp = File(p.join(tmpDir.path, 'mykash_verify_${nowMs()}.sqlite'));
    await src.copy(tmp.path);
    _ProbeDb? probe;
    String? error;
    try {
      probe = _ProbeDb(NativeDatabase(tmp));
      final integ = await probe.customSelect('PRAGMA integrity_check').getSingle();
      final v = probe.versionBefore ?? 0;
      if (integ.read<String>('integrity_check') != 'ok') {
        error = 'ملف النسخة تالف';
      } else if (v < 1) {
        error = 'هذا الملف ليس نسخة احتياطية من MyKash';
      } else if (v > AppDatabase.currentSchema) {
        error = 'النسخة أحدث من هذا التطبيق. حدّث التطبيق أولًا';
      } else {
        final tables = await probe
            .customSelect(
                "SELECT COUNT(*) AS c FROM sqlite_master WHERE type='table' "
                "AND name IN ('items','sales','shop_settings','users')")
            .getSingle();
        if (tables.read<int>('c') < 4) error = 'هذا الملف ليس نسخة احتياطية من MyKash';
      }
    } catch (_) {
      error = 'تعذّر قراءة الملف كنسخة احتياطية';
    } finally {
      try {
        await probe?.close();
      } catch (_) {}
      try {
        await tmp.delete();
      } catch (_) {}
    }
    if (error != null) return error;
    await src.copy(await AppPaths.pendingRestorePath());
    return null;
  }
}

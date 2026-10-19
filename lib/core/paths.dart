import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// مسارات التطبيق. ملف القاعدة في مجلد المستندات كما في الإصدارات السابقة.
class AppPaths {
  static Future<Directory> docs() => getApplicationDocumentsDirectory();

  static Future<String> dbPath() async =>
      p.join((await docs()).path, 'mykash.sqlite');

  static Future<Directory> backupsDir() async {
    final d = Directory(p.join((await docs()).path, 'mykash_backups'));
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  static Future<String> pendingRestorePath() async =>
      p.join((await docs()).path, 'mykash_pending_restore.mykbak');

  static Future<String> epochFlagPath() async =>
      p.join((await docs()).path, 'mykash_sync_epoch_reset.flag');

  static Future<String> versionFilePath() async =>
      p.join((await docs()).path, 'mykash_app_version.txt');
}

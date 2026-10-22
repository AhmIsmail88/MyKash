import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/backup/backup_service.dart';
import 'core/format.dart';
import 'data/database.dart';
import 'data/providers.dart';
import 'features/auth/session.dart';
import 'features/backup/backup_provider.dart';
import 'sync/sync_providers.dart';
import 'sync/sync_server.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // قبل فتح القاعدة: نسخة أمان عند تغيّر الإصدار، ثم تنفيذ استعادة مجهّزة إن وُجدت.
  await BackupService.preOpenSafety();
  await BackupService.applyPendingRestore();
  final db = AppDatabase();
  await db.initDevice(isMobile: Platform.isAndroid || Platform.isIOS);
  await BackupService.afterOpen(db);
  final backup = BackupService(db)..startAuto();
  kCurrency = await db.getSetting('currency') ?? kCurrency;
  kVatRate = int.tryParse(await db.getSetting('vat_rate') ?? '') ?? 0;
  kVatInclusive = (await db.getSetting('vat_inclusive') ?? '0') == '1';
  kBusinessType = await db.getSetting('business_type') ?? 'general';
  final lockMinutes = int.tryParse(await db.getSetting('lock_minutes') ?? '') ?? 10;
  // الجهاز الرئيسي (ديسك توب) يشغّل سيرفر المزامنة المحلي تلقائيًا.
  SyncServer? server;
  if (isHubPlatform) {
    server = SyncServer(db);
    try {
      await server.start();
    } catch (_) {
      // المنفذ مشغول أو محجوب؛ يمكن إعادة المحاولة من شاشة المزامنة.
    }
  }
  runApp(ProviderScope(
    overrides: [
      syncServerProvider.overrideWithValue(server),
      backupServiceProvider.overrideWithValue(backup),
      databaseProvider.overrideWithValue(db),
      lockMinutesProvider.overrideWith((ref) => lockMinutes),
    ],
    child: const MyKashApp(),
  ));
}
